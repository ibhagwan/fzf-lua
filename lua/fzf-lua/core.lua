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

local ACTION_DEFINITIONS = {
  -- list of supported actions with labels to be displayed in the headers
  [actions.grep_lgrep] = { fn_reload = "Fuzzy Search", "Regex Search" },
  [actions.sym_lsym] = { fn_reload = "Fuzzy Search", "Live Query" },
  [actions.buf_del] = { fn_reload = "close", "close" },
}

-- converts contents array sent to `fzf_exec` into a single contents
-- argument with an optional prefix, currently used to combine LSP providers
local contents_from_arr = function(cont_arr)
  -- must have at least one contents item in index 1
  assert(cont_arr[1].contents)
  local cont_type = type(cont_arr[1].contents)
  local contents
  if cont_type == "table" then
    contents = {}
    for _, t in ipairs(cont_arr) do
      assert(type(t.contents) == cont_type, "Unable to combine contents of different types")
      contents = utils.tbl_extend(contents, t.prefix and
        vim.tbl_map(function(x)
          return t.prefix .. x
        end, t.contents)
        or t.contents)
    end
  elseif cont_type == "function" then
    contents = function(fzf_cb)
      coroutine.wrap(function()
        local co = coroutine.running()
        for _, t in ipairs(cont_arr) do
          assert(type(t.contents) == cont_type, "Unable to combine contents of different types")
          local is_async = true
          t.contents(function(entry, cb)
            -- we need to hijack the EOF signal and only send it once the entire dataset
            -- was sent to fzf, if the innner coroutine is different than outer, the caller's
            -- callback is async and we need to yield|resume, otherwise ignore EOF
            is_async = co ~= coroutine.running()
            if entry then
              fzf_cb(t.prefix and t.prefix .. entry or entry, cb)
            elseif is_async then
              coroutine.resume(co)
            end
          end)
          -- wait for EOF if async
          if is_async then
            coroutine.yield()
          end
        end
        -- done
        fzf_cb()
      end)()
    end
  elseif cont_type == "string" then
    assert(false, "Not yet supported")
  end
  return contents
end

-- Main API, see:
-- https://github.com/ibhagwan/fzf-lua/wiki/Advanced
M.fzf_exec = function(contents, opts)
  if type(contents) == "table" and type(contents[1]) == "table" then
    contents = contents_from_arr(contents)
  end
  if not opts or not opts._normalized then
    opts = config.normalize_opts(opts or {}, {})
    if not opts then return end
  end
  opts.fn_selected = opts.fn_selected or function(selected)
    if not selected then return end
    actions.act(opts.actions, selected, opts)
  end
  -- wrapper for command transformer
  if type(contents) == "string" and (opts.fn_transform or opts.fn_preprocess) then
    contents = libuv.spawn_nvim_fzf_cmd({
        cmd = contents,
        cwd = opts.cwd,
        cb_pid = opts._set_pid,
      },
      opts.fn_transform or function(x) return x end,
      opts.fn_preprocess)
  end
  -- setup as "live": disables fuzzy matching and reload the content
  -- every keystroke (query changed), utilizes fzf's 'change:reload'
  -- event trigger or skim's "interactive" mode
  if type(opts.fn_reload) == "string" then
    if not opts.fn_transform then
      -- TODO: add support for 'fn_transform' using 'mt_cmd_wrapper'
      -- functions can be stored using 'config.bytecode' which uses
      -- 'string.dump' to convert from function code to bytes
      opts = M.setup_fzf_interactive_native(opts.fn_reload, opts)
      contents = opts.__fzf_init_cmd
    else
      -- the caller requested to transform, we need to convert
      -- to a function that returns string so that libuv.spawn
      -- is called
      local cmd = opts.fn_reload
      opts.fn_reload = function(q)
        if cmd:match(M.fzf_query_placeholder) then
          return cmd:gsub(M.fzf_query_placeholder, q or "")
        else
          return string.format("%s %s", cmd, q or "")
        end
      end
    end
  end
  if type(opts.fn_reload) == "function" then
    opts.__fn_transform = opts.fn_transform
    opts.__fn_reload = function(query)
      if config.__resume_data then
        config.__resume_data.last_query = query
      end
      return opts.fn_reload(query)
    end
    opts = M.setup_fzf_interactive_wrap(opts)
    contents = opts.__fzf_init_cmd
  end
  return M.fzf_wrap(opts, contents)()
end

M.fzf_live = function(contents, opts)
  assert(contents)
  opts = opts or {}
  opts.fn_reload = contents
  return M.fzf_exec(nil, opts)
end

M.fzf_resume = function(opts)
  if not config.__resume_data or not config.__resume_data.opts then
    utils.info("No resume data available, is 'global_resume' enabled?")
    return
  end
  opts = vim.tbl_deep_extend("force", config.__resume_data.opts, opts or {})
  local last_query = config.__resume_data.last_query
  if not last_query or #last_query == 0 then
    -- in case we continue from another resume,
    -- reset the previous query which was saved
    -- inside "fzf_opts['--query']" argument
    last_query = false
  end
  opts.__resume = true
  opts.query = last_query
  M.fzf_exec(config.__resume_data.contents, opts)
end

M.fzf_wrap = function(opts, contents, fn_selected)
  opts = opts or {}
  return coroutine.wrap(function()
    opts.fn_selected = opts.fn_selected or fn_selected
    local selected = M.fzf(contents, opts)
    if opts.fn_selected then
      opts.fn_selected(selected, opts)
    end
  end)
end

M.fzf = function(contents, opts)
  -- normalize with globals if not already normalized
  if not opts or not opts._normalized then
    opts = config.normalize_opts(opts or {}, {})
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
    -- save a ref to resume data for 'grep_lgrep'
    opts.__resume_data = config.__resume_data
    -- We use this option to print the query on line 1
    -- later to be removed from the result by M.fzf()
    -- this provides a solution for saving the query
    -- when the user pressed a valid bind but not when
    -- aborting with <C-c> or <Esc>, see next comment
    opts.fzf_opts["--print-query"] = ""
    -- setup dummy callbacks for the default fzf 'abort' keybinds
    -- this way the query also gets saved when we do not 'accept'
    opts.actions = opts.actions or {}
    opts.keymap = opts.keymap or {}
    opts.keymap.fzf = opts.keymap.fzf or {}
    for _, k in ipairs({ "ctrl-c", "ctrl-q", "esc" }) do
      if opts.actions[k] == nil and
          (opts.keymap.fzf[k] == nil or opts.keymap.fzf[k] == "abort") then
        opts.actions[k] = actions.dummy_abort
      end
    end
  end
  -- setup the fzf window and preview layout
  local fzf_win = win(opts)
  if not fzf_win then return end
  -- instantiate the previewer
  local previewer, preview_opts = nil, nil
  if opts.previewer and type(opts.previewer) == "string" then
    preview_opts = config.globals.previewers[opts.previewer]
    if not preview_opts then
      utils.warn(("invalid previewer '%s'"):format(opts.previewer))
    end
  elseif opts.previewer and type(opts.previewer) == "table" then
    preview_opts = opts.previewer
  end
  if preview_opts and type(preview_opts.new) == "function" then
    previewer = preview_opts:new(preview_opts, opts, fzf_win)
  elseif preview_opts and type(preview_opts._new) == "function" then
    previewer = preview_opts._new()(preview_opts, opts, fzf_win)
  elseif preview_opts and type(preview_opts._ctor) == "function" then
    previewer = preview_opts._ctor()(preview_opts, opts, fzf_win)
  end
  if previewer then
    -- Set the preview command line
    opts.preview = previewer:cmdline()
    if type(previewer.preview_window) == "function" then
      -- do we need to override the preview_window args?
      -- this can happen with the builtin previewer
      -- (1) when using a split we use the previewer as placeholder
      -- (2) we use 'nohidden:right:0' to trigger preview function
      --     calls without displaying the native fzf previewer split
      opts.fzf_opts["--preview-window"] = previewer:preview_window(opts.preview_window)
    end
    -- provides preview offset when using native previewers
    -- (bat/cat/etc) with providers that supply line numbers
    -- (grep/quickfix/LSP)
    if type(previewer.fzf_delimiter) == "function" then
      opts.fzf_opts["--delimiter"] = previewer:fzf_delimiter()
    end
    if type(previewer.preview_offset) == "function" then
      opts.preview_offset = previewer:preview_offset()
    end
  elseif not opts.preview and not opts.fzf_opts["--preview"] then
    -- no preview available, override in case $FZF_DEFAULT_OPTS
    -- contains a preview which will most likely fail
    opts.fzf_opts["--preview-window"] = "hidden:right:0"
  end

  -- some functions such as buffers|tabs
  -- need to reacquire current buffer|tab state
  if opts.__fn_pre_fzf then opts.__fn_pre_fzf(opts) end
  if opts._fn_pre_fzf then opts._fn_pre_fzf(opts) end
  if opts.fn_pre_fzf then opts.fn_pre_fzf(opts) end

  fzf_win:attach_previewer(previewer)
  fzf_win:create()
  -- save the normalized winopts, otherwise we
  -- lose overrides by 'winopts_fn|winopts_raw'
  opts.winopts.preview = fzf_win.winopts.preview
  local selected, exit_code = fzf.raw_fzf(contents, M.build_fzf_cli(opts),
    {
      fzf_bin = opts.fzf_bin,
      cwd = opts.cwd,
      silent_fail = opts.silent_fail,
      is_fzf_tmux = opts._is_fzf_tmux
    })
  -- kill fzf piped process PID
  -- NOTE: might be an overkill since we're using $FZF_DEFAULT_COMMAND
  -- to spawn the piped process and fzf is responsible for termination
  -- when the fzf process exists
  if type(opts._get_pid == "function") then
    libuv.process_kill(opts._get_pid())
  end
  -- This was added by 'resume': when '--print-query' is specified
  -- we are guaranteed to have the query in the first line, save&remove it
  if selected and #selected > 0 and
      opts.fzf_opts["--print-query"] ~= nil then
    if not (opts._is_skim and opts.fn_reload) then
      -- reminder: this doesn't get called with 'live_grep' when using skim
      -- due to a bug where '--print-query --interactive' combo is broken:
      -- skim always prints an empty line where the typed query should be.
      -- see addtional note above 'opts.fn_post_fzf' inside 'live_grep_mt'
      local query = selected[1]
      config.__resume_data = config.__resume_data or {}
      config.__resume_data.last_query = type(query) == "string" and query or nil
    end
    table.remove(selected, 1)
  end
  if opts.__fn_post_fzf then opts.__fn_post_fzf(opts, selected) end
  if opts._fn_post_fzf then opts._fn_post_fzf(opts, selected) end
  if opts.fn_post_fzf then opts.fn_post_fzf(opts, selected) end
  fzf_win:check_exit_status(exit_code)
  -- retrieve the future action and check:
  --   * if it's a single function we can close the window
  --   * if it's a table of functions we do not close the window
  local keybind = actions.normalize_selected(opts.actions, selected)
  local action = keybind and opts.actions and opts.actions[keybind]
  -- only close the window if autoclose wasn't specified or is 'true'
  if (not fzf_win:autoclose() == false) and type(action) ~= "table" then
    fzf_win:close()
  end
  return selected
end


M.preview_window = function(o)
  local preview_args = ("%s:%s:%s:"):format(
    o.winopts.preview.hidden, o.winopts.preview.border, o.winopts.preview.wrap)
  if o.winopts.preview.layout == "horizontal" or
      o.winopts.preview.layout == "flex" and
      vim.o.columns > o.winopts.preview.flip_columns then
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
M.create_fzf_colors = function(opts)
  local colors = opts and opts.fzf_colors
  if type(colors) == "function" then
    colors = colors(opts)
  end
  if not colors then return end

  local tbl = {}
  for highlight, list in pairs(colors) do
    if type(list) == "table" then
      local value = M.get_color(list[2], list[1])
      local col = value:match("#[%x]+") or value:match("^[0-9]+")
      if col then
        table.insert(tbl, ("%s:%s"):format(highlight, col))
      end
      -- arguments in the 3rd slot onward are passed raw, this can
      -- be used to pass styling arguments, for more info see #413
      -- https://github.com/junegunn/fzf/issues/1663
      for i = 3, #list do
        table.insert(tbl, ("%s:%s"):format(highlight, list[i]))
      end
    elseif type(list) == "string" then
      table.insert(tbl, ("%s:%s"):format(highlight, list))
    end
  end

  return not vim.tbl_isempty(tbl) and table.concat(tbl, ",")
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
    "fzf_ansi",
    "fzf_colors",
    "fzf_layout",
    "keymap",
  }) do
    opts[o] = opts[o] or config.globals[o]
  end
  -- preview and query have special handling:
  --   'opts.<name>' is prioritized over 'fzf_opts[--name]'
  --   'opts.<name>' is automatically shellescaped
  for _, o in ipairs({ "query", "preview" }) do
    local flag = string.format("--%s", o)
    if opts[o] ~= nil then
      -- opt can be 'false' (disabled)
      -- don't shellescape in this case
      opts.fzf_opts[flag] = opts[o] and vim.fn.shellescape(opts[o])
    else
      opts.fzf_opts[flag] = opts.fzf_opts[flag]
    end
  end
  opts.fzf_opts["--bind"] = M.create_fzf_binds(opts.keymap.fzf)
  if opts.fzf_colors then
    opts.fzf_opts["--color"] = M.create_fzf_colors(opts)
  end
  opts.fzf_opts["--expect"] = actions.expect(opts.actions)
  if opts.fzf_opts["--preview-window"] == nil then
    opts.fzf_opts["--preview-window"] = M.preview_window(opts)
  end
  if opts.preview_offset and #opts.preview_offset > 0 then
    opts.fzf_opts["--preview-window"] =
        opts.fzf_opts["--preview-window"] .. ":" .. opts.preview_offset
  end
  -- shell escape the prompt
  opts.fzf_opts["--prompt"] = (opts.prompt or opts.fzf_opts["--prompt"]) and
      vim.fn.shellescape(opts.prompt or opts.fzf_opts["--prompt"])
  -- multi | no-multi (select)
  if opts.nomulti or opts.fzf_opts["--no-multi"] then
    opts.fzf_opts["--multi"] = nil
    opts.fzf_opts["--no-multi"] = ""
  else
    opts.fzf_opts["--multi"] = ""
    opts.fzf_opts["--no-multi"] = nil
  end
  -- backward compatibility, add all previously known options
  for k, v in pairs({
    ["--ansi"] = "fzf_ansi",
    ["--layout"] = "fzf_layout"
  }) do
    if opts[v] and #opts[v] == 0 then
      opts.fzf_opts[k] = nil
    elseif opts[v] then
      opts.fzf_opts[k] = opts[v]
    end
  end
  local extra_args = ""
  for _, o in ipairs({
    "fzf_args",
    "fzf_raw_args",
    "fzf_cli_args",
    "_fzf_cli_args",
  }) do
    if opts[o] then extra_args = extra_args .. " " .. opts[o] end
  end
  if opts._is_skim then
    local info = opts.fzf_opts["--info"]
    -- skim (rust version of fzf) doesn't
    -- support the '--info=' flag
    opts.fzf_opts["--info"] = nil
    if info == "inline" then
      -- inline for skim is defined as:
      opts.fzf_opts["--inline-info"] = ""
    end
    -- skim doesn't accept border args
    local border = opts.fzf_opts["--border"]
    if border == "none" then
      opts.fzf_opts["--border"] = nil
    else
      opts.fzf_opts["--border"] = ""
    end
  end
  -- build the clip args
  local cli_args = ""
  -- fzf-tmux args must be included first
  if opts._is_fzf_tmux then
    for k, v in pairs(opts.fzf_tmux_opts or {}) do
      if v then cli_args = cli_args .. string.format(" %s %s", k, v) end
    end
  end
  for k, v in pairs(opts.fzf_opts) do
    if type(v) == "table" then
      -- table argument is meaningless here
      v = nil
    elseif type(v) == "number" then
      -- convert to string
      v = string.format("%d", v)
    end
    if v then
      v = v:gsub(k .. "=", "")
      cli_args = cli_args ..
          (" %s%s"):format(k, #v > 0 and "=" .. v or "")
    end
  end
  return cli_args .. extra_args
end

M.mt_cmd_wrapper = function(opts)
  assert(opts and opts.cmd)

  local str_to_str = function(s)
    return "[[" .. s:gsub("[%]]", function(x) return "\\" .. x end) .. "]]"
  end

  local opts_to_str = function(o)
    local names = {
      "debug",
      "argv_expr",
      "cmd",
      "cwd",
      "stdout",
      "stderr",
      "stderr_to_stdout",
      "git_dir",
      "git_worktree",
      "git_icons",
      "file_icons",
      "color_icons",
      "path_shorten",
      "strip_cwd_prefix",
      "file_ignore_patterns",
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
        if #str > 0 then str = str .. "," end
        local val = o[name]
        if type(val) == "string" then
          val = str_to_str(val)
        end
        if type(val) == "table" then
          val = vim.inspect(val)
        end
        str = str .. ("%s=%s"):format(name, val)
      end
    end
    return "{" .. str .. "}"
  end

  if not opts.requires_processing and
      not opts.git_icons and not opts.file_icons then
    -- command does not require any processing
    return opts.cmd
  elseif opts.multiprocess then
    assert(not opts.__mt_transform or type(opts.__mt_transform) == "string")
    assert(not opts.__mt_preprocess or type(opts.__mt_preprocess) == "string")
    local fn_preprocess = opts.__mt_preprocess or [[return require("make_entry").preprocess]]
    local fn_transform = opts.__mt_transform or [[return require("make_entry").file]]
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
      fn_transform = ([[_G._devicons_setup=%s; %s]]):format(
        libuv.shellescape(config._devicons_setup),
        fn_transform)
    end
    if config._devicons_path then
      fn_transform = ([[_G._devicons_path=%s; %s]]):format(
        libuv.shellescape(config._devicons_path),
        fn_transform)
    end
    local cmd = libuv.wrap_spawn_stdio(opts_to_str(opts),
      fn_transform, fn_preprocess)
    if opts.debug_cmd or opts.debug and not (opts.debug_cmd == false) then
      print(cmd)
    end
    return cmd
  else
    assert(not opts.__mt_transform or type(opts.__mt_transform) == "function")
    assert(not opts.__mt_preprocess or type(opts.__mt_preprocess) == "function")
    return libuv.spawn_nvim_fzf_cmd(opts,
      function(x)
        return opts.__mt_transform
            and opts.__mt_transform(x, opts)
            or make_entry.file(x, opts)
      end,
      function(o)
        -- setup opts.cwd and git diff files
        return opts.__mt_preprocess
            and opts.__mt_preprocess(o)
            or make_entry.preprocess(o)
      end)
  end
end

-- given the default delimiter ':' this is the
-- fzf expression field index for the line number
-- when entry format is 'file:line:col: text'
-- this is later used with native fzf previewers
-- for setting the preview offset (and on some
-- cases the highlighted line)
M.set_fzf_field_index = function(opts, default_idx, default_expr)
  opts.line_field_index = opts.line_field_index or default_idx or 2
  -- when entry contains lines we set the fzf FIELD INDEX EXPRESSION
  -- to the below so that only the filename is sent to the preview
  -- action, otherwise we will have issues with entries with text
  -- containing '--' as fzf won't know how to interpret the cmd.
  -- this works when the delimiter is only ':', when using multiple
  -- or different delimiters (e.g. in 'lines') we need to use a different
  -- field index expression such as "{..-2}" (all fields but the last 2)
  opts.field_index_expr = opts.field_index_expr or default_expr or "{1}"
  return opts
end

M.set_header = function(opts, hdr_tbl)
  local function normalize_cwd(cwd)
    if path.starts_with_separator(cwd) and cwd ~= vim.loop.cwd() then
      -- since we're always converting cwd to full path
      -- try to convert it back to relative for display
      cwd = path.relative(cwd, vim.loop.cwd())
    end
    -- make our home dir path look pretty
    return path.HOME_to_tilde(cwd)
  end

  if not opts then opts = {} end
  if opts.cwd_prompt or opts.show_cwd_prompt then
    opts.prompt = normalize_cwd(opts.cwd or vim.loop.cwd())
    if not path.ends_with_separator(opts.prompt) then
      opts.prompt = opts.prompt .. path.separator()
    end
  end
  if opts.no_header or opts.headers == false then
    return opts
  end
  local definitions = {
    -- key: opt name
    -- val.hdr_txt_opt: opt header string name
    -- val.hdr_txt_str: opt header string text
    cwd = {
      hdr_txt_opt = "cwd_header",
      hdr_txt_str = "cwd: ",
      hdr_txt_col = "red",
      val = function()
        -- do not display header when we're inside our
        -- cwd unless the caller specifically requested
        if opts.show_cwd_header == false or opts.show_cwd_header == nil and
            (not opts.cwd or opts.cwd == vim.loop.cwd()) then
          return
        end
        return normalize_cwd(opts.cwd or vim.loop.cwd())
      end
    },
    search = {
      hdr_txt_opt = "grep_header",
      hdr_txt_str = "Grep string: ",
      hdr_txt_col = "red",
      val = function()
        return opts.search and #opts.search > 0 and opts.search
      end,
    },
    lsp_query = {
      hdr_txt_opt = "lsp_query_header",
      hdr_txt_str = "Query: ",
      hdr_txt_col = "red",
      val = function()
        return opts.lsp_query and #opts.lsp_query > 0 and opts.lsp_query
      end,
    },
    regex_filter = {
      hdr_txt_opt = "regex_header",
      hdr_txt_str = "Regex filter: ",
      hdr_txt_col = "red",
      val = function()
        return opts.regex_filter and #opts.regex_filter > 0 and opts.regex_filter
      end,
    },
    actions = {
      hdr_txt_opt = "interactive_header",
      hdr_txt_str = "",
      val = function()
        if opts.no_header_i then return end
        local defs = ACTION_DEFINITIONS
        for k, v in pairs(opts.actions) do
          if type(v) == "table" and defs[v[1]] then
            local to = opts.fn_reload and defs[v[1]].fn_reload or defs[v[1]][1]
            return to and (":: <%s> to %s"):format(
              utils.ansi_codes.yellow(k), utils.ansi_codes.red(to))
          end
        end
      end,
    },
  }
  -- by default we only display cwd headers
  -- header string constructed in array order
  if not opts.headers then
    opts.headers = hdr_tbl or { "cwd" }
  end
  -- override header text with the user's settings
  for _, h in ipairs(opts.headers) do
    assert(definitions[h])
    local hdr_text = opts[definitions[h].hdr_txt_opt]
    if hdr_text then
      definitions[h].hdr_txt_str = hdr_text
    end
  end
  -- build the header string
  local hdr_str
  for _, h in ipairs(opts.headers) do
    assert(definitions[h])
    local def = definitions[h]
    local txt = def.val()
    if def and txt then
      hdr_str = not hdr_str and "" or (hdr_str .. ", ")
      hdr_str = ("%s%s%s"):format(hdr_str, def.hdr_txt_str,
        not def.hdr_txt_col and txt or
        utils.ansi_codes[def.hdr_txt_col](txt))
    end
  end
  if hdr_str and #hdr_str > 0 then
    opts.fzf_opts["--header"] = libuv.shellescape(hdr_str)
  end
  return opts
end

M.setup_fzf_interactive_flags = function(command, fzf_field_expression, opts)
  -- query cannot be 'nil'
  opts.query = opts.query or ""

  -- by redirecting the error stream to stdout
  -- we make sure a clear error message is displayed
  -- when the user enters bad regex expressions
  local initial_command = command
  if (opts.stderr_to_stdout ~= false) and
      not initial_command:match("2>") then
    initial_command = command .. " 2>&1"
  end

  local reload_command = initial_command
  if not opts.exec_empty_query then
    reload_command = ("[ -z %s ] || %s"):format(fzf_field_expression, reload_command)
  end
  if opts._is_skim then
    -- skim interactive mode does not need a piped command
    opts.__fzf_init_cmd = nil
    opts.prompt = opts.__prompt or opts.prompt or opts.fzf_opts["--prompt"]
    if opts.prompt then
      opts.fzf_opts["--prompt"] = opts.prompt:match("[^%*]+")
      opts.fzf_opts["--cmd-prompt"] = libuv.shellescape(opts.prompt)
      -- save original prompt and reset the current one since
      -- we're using the '--cmd-prompt' as the "main" prompt
      -- required for resume to have the asterisk prompt prefix
      opts.__prompt = opts.prompt
      opts.prompt = nil
    end
    -- since we surrounded the skim placeholder with quotes
    -- we need to escape them in the initial query
    opts.fzf_opts["--cmd-query"] = libuv.shellescape(utils.sk_escape(opts.query))
    -- '--query' was set by 'resume()', skim has the option to switch back and
    -- forth between interactive command and fuzzy matching (using 'ctrl-q')
    -- setting both '--query' and '--cmd-query' will use <query> to fuzzy match
    -- on top of our result set, double filtering our results (undesirable)
    opts.fzf_opts["--query"] = nil
    opts.query = nil
    -- setup as interactive
    opts._fzf_cli_args = string.format("--interactive --cmd %s",
      libuv.shellescape(reload_command))
  else
    -- **send an empty table to avoid running $FZF_DEFAULT_COMMAND
    -- The above seems to create a hang in some systems
    -- use `true` as $FZF_DEFAULT_COMMAND instead (#510)
    opts.__fzf_init_cmd = "true"
    if opts.exec_empty_query or (opts.query and #opts.query > 0) then
      opts.__fzf_init_cmd = initial_command:gsub(fzf_field_expression,
        libuv.shellescape(opts.query:gsub("%%", "%%%%")))
    end
    opts.fzf_opts["--disabled"] = ""
    opts.fzf_opts["--query"] = libuv.shellescape(opts.query)
    -- OR with true to avoid fzf's "Command failed:" message
    if opts.silent_fail ~= false then
      reload_command = ("%s || true"):format(reload_command)
    end
    opts._fzf_cli_args = string.format("--bind=%s",
      libuv.shellescape(("change:reload:%s"):format(
        ("%s"):format(reload_command))))
  end

  return opts
end

-- query placeholder for "live" queries
M.fzf_query_placeholder = "<query>"

M.fzf_field_expression = function(opts)
  -- fzf already adds single quotes around the placeholder when expanding.
  -- for skim we surround it with double quotes or single quote searches fail
  return opts and opts._is_skim and [["{}"]] or "{q}"
end

-- Sets up the flags and commands required for running a "live" interface
-- @param fn_reload :function called for reloading contents
-- @param fn_transform :function to transform entries when using shell cmd
M.setup_fzf_interactive_wrap = function(opts)
  assert(opts and opts.__fn_reload)

  -- neovim shell wrapper for parsing the query and loading contents
  local fzf_field_expression = M.fzf_field_expression(opts)
  local command = shell.reload_action_cmd(opts, fzf_field_expression)
  return M.setup_fzf_interactive_flags(command, fzf_field_expression, opts)
end

M.setup_fzf_interactive_native = function(command, opts)
  local fzf_field_expression = M.fzf_field_expression(opts)

  -- replace placeholder with the field index expression.
  -- If the command doesn't contain our placeholder, append
  -- the field index expression instead
  if command:match(M.fzf_query_placeholder) then
    command = opts.fn_reload:gsub(M.fzf_query_placeholder, fzf_field_expression)
  else
    command = ("%s %s"):format(command, fzf_field_expression)
  end

  return M.setup_fzf_interactive_flags(command, fzf_field_expression, opts)
end

return M
