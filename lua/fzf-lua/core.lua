local fzf = require "fzf"
local path = require "fzf-lua.path"
local utils = require "fzf-lua.utils"
local config = require "fzf-lua.config"
local actions = require "fzf-lua.actions"
local win = require "fzf-lua.win"

local M = {}

M.fzf = function(opts, contents)
  -- normalize with globals if not already normalized
  if not opts._normalized then
    opts = config.normalize_opts(opts, {})
  end
  -- setup the fzf window and preview layout
  local fzf_win = win(opts)
  if not fzf_win then return end
  -- instantiate the previewer
  local previewer, preview_opts = nil, nil
  if opts.previewer and type(opts.previewer) == 'string' then
    preview_opts = config.globals.previewers[opts.previewer]
    if not preview_opts then
      utils.warn(("invalid previewer '%s'"):format(opts.previewer))
    end
  elseif opts.previewer and type(opts.previewer) == 'table' then
    preview_opts = opts.previewer
  end
  if preview_opts and type(preview_opts._new) == 'function' then
    previewer = preview_opts._new()(preview_opts, opts, fzf_win)
  elseif preview_opts and type(preview_opts._ctor) == 'function' then
    previewer = preview_opts._ctor()(preview_opts, opts, fzf_win)
  end
  if previewer then
    opts.fzf_opts['--preview'] = previewer:cmdline()
    if type(previewer.preview_window) == 'function' then
      -- do we need to override the preview_window args?
      -- this can happen with the builtin previewer
      -- (1) when using a split we use the previewer as placeholder
      -- (2) we use 'nohidden:right:0' to trigger preview function
      --     calls without displaying the native fzf previewer split
      opts.fzf_opts['--preview-window'] = previewer:preview_window(opts.preview_window)
    end
  end

  fzf_win:attach_previewer(previewer)
  fzf_win:create()
  local selected, exit_code = fzf.raw_fzf(contents, M.build_fzf_cli(opts),
    { fzf_binary = opts.fzf_bin, fzf_cwd = opts.cwd })
  utils.process_kill(opts._pid)
  fzf_win:check_exit_status(exit_code)
  if fzf_win:autoclose() == nil or fzf_win:autoclose() then
    fzf_win:close()
  end
  return selected
end

M.get_devicon = function(file, ext)
  local icon, hl
  if config._has_devicons and config._devicons then
    icon, hl  = config._devicons.get_icon(file, ext:lower(), {default = true})
  else
    icon, hl = '', 'dark_grey'
  end

  -- allow user override of the color
  local override = config.globals.file_icon_colors[ext]
  if override then
      hl = override
  end

  return icon..config.globals.file_icon_padding:gsub(" ", utils.nbsp), hl
end

M.preview_window = function(o)
  local preview_args = ("%s:%s:%s:"):format(
    o.winopts.preview.hidden, o.winopts.preview.border, o.winopts.preview.wrap)
  if o.winopts.preview.layout == "horizontal" or
     o.winopts.preview.layout == "flex" and
       vim.o.columns>o.winopts.preview.flip_columns then
    preview_args = preview_args .. o.winopts.preview.horizontal
  else
    preview_args = preview_args .. o.winopts.preview.vertical
  end
  return preview_args
end

M.get_color = function(hl_group, what)
  return vim.fn.synIDattr(vim.fn.synIDtrans(vim.fn.hlID(hl_group)), what)
end

-- Create fzf --color arguments from a table of vim highlight groups.
M.create_fzf_colors = function(colors)
  if not colors then
    return ""
  end

  local tbl = {}
  for highlight, list in pairs(colors) do
    local value = M.get_color(list[2], list[1])
    local col = value:match("#[%x]+") or value:match("^[0-9]+")
    if col then
      table.insert(tbl, ("%s:%s"):format(highlight, col))
    end
  end

  return string.format("--color=%s", table.concat(tbl, ","))
end

M.create_fzf_binds = function(binds)
  if not binds then return '' end
  local tbl = {}
  local dedup = {}
  for k, v in pairs(binds) do
    -- backward compatibility to when binds
    -- where defined as one string '<key>:<command>'
    local key, action = v:match("(.*):(.*)")
    if action then k, v = key, action end
    dedup[k] = v
  end
  for key, action in pairs(dedup) do
    table.insert(tbl, string.format("%s:%s", key, action))
  end
  return "--bind=" .. vim.fn.shellescape(table.concat(tbl, ","))
end

M.build_fzf_cli = function(opts)
  opts.fzf_opts = vim.tbl_extend("force", config.globals.fzf_opts, opts.fzf_opts or {})
  -- copy from globals
  for _, o in ipairs({
    'fzf_info',
    'fzf_ansi',
    'fzf_colors',
    'fzf_layout',
    'fzf_args',
    'fzf_raw_args',
    'fzf_cli_args',
    'keymap',
  }) do
    opts[o] = opts[o] or config.globals[o]
  end
  opts.fzf_opts["--bind"] = M.create_fzf_binds(opts.keymap.fzf)
  if opts.fzf_colors then
    opts.fzf_opts["--color"] = M.create_fzf_colors(opts.fzf_colors)
  end
  opts.fzf_opts["--expect"] = actions.expect(opts.actions)
  opts.fzf_opts["--preview"] = opts.preview or opts.fzf_opts["--preview"]
  if opts.fzf_opts["--preview-window"] == nil then
    opts.fzf_opts["--preview-window"] = M.preview_window(opts)
  end
  if opts.preview_offset and #opts.preview_offset>0 then
    opts.fzf_opts["--preview-window"] =
      opts.fzf_opts["--preview-window"] .. ":" .. opts.preview_offset
  end
  -- shell escape the prompt
  opts.fzf_opts["--prompt"] =
    vim.fn.shellescape(opts.prompt or opts.fzf_opts["--prompt"])
  -- multi | no-multi (select)
  if opts.nomulti or opts.fzf_opts["--no-multi"] then
    opts.fzf_opts["--multi"] = nil
    opts.fzf_opts["--no-multi"] = ''
  else
    opts.fzf_opts["--multi"] = ''
    opts.fzf_opts["--no-multi"] = nil
  end
  -- backward compatibility, add all previously known options
  for k, v in pairs({
    ['--ansi'] = 'fzf_ansi',
    ['--layout'] = 'fzf_layout'
  }) do
    if opts[v] and #opts[v]==0 then
      opts.fzf_opts[k] = nil
    elseif opts[v] then
      opts.fzf_opts[k] = opts[v]
    end
  end
  local extra_args = ''
  for _, o in ipairs({
    'fzf_args',
    'fzf_raw_args',
    'fzf_cli_args',
    '_fzf_cli_args',
  }) do
    if opts[o] then extra_args = extra_args .. " " .. opts[o] end
  end
  if opts._is_skim then
    local info = opts.fzf_opts["--info"]
    -- skim (rust version of fzf) doesn't
    -- support the '--info=' flag
    opts.fzf_opts["--info"] = nil
    if info == 'inline' then
      -- inline for skim is defined as:
      opts.fzf_opts["--inline-info"] = ''
    end
  end
  -- build the clip args
  local cli_args = ''
  for k, v in pairs(opts.fzf_opts) do
    if v then
      v = v:gsub(k .. '=', '')
      cli_args = cli_args ..
        (" %s%s"):format(k,#v>0 and "="..v or '')
    end
  end
  return cli_args .. extra_args
end

local get_diff_files = function(opts)
    local diff_files = {}
    local cmd = opts.git_status_cmd or config.globals.files.git_status_cmd
    if not cmd then return {} end
    local status, err = utils.io_systemlist(path.git_cwd(cmd, opts.cwd))
    if err == 0 then
        for i = 1, #status do
          local icon = status[i]:match("[MUDARC?]+")
          local file = status[i]:match("[^ ]*$")
          if icon and file then
            diff_files[file] = icon
          end
        end
    end

    return diff_files
end

M.make_entry_lcol = function(_, entry)
  if not entry then return nil end
  local filename = entry.filename or vim.api.nvim_buf_get_name(entry.bufnr)
  return string.format("%s:%s:%s:%s%s",
    filename, --utils.ansi_codes.magenta(filename),
    utils.ansi_codes.green(tostring(entry.lnum)),
    utils.ansi_codes.blue(tostring(entry.col)),
    utils._if(entry.text and entry.text:find("^\t"), "", "\t"),
    entry.text)
end

M.make_entry_file = function(opts, x)
  local icon, hl
  local ret = {}
  local file = utils.strip_ansi_coloring(string.match(x, '[^:]*'))
  if opts.cwd_only and path.starts_with_separator(file) then
    local cwd = opts.cwd or vim.loop.cwd()
    if not path.is_relative(file, cwd) then
      return nil
    end
  end
  if opts.cwd and #opts.cwd > 0 then
    -- TODO: does this work if there are ANSI escape codes in x?
    x = path.relative(x, opts.cwd)
  end
  if opts.file_icons then
    local filename = path.tail(file)
    local ext = path.extension(filename)
    icon, hl = M.get_devicon(filename, ext)
    if opts.color_icons then
      -- extra workaround for issue #119 (or similars)
      -- use default if we can't find the highlight ansi
      local fn = utils.ansi_codes[hl] or utils.ansi_codes['dark_grey']
      icon = fn(icon)
    end
    ret[#ret+1] = icon
    ret[#ret+1] = utils.nbsp
  end
  if opts.git_icons then
    local indicators = opts.diff_files and opts.diff_files[file] or utils.nbsp
    for i=1,#indicators do
      icon = indicators:sub(i,i)
      local git_icon = config.globals.git.icons[icon]
      if git_icon then
        icon = git_icon.icon
        if opts.color_icons then
          icon = utils.ansi_codes[git_icon.color or "dark_grey"](icon)
        end
      end
      ret[#ret+1] = icon
    end
    ret[#ret+1] = utils.nbsp
  end
  ret[#ret+1] = x
  return table.concat(ret)
end

M.set_fzf_line_args = function(opts)
  opts._line_placeholder = 2
  -- delimiters are ':' and <tab>
  opts.fzf_opts["--delimiter"] = vim.fn.shellescape('[:\\t]')
  --[[
    #
    #   Explanation of the fzf preview offset options:
    #
    #   ~3    Top 3 lines as the fixed header
    #   +{2}  Base scroll offset extracted from the second field
    #   +3    Extra offset to compensate for the 3-line header
    #   /2    Put in the middle of the preview area
    #
    '--preview-window '~3:+{2}+3/2''
  ]]
  opts.preview_offset = string.format("+{%d}-/2", opts._line_placeholder)
  return opts
end

M.fzf_files = function(opts)

  if not opts then return end

  -- reset git tracking
  opts.diff_files = nil
  if opts.git_icons and not path.is_git_repo(opts.cwd, true) then opts.git_icons = false end

  coroutine.wrap(function ()

    if opts.cwd_only and not opts.cwd then
      opts.cwd = vim.loop.cwd()
    end

    if opts.git_icons then
      opts.diff_files = get_diff_files(opts)
    end

    local has_prefix = opts.file_icons or opts.git_icons or opts.lsp_icons
    if not opts.filespec then
      opts.filespec = utils._if(has_prefix, "{2}", "{1}")
    end


    local selected = M.fzf(opts, opts.fzf_fn)

    if opts.post_select_cb then
      opts.post_select_cb()
    end

    if not selected then return end

    if #selected > 1 then
      for i = 2, #selected do
        selected[i] = path.entry_to_file(selected[i], opts.cwd).noicons
        if opts.cb_selected then
          local cb_ret = opts.cb_selected(opts, selected[i])
          if cb_ret then selected[i] = cb_ret end
        end
      end
    end

    actions.act(opts.actions, selected, opts)

  end)()

end

-- save to upvalue for performance reasons
local string_byte = string.byte
local string_sub = string.sub

local function find_last_newline(str)
  for i=#str,1,-1 do
    if string_byte(str, i) == 10 then
        return i
    end
  end
end

-- https://github.com/luvit/luv/blob/master/docs.md
-- uv.spawn returns tuple: handle, pid
local _, _pid

local function coroutine_callback(fn)
  local co = coroutine.running()
  local callback = function(...)
    if coroutine.status(co) == 'suspended' then
      coroutine.resume(co, ...)
    else
      local pid = unpack({...})
      utils.process_kill(pid)
    end
  end
  fn(callback)
  return coroutine.yield()
end

local function coroutinify(fn)
  return function(...)
    local args = {...}
    return coroutine.wrap(function()
      return coroutine_callback(function(cb)
        table.insert(args, cb)
        fn(unpack(args))
      end)
    end)()
  end
end

M.set_fzf_interactive_cmd = function(opts)

  if not opts then return end

  -- fzf already adds single quotes around the placeholder when expanding
  -- for skim we surround it with double quotes or single quote searches fail
  local placeholder = utils._if(opts._is_skim, '"{}"', '{q}')

  local uv = vim.loop
  local function spawn(pipe, args, cb)
    local shell_cmd = opts._reload_command(args[1])
    local output_pipe = uv.new_pipe(false)
    local error_pipe = uv.new_pipe(false)
    local write_cb_count = 0
    local prev_line_content = nil

    local shell = vim.env.SHELL or "sh"

    local finish = function(_)
      if pipe and not uv.is_closing(pipe) then
        uv.close(pipe)
        pipe = nil
      end
      output_pipe:shutdown()
      error_pipe:shutdown()
      if cb then cb(_pid) end
    end

    -- terminate previously running commands
    utils.process_kill(_pid)

    _, _pid = uv.spawn(shell, {
      args = { "-c", shell_cmd },
      stdio = { nil, output_pipe, error_pipe },
      cwd = opts.cwd
    }, function(code, signal)
      output_pipe:read_stop()
      error_pipe:read_stop()
      output_pipe:close()
      error_pipe :close()
      if write_cb_count==0 then
        -- only close if all our uv.write
        -- calls are completed
        finish(1)
      end
    end)

    -- save current process pid
    local pid = _pid
    opts._pid = _pid

    local function write_cb(data)
      if not pipe then return end
      if pid ~= _pid then
        -- safety, I never saw this get called
        -- will set `pipe = nill`
        finish(2)
        return
      end
      write_cb_count = write_cb_count + 1
      uv.write(pipe, data, function(err)
        if err then
          -- sometime fails?
          -- assert(not err)
          finish(3)
        end
        write_cb_count = write_cb_count - 1
        if write_cb_count == 0 and uv.is_closing(output_pipe) then
          -- spawn callback already called and did not close the pipe
          -- due to write_cb_count>0, since this is the last call
          -- we can close the fzf pipe
          finish(4)
        end
      end)
    end

    local function process_lines(str)
      write_cb(str:gsub("[^\n]+",
        function(x)
          return opts._transform_command(x)
        end))
    end

    local read_cb = function(err, data)

      if err then
        assert(not err)
        finish(5)
      end
      if not data then
        return
      end

      if prev_line_content then
          data = prev_line_content .. data
          prev_line_content = nil
      end

      if not opts._transform_command then
        write_cb(data)
      elseif string_byte(data, #data) == 10 then
        process_lines(data)
      else
        local nl_index = find_last_newline(data)
        if not nl_index then
          prev_line_content = data
        else
          prev_line_content = string_sub(data, nl_index + 1)
          local stripped_with_newline = string_sub(data, 1, nl_index)
          process_lines(stripped_with_newline)
        end
      end

    end

    local err_cb = function(err, data)
      if err then
        assert(not err)
        finish(6)
      end
      if not data then
        return
      end
      write_cb(data)
    end

    output_pipe:read_start(read_cb)
    error_pipe:read_start(err_cb)
  end

  -- local spawn_fn = spawn
  local spawn_fn = coroutinify(spawn)
  local raw_async_act = require("fzf.actions").raw_async_action(spawn_fn, placeholder)

  return M.set_fzf_interactive(opts, raw_async_act, placeholder)
end

M.set_fzf_interactive_cb = function(opts)

  if not opts then return end

  -- fzf already adds single quotes around the placeholder when expanding
  -- for skim we surround it with double quotes or single quote searches fail
  local placeholder = utils._if(opts._is_skim, '"{}"', '{q}')

  local uv = vim.loop
  local raw_async_act = require("fzf.actions").raw_async_action(function(pipe, args)

    local results = opts._reload_action(args[1])

    local close_pipe = function()
      if pipe and not uv.is_closing(pipe) then
        uv.close(pipe)
        pipe = nil
      end
    end

    if type(results) == 'table' then
      for _, entry in ipairs(results) do
        uv.write(pipe, entry .. "\n", function(err)
          if err then
            close_pipe()
          end
        end)
      end
    end

    close_pipe()
  end, placeholder)

  return M.set_fzf_interactive(opts, raw_async_act, placeholder)
end

M.set_fzf_interactive = function(opts, act_cmd, placeholder)

  if not opts or not act_cmd or not placeholder then return end

  -- cannot be nil
  local query = opts.query or ''

  if opts._is_skim then
    -- do not run an empty string query unless the user requested
    if not opts.exec_empty_query then
      act_cmd = "sh -c " .. vim.fn.shellescape(
        ("[ -z %s ] || %s"):format(placeholder, act_cmd))
    else
      act_cmd = vim.fn.shellescape(act_cmd)
    end
    -- skim interactive mode does not need a piped command
    opts.fzf_fn = nil
    opts.fzf_opts['--prompt'] = '*' .. opts.prompt
    opts.fzf_opts['--cmd-prompt'] = vim.fn.shellescape(opts.prompt)
    opts.prompt = nil
    -- since we surrounded the skim placeholder with quotes
    -- we need to escape them in the initial query
    opts.fzf_opts['--cmd-query'] = vim.fn.shellescape(utils.sk_escape(query))
    opts._fzf_cli_args = string.format( "-i -c %s", act_cmd)
  else
    -- fzf already adds single quotes
    -- around the place holder
    opts.fzf_fn = {}
    if opts.exec_empty_query or (query and #query>0) then
      opts.fzf_fn = require("fzf.helpers").cmd_line_transformer(
        { cmd = act_cmd:gsub(placeholder, vim.fn.shellescape(query)),
          cwd = opts.cwd, pid_cb = opts._pid_cb },
        function(x) return x end)
    end
    opts.fzf_opts['--phony'] = ''
    opts.fzf_opts['--query'] = vim.fn.shellescape(query)
    opts._fzf_cli_args = string.format('--bind=%s',
        vim.fn.shellescape(string.format("change:reload:%s || true", act_cmd)))
  end

  return opts

end


return M
