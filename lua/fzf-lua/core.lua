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

M.fzf_resume = function(opts)
  if not config.__resume_data or not config.__resume_data.opts then
    utils.info("No resume data available, is 'global_resume' enabled?")
    return
  end
  opts = vim.tbl_deep_extend("force", config.__resume_data.opts, opts or {})
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
  if opts.__FNCREF__ then
    -- HACK for 'live_grep' and 'lsp_live_workspace_symbols'
    opts.cmd = nil
    opts.query = nil
    opts.search = nil
    opts.continue_last_search = true
    opts.__FNCREF__(opts)
  else
    opts.fzf_opts['--query'] = last_query
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
    if not opts then return end
  end
  if opts.fn_pre_win then
    opts.fn_pre_win(opts)
  end
  -- support global resume?
  if opts.global_resume then
    config.__resume_data = config.__resume_data or {}
    config.__resume_data.opts = utils.deepcopy(opts)
    config.__resume_data.contents = contents and utils.deepcopy(contents) or nil
    if not opts.__resume then
      -- since the shell callback isn't called
      -- until the user first types something
      -- delete the stored query unless called
      -- from within 'fzf_resume', this prevents
      -- using the stored query between different
      -- providers
      config.__resume_data.last_query = nil
    end
  end
  if opts.save_query or
    opts.global_resume and opts.global_resume_query then
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
    -- provides preview offset when using native previewers
    -- (bat/cat/etc) with providers that supply line numbers
    -- (grep/quickfix/LSP)
    if type(previewer.fzf_delimiter) == 'function' then
      opts.fzf_opts["--delimiter"] = previewer:fzf_delimiter()
    end
    if type(previewer.preview_offset) == 'function' then
      opts.preview_offset = previewer:preview_offset()
    end
  elseif not opts.preview and not opts.fzf_opts['--preview'] then
    -- no preview available, override incase $FZF_DEFAULT_OPTS
    -- contains a preview which will most likely fail
    opts.fzf_opts['--preview-window'] = 'hidden:right:0'
  end

  if opts.fn_pre_fzf then
    -- some functions such as buffers|tabs
    -- need to reacquire current buffer|tab state
    opts.fn_pre_fzf(opts)
  end

  fzf_win:attach_previewer(previewer)
  fzf_win:create()
  -- save the normalized winopts, otherwise we
  -- lose overrides by 'winopts_fn|winopts_raw'
  opts.winopts.preview = fzf_win.winopts.preview
  local selected, exit_code = fzf.raw_fzf(contents, M.build_fzf_cli(opts),
    { fzf_binary = opts.fzf_bin, fzf_cwd = opts.cwd })
  -- This was added by 'resume':
  -- when '--print-query' is specified
  -- we are guaranteed to have the query
  -- in the first line, save&remove it
  if selected and #selected>0 and
     opts.fzf_opts['--print-query'] ~= nil then
    if opts.fn_save_query then
      -- reminder: this doesn't get called with 'live_grep' when using skim
      -- due to a bug where '--print-query --interactive' combo is broken:
      -- skim always prints an emtpy line where the typed query should be
      -- see addtional note above 'opts.save_query' inside 'live_grep_mt'
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
      "git_dir",
      "git_worktree",
      "git_icons",
      "file_icons",
      "color_icons",
      "strip_cwd_prefix",
      "rg_glob",
      "__module__",
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

  if not opts.requires_processing and
     not opts.git_icons and not opts.file_icons then
    -- command does not require any processing
    return opts.cmd
  elseif opts.multiprocess then
    local fn_preprocess = opts._fn_preprocess_str or [[return require("make_entry").preprocess]]
    local fn_transform = opts._fn_transform_str or [[return require("make_entry").file]]
    -- replace all below 'fn.shellescape' with our version
    -- replacing the surrounding single quotes with double
    -- as this was causing resume to fail with fish shell
    -- due to fzf replacing ' with \ (no idea why)
    if not opts.no_remote_config then
      fn_transform = ([[_G._fzf_lua_server=%s; %s]]):format(
        libuv.shellescape(vim.g.fzf_lua_server),
        fn_transform)
    end
    if config._devicons_setup then
      fn_transform = ([[_G._devicons_setup=%s; %s]]) :format(
          libuv.shellescape(config._devicons_setup),
          fn_transform)
    end
    if config._devicons_path then
      fn_transform = ([[_G._devicons_path=%s; %s]]) :format(
          libuv.shellescape(config._devicons_path),
          fn_transform)
    end
    local cmd = libuv.wrap_spawn_stdio(opts_to_str(opts),
      fn_transform, fn_preprocess)
    if opts.debug_cmd or opts.debug and not (opts.debug_cmd==false) then
      print(cmd)
    end
    return cmd
  else
    return libuv.spawn_nvim_fzf_cmd(opts,
      function(x)
        return opts._fn_transform
          and opts._fn_transform(opts, x)
          or make_entry.file(opts, x)
      end,
      function(o)
        -- setup opts.cwd and git diff files
        return opts._fn_preprocess
          and opts._fn_preprocess(o)
          or make_entry.preprocess(o)
      end)
  end
end

-- shortcuts to make_entry
M.get_devicon = make_entry.get_devicon
M.make_entry_file = make_entry.file
M.make_entry_preprocess = make_entry.preprocess

M.make_entry_lcol = function(opts, entry)
  if not entry then return nil end
  local filename = entry.filename or vim.api.nvim_buf_get_name(entry.bufnr)
  return string.format("%s:%s:%s:%s%s",
    -- uncomment to test URIs
    -- "file://" .. filename,
    filename, --utils.ansi_codes.magenta(filename),
    utils.ansi_codes.green(tostring(entry.lnum)),
    utils.ansi_codes.blue(tostring(entry.col)),
    entry.text and #entry.text>0 and " " or "",
    not entry.text and "" or
      (opts.trim_entry and vim.trim(entry.text)) or entry.text)
end

-- given the default delimiter ':' this is the
-- fzf experssion field index for the line number
-- when entry format is 'file:line:col: text'
-- this is later used with native fzf previewers
-- for setting the preview offset (and on some
-- cases the highlighted line)
M.set_fzf_field_index = function(opts, default_idx, default_expr)
  opts.line_field_index = opts.line_field_index or default_idx or 2
  -- when entry contains lines we set the fzf FIELD INDEX EXPRESSION
  -- to the below so that only the filename is sent to the preview
  -- action, otherwise we will have issues with entries with text
  -- containing '--' as fzf won't know how to interpret the cmd
  -- this works when the delimiter is only ':', when using multiple
  -- or different delimiters (e.g. in 'lines') we need to use a different
  -- field index experssion such as "{..-2}" (all fields but the last 2)
  opts.field_index_expr = opts.field_index_expr or default_expr or "{1}"
  return opts
end

M.set_header = function(opts, flags)
  if not opts then opts = {} end
  if opts.no_header then return opts end
  if not opts.cwd_header then opts.cwd_header = "cwd:" end
  if not opts.grep_header then opts.grep_header = "Grep string:" end
  if not opts.cwd and opts.show_cwd_header then opts.cwd = vim.loop.cwd() end
  local cwd_str, header_str
  local search_str = flags ~= 2 and opts.search and #opts.search>0 and
    ("%s %s"):format(opts.grep_header, utils.ansi_codes.red(opts.search))
  if flags ~= 1 and opts.cwd and
    (opts.show_cwd_header ~= false) and
    (opts.show_cwd_header or opts.cwd ~= vim.loop.cwd()) then
    local cwd = opts.cwd
    if path.starts_with_separator(cwd) and cwd ~= vim.loop.cwd() then
      -- since we're always converting cwd to full path
      -- try to convert it back to relative for display
      cwd = path.relative(cwd, vim.loop.cwd())
    end
    -- make our home dir path look pretty
    cwd = cwd:gsub("^"..vim.env.HOME, "~")
    cwd_str = ("%s %s"):format(opts.cwd_header, utils.ansi_codes.red(cwd))
  end
  -- 1: only search
  -- 2: only cwd
  -- otherwise, all
  if flags == 1 then header_str = search_str or ''
  elseif flags == 2 then header_str = cwd_str or ''
  else
    header_str = ("%s%s%s"):format(
      cwd_str and cwd_str or '',
      cwd_str and search_str and ', ' or '',
      search_str and search_str or '')
  end
  -- check for 'actions.grep_lgrep' and "ineteractive" header
  if not opts.no_header_i then
    for k, v in pairs(opts.actions) do
      if type(v) == 'table' and v[1] == actions.grep_lgrep then
        local to = opts.__FNCREF__ and 'Grep' or 'Live Grep'
        header_str = (':: <%s> to %s%s'):format(
          utils.ansi_codes.yellow(k),
          utils.ansi_codes.red(to),
          header_str and #header_str>0 and ", "..header_str or '')
      end
    end
  end
  if not header_str or #header_str==0 then return opts end
  opts.fzf_opts['--header'] = libuv.shellescape(header_str)
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
    opts.fzf_opts['--prompt'] = opts.prompt:match("[^%*]+")
    opts.fzf_opts['--cmd-prompt'] = libuv.shellescape(opts.prompt)
    opts.prompt = nil
    -- since we surrounded the skim placeholder with quotes
    -- we need to escape them in the initial query
    opts.fzf_opts['--cmd-query'] = libuv.shellescape(utils.sk_escape(query))
    opts._fzf_cli_args = string.format( "-i -c %s", act_cmd)
  else
    -- fzf already adds single quotes
    -- around the place holder
    opts.fzf_fn = {}
    if opts.exec_empty_query or (query and #query>0) then
      opts.fzf_fn = act_cmd:gsub(placeholder,
          #query>0 and utils.lua_escape(libuv.shellescape(query)) or "''")
    end
    opts.fzf_opts['--phony'] = ''
    opts.fzf_opts['--query'] = libuv.shellescape(query)
    opts._fzf_cli_args = string.format('--bind=%s',
        vim.fn.shellescape(string.format("change:reload:%s || true", act_cmd)))
  end

  return opts

end


return M
