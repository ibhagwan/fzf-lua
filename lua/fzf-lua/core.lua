local fzf = require "fzf-lua.fzf"
local path = require "fzf-lua.path"
local utils = require "fzf-lua.utils"
local config = require "fzf-lua.config"
local actions = require "fzf-lua.actions"
local win = require "fzf-lua.win"
local libuv = require "fzf-lua.libuv"
local shell = require "fzf-lua.shell"
local make_entry = require "fzf-lua.make_entry"

local M = {}

M.fzf_resume = function()
  if not config.__resume_data or not config.__resume_data.opts then
    utils.info("No resume data available, is 'global_resume' enabled?")
    return
  end
  local opts = config.__resume_data.opts
  local last_query = config.__resume_data.last_query
  if last_query and #last_query>0 then
    last_query = vim.fn.shellescape(last_query)
  else
    -- in case we continue from another resume
    -- reset the previous query which was saved
    -- inside "fzf_opts['--query']" argument
    last_query = false
  end
  opts.__resume = true
  opts.fzf_opts['--query'] = last_query
  if opts.__FNCREF__ then
    -- HACK for 'live_grep' and 'lsp_live_workspace_symbols'
    opts.__FNCREF__({ continue_last_search = true })
  else
    M.fzf_wrap(opts, config.__resume_data.contents)()
  end
end

M.fzf_wrap = function(opts, contents, fn_selected)
  return coroutine.wrap(function()
    opts.fn_selected = opts.fn_selected or fn_selected
    local selected = M.fzf(opts, contents)
    if opts.fn_selected then
      opts.fn_selected(selected)
    end
  end)
end

M.fzf = function(opts, contents)
  -- normalize with globals if not already normalized
  if not opts._normalized then
    opts = config.normalize_opts(opts, {})
  end
  if opts.fn_pre_win then
    opts.fn_pre_win(opts)
  end
  -- support global resume?
  if opts.global_resume then
    config.__resume_data = config.__resume_data or {}
    config.__resume_data.opts = vim.deepcopy(opts)
    config.__resume_data.contents = contents and vim.deepcopy(contents) or nil
    if not opts.__resume then
      -- since the shell callback isn't called
      -- until the user first types something
      -- delete the stored query unless called
      -- from within 'fzf_resume', this prevents
      -- using the stored query between different
      -- providers
      config.__resume_data.last_query = nil
    end
    if opts.global_resume_query then
      -- We use this option to print the query on line 1
      -- later to be removed from the result by M.fzf()
      -- this providers a solution for saving the query
      -- when the user pressed a valid bind but not when
      -- aborting with <C-c> or <Esc>, see next comment
      opts.fzf_opts['--print-query'] = ''
      -- Signals to the win object resume is enabled
      -- so we can setup the keypress event monitoring
      -- since we already have the query on valid
      -- exit codes we only need to monitor <C-c>, <Esc>
      opts.fn_save_query = function(query)
        config.__resume_data.last_query = query and #query>0 and query or nil
      end
      -- 'au InsertCharPre' would be the best option here
      -- but it does not work for terminals:
      -- https://github.com/neovim/neovim/issues/5018
      -- this is causing lag when typing too fast (#271)
      -- also not possible with skim (no 'change' event)
      --[[ if not opts._is_skim then
        local raw_act = shell.raw_action(function(args)
          opts.fn_save_query(args[1])
        end, "{q}")
        opts._fzf_cli_args = ('--bind=change:execute-silent:%s'):
          format(vim.fn.shellescape(raw_act))
      end ]]
    end
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
  if preview_opts and type(preview_opts.new) == 'function' then
    previewer = preview_opts:new(preview_opts, opts, fzf_win)
  elseif preview_opts and type(preview_opts._new) == 'function' then
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

  if opts.fn_pre_fzf then
    -- some functions such as buffers|tabs
    -- need to reacquire current buffer|tab state
    opts.fn_pre_fzf(opts)
  end

  fzf_win:attach_previewer(previewer)
  fzf_win:create()
  local selected, exit_code = fzf.raw_fzf(contents, M.build_fzf_cli(opts),
    { fzf_binary = opts.fzf_bin, fzf_cwd = opts.cwd })
  -- This was added by 'resume':
  -- when '--print-query' is specified
  -- we are guaranteed to have the query
  -- in the first line, save&remove it
  if selected and #selected>0 and
     opts.fzf_opts['--print-query'] ~= nil then
    if opts.fn_save_query then
      opts.fn_save_query(selected[1])
    end
    table.remove(selected, 1)
  end
  if opts.fn_post_fzf then
    opts.fn_post_fzf(opts, selected)
  end
  libuv.process_kill(opts._pid)
  fzf_win:check_exit_status(exit_code)
  -- retrieve the future action and check:
  --   * if it's a single function we can close the window
  --   * if it's a table of functions we do not close the window
  local keybind = actions.normalize_selected(opts.actions, selected)
  local action = keybind and opts.actions and opts.actions[keybind]
  -- only close the window if autoclose wasn't specified or is 'true'
  if (not fzf_win:autoclose() == false) and type(action) ~= 'table' then
    fzf_win:close()
  end
  return selected
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
  if not binds or vim.tbl_isempty(binds) then return end
  local tbl = {}
  local dedup = {}
  for k, v in pairs(binds) do
    -- backward compatibility to when binds
    -- where defined as one string '<key>:<command>'
    if v then
      local key, action = v:match("(.*):(.*)")
      if action then k, v = key, action end
      dedup[k] = v
    end
  end
  for key, action in pairs(dedup) do
    table.insert(tbl, string.format("%s:%s", key, action))
  end
  return vim.fn.shellescape(table.concat(tbl, ","))
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

M.mt_cmd_wrapper = function(opts)
  assert(opts and opts.cmd)

  local str_to_str = function(s)
    return "[[" .. s:gsub('[%]]', function(x) return "\\"..x end) .. "]]"
  end

  local opts_to_str = function(o)
    local names = {
      "debug",
      "argv_expr",
      "cmd",
      "cwd",
      "git_icons",
      "file_icons",
      "color_icons",
      "strip_cwd_prefix",
      "rg_glob",
    }
    -- caller reqested rg with glob support
    if o.rg_glob then
      table.insert(names, "glob_flag")
      table.insert(names, "glob_separator")
    end
    local str = ""
    for _, name in ipairs(names) do
      if o[name] ~= nil then
        if #str>0 then str = str..',' end
        local val = o[name]
        if type(val) == 'string' then
          val = str_to_str(val)
        end
        if type(val) == 'table' then
          val = vim.inspect(val)
        end
        str = str .. ("%s=%s"):format(name, val)
      end
    end
    return '{'..str..'}'
  end

  if not opts.force_multiprocess and
     not opts.git_icons and not opts.file_icons then
    -- command does not require any processing
    return opts.cmd
  elseif opts.multiprocess or opts.force_multiprocess then
    local fn_preprocess = [[return require("make_entry").preprocess]]
    local fn_transform = [[return require("make_entry").file]]
    if not opts.no_remote_config then
      fn_transform = ([[_G._fzf_lua_server=%s; %s]]):format(
        vim.fn.shellescape(vim.g.fzf_lua_server),
        fn_transform)
    end
    if config._devicons_setup then
      fn_transform = ([[_G._devicons_setup=%s; %s]]) :format(
          vim.fn.shellescape(config._devicons_setup),
          fn_transform)
    end
    if config._devicons_path then
      fn_transform = ([[_G._devicons_path=%s; %s]]) :format(
          vim.fn.shellescape(config._devicons_path),
          fn_transform)
    end
    local cmd = libuv.wrap_spawn_stdio(opts_to_str(opts),
      fn_transform, fn_preprocess)
    if opts.debug then print(cmd) end
    return cmd
  else
    return libuv.spawn_nvim_fzf_cmd(opts,
      function(x)
        return make_entry.file(opts, x)
      end,
      function(o)
        -- setup opts.cwd and git diff files
        return make_entry.preprocess(o)
      end)
  end
end

-- shortcuts to make_entry
M.get_devicon = make_entry.get_devicon
M.make_entry_file = make_entry.file
M.make_entry_preprocess = make_entry.preprocess

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

M.set_header = function(opts, type)
  if not opts then opts = {} end
  if opts.no_header then return opts end
  if not opts.cwd_header then opts.cwd_header = "cwd:" end
  if not opts.search_header then opts.search_header = "Searching for:" end
  if not opts.cwd and opts.show_cwd_header then opts.cwd = vim.loop.cwd() end
  local header_str
  local cwd_str =
    opts.cwd and (opts.show_cwd_header ~= false) and
    (opts.show_cwd_header or opts.cwd ~= vim.loop.cwd()) and
    ("%s %s"):format(opts.cwd_header, opts.cwd:gsub("^"..vim.env.HOME, "~"))
  local search_str = opts.search and #opts.search > 0 and
    ("%s %s"):format(opts.search_header, opts.search)
  -- 1: only search
  -- 2: only cwd
  -- otherwise, all
  if type == 1 then header_str = search_str or ''
  elseif type == 2 then header_str = cwd_str or ''
  else
    header_str = search_str or ''
    if #header_str>0 and cwd_str and #cwd_str>0 then
      header_str = header_str .. ", "
    end
    header_str = header_str .. (cwd_str or '')
  end
  if not header_str or #header_str==0 then return opts end
  opts.fzf_opts['--header'] = vim.fn.shellescape(header_str)
  return opts
end


M.fzf_files = function(opts, contents)

  if not opts then return end


  M.fzf_wrap(opts, contents or opts.fzf_fn, function(selected)

    if opts.post_select_cb then
      opts.post_select_cb()
    end

    if not selected then return end

    if #selected > 1 then
      local idx = utils.tbl_length(opts.actions)>1 and 2 or 1
      for i = idx, #selected do
        selected[i] = path.entry_to_file(selected[i], opts.cwd).stripped
      end
    end

    actions.act(opts.actions, selected, opts)

  end)()

end

M.set_fzf_interactive_cmd = function(opts)

  if not opts then return end

  -- fzf already adds single quotes around the placeholder when expanding
  -- for skim we surround it with double quotes or single quote searches fail
  local placeholder = utils._if(opts._is_skim, '"{}"', '{q}')
  local raw_async_act = shell.reload_action_cmd(opts, placeholder)
  return M.set_fzf_interactive(opts, raw_async_act, placeholder)
end

M.set_fzf_interactive_cb = function(opts)

  if not opts then return end

  -- fzf already adds single quotes around the placeholder when expanding
  -- for skim we surround it with double quotes or single quote searches fail
  local placeholder = utils._if(opts._is_skim, '"{}"', '{q}')

  local uv = vim.loop
  local raw_async_act = shell.raw_async_action(function(pipe, args)

    coroutine.wrap(function()

      local co = coroutine.running()
      local results = opts._reload_action(args[1])

      local close_pipe = function()
        if pipe and not uv.is_closing(pipe) then
          uv.close(pipe)
          pipe = nil
        end
        coroutine.resume(co)
      end

      if type(results) == 'table' and not vim.tbl_isempty(results) then
        uv.write(pipe,
          vim.tbl_map(function(x) return x.."\n" end, results),
          function(_)
            close_pipe()
          end)
        -- wait for write to finish
        coroutine.yield()
      end
      -- does nothing if write finished successfully
      close_pipe()

    end)()
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
      opts.fzf_fn = act_cmd:gsub(placeholder,
          #query>0 and utils.lua_escape(vim.fn.shellescape(query)) or "''")
    end
    opts.fzf_opts['--phony'] = ''
    opts.fzf_opts['--query'] = vim.fn.shellescape(query)
    opts._fzf_cli_args = string.format('--bind=%s',
        vim.fn.shellescape(string.format("change:reload:%s || true", act_cmd)))
  end

  return opts

end


return M
