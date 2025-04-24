local uv = vim.uv or vim.loop
local fzf = require "fzf-lua.fzf"
local path = require "fzf-lua.path"
local utils = require "fzf-lua.utils"
local config = require "fzf-lua.config"
local actions = require "fzf-lua.actions"
local win = require "fzf-lua.win"
local libuv = require "fzf-lua.libuv"
local shell = require "fzf-lua.shell"
local make_entry = require "fzf-lua.make_entry"
local base64 = require "fzf-lua.lib.base64"
local serpent = require "fzf-lua.lib.serpent"

local M = {}

M.ACTION_DEFINITIONS = {
  -- list of supported actions with labels to be displayed in the headers
  -- no pos implies an append to header array
  [actions.toggle_ignore]     = {
    function(o)
      local flag = o.toggle_ignore_flag or "--no-ignore"
      if o.cmd and o.cmd:match(utils.lua_regex_escape(flag)) then
        return "Respect .gitignore"
      else
        return "Disable .gitignore"
      end
    end,
  },
  [actions.toggle_hidden]     = {
    function(o)
      local flag = o.toggle_hidden_flag or "--hidden"
      if o.cmd and o.cmd:match(utils.lua_regex_escape(flag)) then
        return "Exclude hidden files"
      else
        return "Include hidden files"
      end
    end,
  },
  [actions.toggle_follow]     = {
    function(o)
      local flag = o.toggle_follow_flag or "-L"
      if o.cmd and o.cmd:match(utils.lua_regex_escape(flag)) then
        return "Disable symlink follow"
      else
        return "Enable symlink follow"
      end
    end,
  },
  [actions.grep_lgrep]        = {
    function(o)
      if o.fn_reload then
        return "Fuzzy Search"
      else
        return "Regex Search"
      end
    end,
  },
  [actions.sym_lsym]          = {
    function(o)
      if o.fn_reload then
        return "Fuzzy Search"
      else
        return "Live Query"
      end
    end,
  },
  [actions.toggle_bg]         = {
    function(_)
      -- return string.format("set bg=%s", vim.o.background == "dark" and "light" or "dark")
      return "toggle bg"
    end,
  },
  [actions.buf_del]           = { "close" },
  [actions.arg_del]           = { "delete" },
  [actions.dap_bp_del]        = { "delete" },
  [actions.cs_delete]         = { "uninstall" },
  [actions.cs_update]         = { "[down|re]-load" },
  [actions.git_reset]         = { "reset" },
  [actions.git_stage]         = { "stage", pos = 1 },
  [actions.git_unstage]       = { "unstage", pos = 2 },
  [actions.git_stage_unstage] = { "[un-]stage", pos = 1 },
  [actions.git_stash_drop]    = { "drop a stash" },
  [actions.git_yank_commit]   = { "copy commit hash" },
  [actions.git_branch_add]    = { "add branch" },
  [actions.git_branch_del]    = { "delete branch" },
  [actions.ex_run]            = { "edit" },
  [actions.ex_run_cr]         = { "execute" },
  [actions.search]            = { "edit" },
  [actions.search_cr]         = { "search" },
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
      contents = utils.tbl_join(contents, t.prefix and
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

---@alias content (string|number)[]|fun(fzf_cb: fun(entry?: string|number, cb?: function))|string|nil

-- Main API, see:
-- https://github.com/ibhagwan/fzf-lua/wiki/Advanced
---@param contents content
---@param opts? {fn_reload: string|function, fn_transform: function, __fzf_init_cmd: string, _normalized: boolean}
M.fzf_exec = function(contents, opts)
  if type(contents) == "table" and type(contents[1]) == "table" then
    contents = contents_from_arr(contents)
  end
  if not opts or not opts._normalized then
    opts = config.normalize_opts(opts or {}, {})
    if not opts then return end
  end
  -- save a copy of cprovider info in the opts, we later use it for better named
  -- quickfix lists, use `pcall` because we will circular ref main object (#776)
  _, opts.__INFO = pcall(loadstring("return require'fzf-lua'.get_info()"))
  opts.fn_selected = opts.fn_selected or function(selected, o)
    actions.act(selected, o)
  end
  -- wrapper for command transformer
  if type(contents) == "string" and (opts.fn_transform or opts.fn_preprocess) then
    contents = libuv.spawn_nvim_fzf_cmd({
        cmd = contents,
        cwd = opts.cwd,
        cb_pid = function(pid) opts.__pid = pid end,
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
      local cmd = opts.fn_reload --[[@as string]]
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
      config.resume_set("query", query, opts)
      return opts.fn_reload(query)
    end
    opts = M.setup_fzf_interactive_wrap(opts)
    contents = opts.__fzf_init_cmd
  end
  return M.fzf_wrap(opts, contents)
end

---@param contents string|fun(query: string): string|string[]|function
---@param opts? table
M.fzf_live = function(contents, opts)
  assert(contents)
  opts = opts or {}
  opts.fn_reload = contents
  return M.fzf_exec(nil, opts)
end

M.fzf_resume = function(opts)
  -- First try to unhide the window
  if win.unhide() then return end
  if not config.__resume_data or not config.__resume_data.opts then
    utils.info("No resume data available.")
    return
  end
  opts = vim.tbl_deep_extend("force", config.__resume_data.opts, opts or {})
  opts = M.set_header(opts, opts.headers or {})
  opts.cwd = opts.cwd and libuv.expand(opts.cwd) or nil
  opts.__resuming = true
  M.fzf_exec(config.__resume_data.contents, opts)
end

---@param opts table
---@param contents content
---@param fn_selected function?
---@return thread
M.fzf_wrap = function(opts, contents, fn_selected)
  opts = opts or {}
  local _co
  coroutine.wrap(function()
    _co = coroutine.running()
    if type(opts.cb_co) == "function" then opts.cb_co(_co) end
    opts.fn_selected = opts.fn_selected or fn_selected
    local selected = M.fzf(contents, opts)
    if opts.fn_selected then
      -- errors thrown here gets silenced possibly
      -- due to a coroutine, so catch explicitly
      xpcall(function()
        opts.fn_selected(selected, opts)
      end, function(err)
        -- ignore existing swap file error, the choices dialog will still be
        -- displayed to user to make a selection once fzf-lua exits (#1011)
        if err:match("Vim%(edit%):E325") then
          return
        end
        utils.err("fn_selected threw an error: " .. debug.traceback(err, 1))
      end)
    end
  end)()
  return _co
end

-- conditionally update the context if fzf-lua
-- interface isn't open
M.CTX = function(opts)
  opts = opts or {}
  -- save caller win/buf context, ignore when fzf
  -- is already open (actions.sym_lsym|grep_lgrep)
  local winobj = utils.fzf_winobj()
  if not M.__CTX
      -- when called from the LSP module in "sync" mode when no results are found
      -- the fzf window won't open (e.g. "No references found") and the context is
      -- never cleared. The below condition validates the source window when the
      -- UI is not open (#907)
      or (not winobj and M.__CTX.bufnr ~= vim.api.nvim_get_current_buf())
      -- we should never get here when fzf process is hidden unless the user requested
      -- not to resume or a different picker, i.e. hide files and open buffers
      or winobj and winobj:hidden()
  then
    M.__CTX = {
      mode = vim.api.nvim_get_mode().mode,
      bufnr = vim.api.nvim_get_current_buf(),
      bname = vim.api.nvim_buf_get_name(0),
      winid = vim.api.nvim_get_current_win(),
      alt_bufnr = vim.fn.bufnr("#"),
      tabnr = vim.fn.tabpagenr(),
      tabh = vim.api.nvim_win_get_tabpage(0),
      cursor = vim.api.nvim_win_get_cursor(0),
      line = vim.api.nvim_get_current_line(),
      curtab_wins = (function()
        local ret = {}
        local wins = vim.api.nvim_tabpage_list_wins(0)
        for _, w in ipairs(wins) do
          ret[tostring(w)] = true
        end
        return ret
      end)()
    }
  end
  -- perhaps a min impact optimization but since only
  -- buffers/tabs use these we only include the current
  -- list of buffers when requested
  if opts.includeBuflist and not M.__CTX.buflist then
    -- also add a map for faster lookups than `utils.tbl_contains`
    -- TODO: is it really faster since we must use string keys?
    M.__CTX.bufmap = {}
    M.__CTX.buflist = vim.api.nvim_list_bufs()
    for _, b in ipairs(M.__CTX.buflist) do
      M.__CTX.bufmap[tostring(b)] = true
    end
  end
  -- custom bufnr from caller? (#1757)
  local bufnr = tonumber(opts.buf) or tonumber(opts.bufnr)
  if bufnr then
    M.__CTX.bufnr = bufnr
    M.__CTX.bname = vim.api.nvim_buf_get_name(bufnr)
  end
  return M.__CTX
end

---@param contents content
---@param opts table?
---@return string[]?
M.fzf = function(contents, opts)
  -- Disable opening from the command-line window `:q`
  -- creates all kinds of issues, will fail on `nvim_win_close`
  if vim.fn.win_gettype() == "command" then
    utils.info("Unable to open from the command-line window. See `:help E11`.")
    return
  end
  -- normalize with globals if not already normalized
  if not opts or not opts._normalized then
    opts = config.normalize_opts(opts or {}, {})
    if not opts then return end
  end
  -- flag used to print the query on stdout line 1
  -- later to be removed from the result by M.fzf()
  -- this provides a solution for saving the query
  -- when the user pressed a valid bind but not when
  -- aborting with <C-c> or <Esc>, see next comment
  opts.fzf_opts["--print-query"] = true
  -- setup dummy callbacks for the default fzf 'abort' keybinds
  -- this way the query also gets saved when we do not 'accept'
  opts.actions = opts.actions or {}
  opts.keymap = opts.keymap or {}
  opts.keymap.fzf = opts.keymap.fzf or {}
  for _, k in ipairs({ "ctrl-c", "ctrl-q", "esc", "enter" }) do
    if opts.actions[k] == nil and (opts.keymap.fzf[k] == nil or opts.keymap.fzf[k] == "abort")
    then
      opts.actions[k] = actions.dummy_abort
    end
  end
  if not opts.__resuming then
    -- `opts.__resuming` is only set from `fzf_resume`, since we
    -- not resuming clear the shell protected functions registry
    shell.clear_protected()
  end
  -- store last call opts for resume
  config.resume_set(nil, opts.__call_opts, opts)
  -- caller specified not to resume this call (used by "builtin" provider)
  if not opts.no_resume then
    config.__resume_data = config.__resume_data or {}
    config.__resume_data.opts = utils.deepcopy(opts)
    config.__resume_data.contents = contents and utils.deepcopy(contents) or nil
  end
  -- update context and save a copy in options (for actions)
  -- call before creating the window or fzf_winobj is not nil
  opts.__CTX = M.CTX(opts.ctx)
  if opts.fn_pre_win then
    opts.fn_pre_win(opts)
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
    -- fzf 0.40 added 'zero' event for when there's no match
    -- clears the preview when there are no matching entries
    if utils.has(opts, "fzf", { 0, 40 }) and previewer.zero then
      utils.map_set(opts, "keymap.fzf.zero", previewer:zero())
    end
    if type(previewer.preview_window) == "function" then
      -- do we need to override the preview_window args?
      -- this can happen with the builtin previewer
      -- (1) when using a split we use the previewer as placeholder
      -- (2) we use 'nohidden:right:0' to trigger preview function
      --     calls without displaying the native fzf previewer split
      opts.fzf_opts["--preview-window"] = previewer:preview_window()
    end
    -- provides preview offset when using native previewers
    -- (bat/cat/etc) with providers that supply line numbers
    -- (grep/quickfix/LSP)
    if type(previewer.fzf_delimiter) == "function" then
      opts.fzf_opts["--delimiter"] = previewer:fzf_delimiter()
    end
    if opts.preview_offset == nil and type(previewer._preview_offset) == "function" then
      opts.preview_offset = previewer:_preview_offset()
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
  local fzf_bufnr = fzf_win:create()
  -- convert "reload" actions to fzf's `reload` binds
  -- convert "exec_silent" actions to fzf's `execute-silent` binds
  opts = M.convert_reload_actions(opts.__reload_cmd or contents, opts)
  opts = M.convert_exec_silent_actions(opts)
  local selected, exit_code = fzf.raw_fzf(contents, M.build_fzf_cli(opts, fzf_win),
    {
      fzf_bin = opts.fzf_bin,
      cwd = opts.cwd,
      pipe_cmd = opts.pipe_cmd,
      silent_fail = opts.silent_fail,
      is_fzf_tmux = opts._is_fzf_tmux,
      debug = opts.debug == true or opts.debug == "verbose",
      RIPGREP_CONFIG_PATH = opts.RIPGREP_CONFIG_PATH,
    })
  -- kill fzf piped process PID
  -- NOTE: might be an overkill since we're using $FZF_DEFAULT_COMMAND
  -- to spawn the piped process and fzf is responsible for termination
  -- when the fzf process exists
  if tonumber(opts.__pid) then
    libuv.process_kill(opts.__pid)
  end
  -- If a hidden process was killed by [re-]starting a new picker do nothing
  if fzf_win:was_hidden() then return end
  -- This was added by 'resume': when '--print-query' is specified
  -- we are guaranteed to have the query in the first line, save&remove it
  if selected and #selected > 0 then
    if not (opts._is_skim and opts.fn_reload) then
      -- reminder: this doesn't get called with 'live_grep' when using skim
      -- due to a bug where '--print-query --interactive' combo is broken:
      -- skim always prints an empty line where the typed query should be.
      -- see additional note above 'opts.fn_post_fzf' inside 'live_grep_mt'
      config.resume_set("query", selected[1], opts)
    end
    table.remove(selected, 1)
  end
  if opts.__fn_post_fzf then opts.__fn_post_fzf(opts, selected) end
  if opts._fn_post_fzf then opts._fn_post_fzf(opts, selected) end
  if opts.fn_post_fzf then opts.fn_post_fzf(opts, selected) end
  fzf_win:check_exit_status(exit_code, fzf_bufnr)
  -- retrieve the future action and check:
  --   * if it's a single function we can close the window
  --   * if it's a table of functions we do not close the window
  local keybind = actions.normalize_selected(selected, opts)
  local action = keybind and opts.actions and opts.actions[keybind]
  -- only close the window if autoclose wasn't specified or is 'true'
  -- or if the action wasn't a table or defined with `reload|noclose`
  local do_not_close = type(action) == "table"
      and (action[1] ~= nil or action.reload or action.noclose or action.reuse)
  if (not fzf_win:autoclose() == false) and not do_not_close then
    fzf_win:close(fzf_bufnr)
    -- only clear context if we didn't open a new interface, for example, opening
    -- files, switching to normal with <c-\><c-n> and opening buffers (#1810)
    if utils.fzf_winobj() == nil then
      M.__CTX = nil
    end
  end
  return selected
end

-- Best approximation of neovim border types to fzf border types
local function translate_border(winopts, metadata)
  local neovim2fzf = {
    none       = "noborder",
    single     = "border-sharp",
    double     = "border-double",
    rounded    = "border-rounded",
    solid      = "noborder",
    empty      = "border-block",
    shadow     = "border-thinblock",
    bold       = "border-bold",
    block      = "border-block",
    solidblock = "border-block",
    thicc      = "border-bold",
    thiccc     = "border-block",
    thicccc    = "border-block",
  }
  local border = winopts.border
  if not border then border = "none" end
  if border == true then border = "border" end
  if type(border) == "function" then
    border = border(winopts, metadata)
  end
  border = type(border) == "string" and (neovim2fzf[border] or border) or nil
  return border
end

---@param o table
---@return string
M.preview_window = function(o, fzf_win)
  local layout
  local prefix = string.format("%s:%s%s",
    o.winopts.preview.hidden and "hidden" or "nohidden",
    o.winopts.preview.wrap and "wrap" or "nowrap",
    (function()
      local border = (function()
        local preview_str = fzf_win:fzf_preview_layout_str()
        local preview_pos = preview_str:match("[^:]+") or "right"
        return translate_border(o.winopts.preview,
          { type = "fzf", name = "prev", layout = preview_pos })
      end)()
      return border and string.format(":%s", border) or ""
    end)()
  )
  if utils.has(o, "fzf", { 0, 31 })
      and o.winopts.preview.layout == "flex"
      and tonumber(o.winopts.preview.flip_columns) > 0
  then
    -- Fzf's alternate layout calculates the available preview width in a horizontal split
    -- (left/right), for the "<%d" condition to trigger the width should be test against a
    -- calculated preview width after a horizontal split (and not vs total fzf window width)
    -- to do that we must substract the calculated fzf "main" window width from `flip_columns`.
    -- NOTE: sending `true` as first arg gets the no fullscreen width, otherwise we'll get
    -- incosstent behavior when starting fullscreen
    local columns = fzf_win:columns(true)
    local fzf_prev_percent = tonumber(o.winopts.preview.horizontal:match(":(%d+)%%")) or 50
    local fzf_main_width = math.ceil(columns * (100 - fzf_prev_percent) / 100)
    local horizontal_min_width = o.winopts.preview.flip_columns - fzf_main_width + 1
    if horizontal_min_width > 0 then
      layout = string.format("%s:%s,<%d(%s:%s)",
        prefix, o.winopts.preview.horizontal, horizontal_min_width,
        prefix, o.winopts.preview.vertical)
    end
  end
  if not layout then
    layout = string.format("%s:%s", prefix, fzf_win:fzf_preview_layout_str())
  end
  return layout
end

-- Create fzf --color arguments from a table of vim highlight groups.
M.create_fzf_colors = function(opts)
  if type(opts.fzf_colors) ~= "table" then return end
  local colors = opts.fzf_colors

  if opts.fn_reload then
    colors.query = { "fg", opts.hls.live_prompt }
  end

  -- Remove non supported colors from skim and older fzf versions
  if not utils.has(opts, "fzf", { 0, 35 }) or utils.has(opts, "sk") then
    colors.separator = nil
  end
  if not utils.has(opts, "fzf", { 0, 41 }) or utils.has(opts, "sk") then
    colors.scrollbar = nil
  end

  local tbl = {}

  -- In case the user already set fzf_opts["--color"] (#1052)
  if opts.fzf_colors and type(opts.fzf_colors["--color"]) == "string" then
    table.insert(tbl, opts.fzf_opts["--color"])
  end

  for flag, list in pairs(colors) do
    if type(list) == "table" then
      local spec = {}
      local what = list[1]
      -- [2] can be one or more highlights, first existing hl wins
      local hls = type(list[2]) == "table" and list[2] or { list[2] }
      for _, hl in ipairs(hls) do
        local hexcol = utils.hexcol_from_hl(hl, what)
        if hexcol and #hexcol > 0 then
          table.insert(spec, hexcol)
          break
        end
      end
      -- arguments in the 3rd slot onward are passed raw, this can
      -- be used to pass styling arguments, for more info see #413
      -- https://github.com/junegunn/fzf/issues/1663
      for i = 3, #list do
        if type(list[i]) == "string" then
          table.insert(spec, list[i])
        end
      end
      if not utils.tbl_isempty(spec) then
        table.insert(spec, 1, flag)
        table.insert(tbl, table.concat(spec, ":"))
      end
    elseif type(list) == "string" then
      table.insert(tbl, ("%s:%s"):format(flag, list))
    end
  end

  -- NOTE: return `nil` so we don't set `fzf_opts["--color"]` to false
  -- although harmless (and now fixed) can cause "reload" issues (#1764)
  return not utils.tbl_isempty(tbl) and table.concat(tbl, ",") or nil
end

M.create_fzf_binds = function(opts)
  local binds = opts.keymap.fzf
  if not binds or utils.tbl_isempty(binds) then return {} end
  local combine, separate = {}, {}
  local dedup = {}
  for k, v in pairs(binds) do
    -- value can be defined as a table with addl properties (help string)
    if type(v) == "table" then
      v = v[1]
    elseif type(v) == "function" then
      if utils.has(opts, "fzf") then
        v = "execute-silent:" .. shell.raw_action(v, nil, opts.debug)
      else
        v = nil
      end
    end
    if v then
      dedup[k] = v
    end
  end
  for key, action in pairs(dedup) do
    -- Since we no longer use `--expect` any bind that contains `accept`
    -- should be assumed to "accept" the default action, using `--expect`
    -- that meant printing an empty string for the default enter key
    if utils.has(opts, "fzf", { 0, 53 })
        and action:match("accept%s-$")
        and not action:match("print(.-)%+accept")
    then
      action = action:gsub("accept%s-$", "print(enter)+accept")
    end
    local bind = string.format("%s:%s", key, action)
    -- Separate "transform|execute|execute-silent" binds to their own `--bind` argument, this
    -- way we can use `transform:...` and not be forced to use brackets, i.e. `transform(...)`
    -- this enables us to use brackets in the inner actions, e.g. "zero:transform:rebind(...)"
    if action:match("transform")
        or action:match("execute")
        or action:match("reload")
        or key == "zero"
        or key == "load"
        or key == "start"
        or key == "resize"
    then
      table.insert(separate, bind)
    else
      table.insert(combine, bind)
    end
  end
  if not utils.tbl_isempty(combine) then
    table.insert(separate, 1, table.concat(combine, ","))
  end
  return separate
end

---@param opts table
---@return string[]
M.build_fzf_cli = function(opts, fzf_win)
  -- below options can be specified directly in opts and will be
  -- prioritized: opts.<name> is prioritized over fzf_opts["--name"]
  for _, flag in ipairs({ "query", "prompt", "header", "preview" }) do
    if opts[flag] ~= nil then
      opts.fzf_opts["--" .. flag] = opts[flag]
    end
  end
  -- convert preview action functions to strings using our shell wrapper
  do
    local preview_cmd
    local preview_spec = opts.fzf_opts["--preview"]
    if type(preview_spec) == "function" then
      preview_cmd = shell.raw_action(preview_spec, "{}", opts.debug)
    elseif type(preview_spec) == "table" then
      preview_spec = vim.tbl_extend("keep", preview_spec, {
        fn = preview_spec.fn or preview_spec[1],
        -- by default we use current item only "{}"
        -- using "{+}" will send multiple selected items
        field_index = "{}",
      })
      if preview_spec.type == "cmd" then
        preview_cmd = shell.raw_preview_action_cmd(
          preview_spec.fn, preview_spec.field_index, opts.debug)
      else
        preview_cmd = shell.raw_action(preview_spec.fn, preview_spec.field_index, opts.debug)
      end
    end
    if preview_cmd then
      opts.fzf_opts["--preview"] = preview_cmd
    end
  end
  opts.fzf_opts["--bind"] = M.create_fzf_binds(opts)
  opts.fzf_opts["--color"] = M.create_fzf_colors(opts)
  do
    -- `actions.expect` parses the actions table and returns a list of
    -- keys that trigger completion (accept) to be added to `--expect`
    -- If the action contains the prefix key, e.g. `{ fn = ... , prefix = "select-all" }`
    -- additional binds will be set for the specific action key
    -- NOTE: requires fzf >= 0.53 (https://github.com/junegunn/fzf/issues/3810)
    local expect_keys, expect_binds = actions.expect(opts.actions, opts)
    if expect_keys and #expect_keys > 0 then
      opts.fzf_opts["--expect"] = table.concat(expect_keys, ",")
    end
    if expect_binds and #expect_binds > 0 then
      table.insert(opts.fzf_opts["--bind"], table.concat(expect_binds, ","))
    end
  end
  if opts.fzf_opts["--preview-window"] == nil then
    opts.fzf_opts["--preview-window"] = M.preview_window(opts, fzf_win)
  end
  if opts.fzf_opts["--preview-window"] and opts.preview_offset and #opts.preview_offset > 0 then
    opts.fzf_opts["--preview-window"] =
        opts.fzf_opts["--preview-window"] .. ":" .. opts.preview_offset
  end
  -- build the cli args
  local cli_args = {}
  -- fzf-tmux args must be included first
  if opts._is_fzf_tmux == 1 then
    for k, v in pairs(opts.fzf_tmux_opts or {}) do
      table.insert(cli_args, k)
      if type(v) == "string" and #v > 0 then
        table.insert(cli_args, v)
      end
    end
  elseif opts._is_fzf_tmux == 2 and utils.has(opts, "fzf") then
    -- "--height" specified after "--tmux" will take priority and cause
    -- the job to spawn in the background without a visible interface
    -- NOTE: this doesn't happen with skim and will cause issues if
    -- "$SKIM_DEFAULT_OPTIONS" will contain `--height`
    opts.fzf_opts["--height"] = nil
  end
  for k, t in pairs(opts.fzf_opts) do
    for _, v in ipairs(type(t) == "table" and t or { t }) do
      (function()
        -- flag can be set to `false` to negate a default
        if not v then return end
        local opt_v
        if type(v) == "string" or type(v) == "number" then
          v = tostring(v) -- convert number type to string
          if k == "--query" then
            opt_v = libuv.shellescape(v)
          else
            if utils.__IS_WINDOWS and type(v) == "string" and v:match([[^'.*'$]]) then
              -- replace single quote shellescape
              -- TODO: replace all so we never get here
              v = [["]] .. v:sub(2, #v - 1) .. [["]]
            end
            if libuv.is_escaped(v) then
              utils.warn(string.format("`fzf_opts` are automatically shellescaped."
                .. " Please remove surrounding quotes from %s=%s", k, v))
            end
            opt_v = libuv.is_escaped(v) and v or libuv.shellescape(v)
          end
        end
        if utils.has(opts, "sk") then
          -- NOT FIXED in 0.11.11: https://github.com/skim-rs/skim/pull/586
          -- TODO: reopen skim issue
          -- skim has a bug with flag values that start with `-`, for example
          -- specifying `--nth "-1.."` will fail but `--nth="-1.."` works (#1085)
          table.insert(cli_args, not opt_v and k or string.format("%s=%s", k, opt_v))
        else
          table.insert(cli_args, k)
          if opt_v then table.insert(cli_args, opt_v) end
        end
      end)()
    end
  end
  for _, o in ipairs({ "fzf_args", "fzf_raw_args", "fzf_cli_args", "_fzf_cli_args" }) do
    if opts[o] then
      table.insert(cli_args, type(opts[o]) == "table" and opts[o] or tostring(opts[o]))
    end
  end
  return cli_args
end

---@param opts table
---@return string|function
M.mt_cmd_wrapper = function(opts)
  assert(opts and opts.cmd)
  ---@param o table<string, unknown>
  ---@return table
  local filter_opts = function(o)
    local names = {
      "debug",
      "profile",
      "process1",
      "silent",
      "argv_expr",
      "cmd",
      "cwd",
      "stdout",
      "stderr",
      "stderr_to_stdout",
      "formatter",
      "multiline",
      "git_dir",
      "git_worktree",
      "git_icons",
      "file_icons",
      "color_icons",
      "path_shorten",
      "strip_cwd_prefix",
      "exec_empty_query",
      "file_ignore_patterns",
      "rg_glob",
      "_base64",
      utils.__IS_WINDOWS and "__FZF_VERSION" or nil,
    }
    -- caller requested rg with glob support
    if o.rg_glob then
      table.insert(names, "glob_flag")
      table.insert(names, "glob_separator")
    end
    local t = {}
    for _, name in ipairs(names) do
      if o[name] ~= nil then
        t[name] = o[name]
      end
    end
    t.g = {}
    for k, v in pairs({
      ["_fzf_lua_server"] = vim.g.fzf_lua_server,
      -- [NOTE] No longer needed, we use RPC for icons
      -- ["_devicons_path"] = devicons.plugin_path(),
      -- ["_devicons_setup"] = config._devicons_setup,
      ["_EOL"] = opts.multiline and "\0" or "\n",
      ["_debug"] = opts.debug,
    }) do
      t.g[k] = v
    end
    return t
  end

  ---@param obj table|string
  ---@return string
  local serialize = function(obj)
    local str = type(obj) == "table"
        and serpent.line(obj, { comment = false, sortkeys = false })
        or tostring(obj)
    if opts._base64 ~= false then
      -- by default, base64 encode all arguments
      return "[==[" .. base64.encode(str) .. "]==]"
    else
      -- if not encoding, don't string wrap the table
      return type(obj) == "table" and str
          or "[==[" .. str .. "]==]"
    end
  end

  if not opts.requires_processing
      and not opts.git_icons
      and not opts.file_icons
      and not opts.file_ignore_patterns
      and not opts.path_shorten
      and not opts.formatter
      and not opts.multiline
  then
    -- command does not require any processing, we also reset `argv_expr`
    -- to keep `setup_fzf_interactive_flags::no_query_condi` in the command
    opts.argv_expr = nil
    return opts.cmd
  elseif opts.multiprocess then
    assert(not opts.__mt_transform or type(opts.__mt_transform) == "string")
    assert(not opts.__mt_preprocess or type(opts.__mt_preprocess) == "string")
    assert(not opts.__mt_postprocess or type(opts.__mt_postprocess) == "string")
    if opts.argv_expr then
      -- Since the `rg` command will be wrapped inside the shell escaped
      -- '--headless .. --cmd', we won't be able to search single quotes
      -- as it will break the escape sequence. So we use a nifty trick:
      --   * replace the placeholder with {argv1}
      --   * re-add the placeholder at the end of the command
      --   * preprocess then replace it with vim.fn.argv(1)
      -- NOTE: since we cannot guarantee the positional index
      -- of arguments (#291), we use the last argument instead
      opts.cmd = opts.cmd:gsub(M.fzf_query_placeholder, "{argvz}")
    end
    local cmd = libuv.wrap_spawn_stdio(
      serialize(filter_opts(opts)),
      serialize(opts.__mt_transform or [[return require("fzf-lua.make_entry").file]]),
      serialize(opts.__mt_preprocess or [[return require("fzf-lua.make_entry").preprocess]]),
      serialize(opts.__mt_postprocess or "nil")
    )
    if opts.argv_expr then
      -- prefix the query with `--` so we can support `--fixed-strings` (#781)
      cmd = string.format("%s -- %s", cmd, M.fzf_query_placeholder)
    end
    return cmd
  else
    assert(not opts.__mt_transform or type(opts.__mt_transform) == "function")
    assert(not opts.__mt_preprocess or type(opts.__mt_preprocess) == "function")
    assert(not opts.__mt_postprocess or type(opts.__mt_postprocess) == "function")
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
      end,
      opts.__mt_postprocess and function(o) return opts.__mt_postprocess(o) end or nil)
  end
end

-- given the default delimiter ':' this is the
-- fzf expression field index for the line number
-- when entry format is 'file:line:col: text'
-- this is later used with native fzf previewers
-- for setting the preview offset (and on some
-- cases the highlighted line)
M.set_fzf_field_index = function(opts, default_idx, default_expr)
  opts.line_field_index = opts.line_field_index or default_idx or "{2}"
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

M.set_title_flags = function(opts, titles)
  -- NOTE: we only support cmd titles ATM
  if not vim.tbl_contains(titles or {}, "cmd") then return opts end
  if opts.winopts.title_flags == false then return opts end
  local cmd = type(opts.cmd) == "string" and opts.cmd
      or type(opts.fn_reload) == "string" and opts.fn_reload
      or nil
  if not cmd then return opts end
  local flags = {}
  local patterns = {
    { { utils.lua_regex_escape(opts.toggle_hidden_flag) or "%-%-hidden" },     "h" },
    { { utils.lua_regex_escape(opts.toggle_ignore_flag) or "%-%-no%-ignore" }, "i" },
    { { utils.lua_regex_escape(opts.toggle_follow_flag) or "%-L" },            "f" },
  }
  for _, def in ipairs(patterns) do
    for _, p in ipairs(def[1]) do
      if opts.cmd:match(p) then
        table.insert(flags, string.format(" %s ", def[2]))
      end
    end
  end
  if not utils.tbl_isempty(flags) then
    local title = utils.map_get(opts, "winopts.title")
    if type(title) == "string" then
      title = { { title, opts.hls.title } }
    end
    if type(title) == "table" then
      for _, f in ipairs(flags) do
        -- table.insert(title, { " " })
        table.insert(title, { f, opts.hls.title_flags })
      end
      utils.map_set(opts, "winopts.title", title)
      -- HACK: update the win title for "unhide" / "resume"
      local winobj = win.__SELF()
      if winobj then
        utils.map_set(winobj, "winopts.title", title)
        utils.map_set(winobj._o, "winopts.title", title)
      end
    end
  end
  return opts
end

M.set_header = function(opts, hdr_tbl)
  local function normalize_cwd(cwd)
    if path.is_absolute(cwd) and not path.equals(cwd, uv.cwd()) then
      -- since we're always converting cwd to full path
      -- try to convert it back to relative for display
      cwd = path.relative_to(cwd, uv.cwd())
    end
    -- make our home dir path look pretty
    return path.HOME_to_tilde(cwd)
  end

  if not opts then opts = {} end
  if opts.cwd_prompt then
    opts.prompt = normalize_cwd(opts.cwd or uv.cwd())
    if tonumber(opts.cwd_prompt_shorten_len) and
        #opts.prompt >= tonumber(opts.cwd_prompt_shorten_len) then
      opts.prompt = path.shorten(opts.prompt, tonumber(opts.cwd_prompt_shorten_val) or 1)
    end
    opts.prompt = path.add_trailing(opts.prompt)
  end
  if opts.no_header or opts.headers == false then
    return opts
  end
  local definitions = {
    -- key: opt name
    -- val.hdr_txt_opt: opt header string name
    -- val.hdr_txt_str: opt header string text
    cwd = {
      hdr_txt_opt = "cwd_header_txt",
      hdr_txt_str = "cwd: ",
      hdr_txt_col = opts.hls.header_text,
      val = function()
        -- do not display header when we're inside our
        -- cwd unless the caller specifically requested
        if opts.cwd_header == false or
            opts.cwd_prompt and opts.cwd_header == nil or
            opts.cwd_header == nil and
            (not opts.cwd or path.equals(opts.cwd, uv.cwd())) then
          return
        end
        return normalize_cwd(opts.cwd or uv.cwd())
      end
    },
    search = {
      hdr_txt_opt = "grep_header_txt",
      hdr_txt_str = "Grep string: ",
      hdr_txt_col = opts.hls.header_text,
      val = function()
        return opts.search and #opts.search > 0 and opts.search
      end,
    },
    lsp_query = {
      hdr_txt_opt = "lsp_query_header_txt",
      hdr_txt_str = "Query: ",
      hdr_txt_col = opts.hls.header_text,
      val = function()
        return opts.lsp_query and #opts.lsp_query > 0 and opts.lsp_query
      end,
    },
    regex_filter = {
      hdr_txt_opt = "regex_header_txt",
      hdr_txt_str = "Regex filter: ",
      hdr_txt_col = opts.hls.header_text,
      val = function()
        if type(opts.regex_filter) == "string" then
          return opts.regex_filter
        elseif type(opts.regex_filter) == "table" and type(opts.regex_filter[1]) == "string" then
          return string.format("%s%s",
            opts.regex_filter.exclude and "not " or "",
            opts.regex_filter[1])
        elseif type(opts.regex_filter) == "function" then
          return "<function>"
        end
      end,
    },
    actions = {
      hdr_txt_opt = "interactive_header_txt",
      hdr_txt_str = "",
      val = function(o)
        if opts.no_header_i then return end
        local defs = M.ACTION_DEFINITIONS
        local ret = {}
        local sorted = vim.tbl_keys(opts.actions or {})
        table.sort(sorted)
        for _, k in ipairs(sorted) do
          (function()
            local v = opts.actions[k]
            local action = type(v) == "function" and v or type(v) == "table" and (v.fn or v[1])
            if type(v) == "table" and v.header == false then return end
            local def, to = nil, type(v) == "table" and v.header
            if not to and type(action) == "function" and defs[action] then
              def = defs[action]
              to = def[1]
            end
            if to then
              if type(to) == "function" then
                to = to(o)
              end
              table.insert(ret, def and def.pos or #ret + 1,
                string.format("<%s> to %s",
                  utils.ansi_from_hl(opts.hls.header_bind, k),
                  utils.ansi_from_hl(opts.hls.header_text, tostring(to))))
            end
          end)()
        end
        -- table.concat fails if the table indexes aren't consecutive
        return not utils.tbl_isempty(ret) and (function()
          local t = {}
          for _, i in pairs(ret) do
            table.insert(t, i)
          end
          t[1] = (opts.header_prefix or ":: ") .. t[1]
          return table.concat(t, opts.header_separator or "|")
        end)() or nil
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
    local txt = def.val(opts)
    if def and txt then
      hdr_str = not hdr_str and "" or (hdr_str .. ", ")
      hdr_str = ("%s%s%s"):format(hdr_str, def.hdr_txt_str,
        not def.hdr_txt_col and txt or
        utils.ansi_from_hl(def.hdr_txt_col, txt))
    end
  end
  if hdr_str and #hdr_str > 0 then
    opts.fzf_opts["--header"] = hdr_str
  end
  return opts
end


-- Use both {q} and {+} as field indexes so we can update last query when
-- executing the action, without this we lose the last query on "hide" as
-- the process never terminates and `--print-query` isn't being printed
-- When no entry selected (with {q} {+}), {+} will be forced expand to ''
-- Use {n} to know if we really select an empty string, or there's just no selected
local patch_shell_action = function(v, opts)
  local field_index = v.field_index == false and "" or v.field_index or "{+}"
  local overide_f_idx
  if not field_index:match("^{q} {n}") then
    field_index = "{q} {n} " .. field_index
    overide_f_idx = true
  end
  -- replace the action with shell cmd proxy to the original action
  return shell.raw_action(function(items, _, _)
    assert(field_index:match("^{q} {n}"))
    local query, idx = unpack(items, 1, 2)
    config.resume_set("query", query, opts)
    if overide_f_idx then
      table.remove(items, 1)
      table.remove(items, 1)
    end
    -- fix side effect of "{q} {+}": {+} is forced expanded to ""
    -- only when: user didn't set v.field_index (otherwise it can be complex/unpredictable)
    -- {n} used to determine if "zero-selected && zero-match", then patch: "" -> nil
    if not v.field_index then
      -- When no item is matching (empty list or non-matching query)
      -- both {n} and {+} are expanded to "".
      -- NOTE1: older versions of fzf don't expand {n} to "" (without match)
      -- in such case the (empty) items table will be in `items[2]` (#1833)
      -- NOTE2: on Windows, no match {n} is expanded to '' (#1836)
      local zero_matched = not tonumber(idx)
      local zero_selected = #items == 0 or (#items == 1 and #items[1] == 0)
      items = (zero_matched and zero_selected) and {} or items
    end
    v.fn(items, opts)
  end, field_index, opts.debug)
end

-- converts actions defined with "reload=true" to use fzf's `reload` bind
-- provides a better UI experience without a visible interface refresh
---@param reload_cmd content
---@param opts table
---@return table
M.convert_reload_actions = function(reload_cmd, opts)
  local fallback ---@type boolean?
  local has_reload ---@type boolean?
  -- Does not work with fzf version < 0.36, fzf fails with
  -- "error 2: bind action not specified:" (#735)
  -- Not yet supported with skim
  if not utils.has(opts, "fzf", { 0, 36 })
      or utils.has(opts, "sk")
      or type(reload_cmd) ~= "string" then
    fallback = true
  end
  -- Two types of action as table:
  --   (1) map containing action properties (reload, noclose, etc)
  --   (2) array of actions to be executed serially
  -- CANNOT HAVE MIXED DEFINITIONS
  for k, v in pairs(opts.actions) do
    if type(v) == "function" or type(v) == "table" then
      assert(type(v) == "function" or (v.fn and v[1] == nil) or (v[1] and v.fn == nil))
      if type(v) == "table" and v.reload then
        has_reload = true
        assert(type(v.fn) == "function")
        -- fallback: we cannot use the `reload` event (old fzf or skim)
        -- convert to "old-style" interface reload using `resume`
        if fallback then
          opts.actions[k] = { v.fn, actions.resume }
        end
      elseif not fallback and type(v) == "table"
          and type(v[1]) == "function" and v[2] == actions.resume then
        -- backward compat: we can use the `reload` event but action
        -- definition is still using the old style using `actions.resume`
        -- convert to the new style using { fn = <function>, reload = true }
        opts.actions[k] = { fn = v[1], reload = true }
      end
    end
  end
  if opts.silent ~= true and has_reload and reload_cmd and type(reload_cmd) ~= "string" then
    utils.warn(
      "actions with `reload` are only supported with string commands, using resume fallback")
  end
  if fallback then
    -- for fallback, conversion to "old-style" actions is sufficient
    return opts
  end
  local reload_binds = {}
  for k, v in pairs(opts.actions) do
    if type(v) == "table" and v.reload then
      assert(type(v.fn) == "function")
      table.insert(reload_binds, k)
    end
  end
  local bind_concat = function(tbl, act)
    if #tbl == 0 then return nil end
    return table.concat(vim.tbl_map(function(x)
      return string.format("%s(%s)", act, x)
    end, tbl), "+")
  end
  local unbind = bind_concat(reload_binds, "unbind")
  local rebind = bind_concat(reload_binds, "rebind")
  for k, v in pairs(opts.actions) do
    if type(v) == "table" and v.reload then
      -- Modified actions should not be considered in `actions.expect`
      opts.actions[k]._ignore = true
      local shell_action = patch_shell_action(v, opts)
      if type(v.prefix) == "string" and not v.prefix:match("%+$") then
        v.prefix = v.prefix .. "+"
      end
      if type(v.postfix) == "string" and not v.postfix:match("^%+") then
        v.postfix = "+" .. v.postfix
      end
      opts.keymap.fzf[k] = {
        string.format("%s%sexecute-silent(%s)+reload(%s)%s",
          type(v.prefix) == "string" and v.prefix or "",
          unbind and (unbind .. "+") or "",
          shell_action,
          reload_cmd,
          type(v.postfix) == "string" and v.postfix or ""),
        desc = v.desc or config.get_action_helpstr(v.fn)
      }
    end
  end
  opts.keymap.fzf.load = (function()
    -- NOTE: this fixes existence of both load as function and rebind, e.g. git_status with:
    -- setup({ keymap = { fzf = { true, load = function() _G._fzf_load_called = true end } } }
    if type(opts.keymap.fzf.load) == "function" then
      opts.keymap.fzf.load = "execute-silent:" ..
          shell.raw_action(opts.keymap.fzf.load, nil, opts.debug)
    end
    if rebind and type(opts.keymap.fzf.load) == "string" then
      return string.format("%s+%s", rebind, opts.keymap.fzf.load)
    else
      return rebind or opts.keymap.fzf.load
    end
  end)()
  return opts
end

-- converts actions defined inside 'silent_actions' to use fzf's 'execute-silent'
-- bind, these actions will not close the UI, e.g. commits|bcommits yank commit sha
---@param opts table
---@return table
M.convert_exec_silent_actions = function(opts)
  -- `execute-silent` actions are bugged with skim (can't use quotes)
  if utils.has(opts, "sk") then
    return opts
  end
  for k, v in pairs(opts.actions) do
    if type(v) == "table" and v.exec_silent then
      assert(type(v.fn) == "function")
      -- Modified actions should not be considered in `actions.expect`
      opts.actions[k]._ignore = true
      local shell_action = patch_shell_action(v, opts)
      if type(v.prefix) == "string" and not v.prefix:match("%+$") then
        v.prefix = v.prefix .. "+"
      end
      if type(v.postfix) == "string" and not v.postfix:match("^%+") then
        v.postfix = "+" .. v.postfix
      end
      -- `execute-silent(...)` with fzf version < 0.36, errors with:
      -- 'error 2: bind action not specified' (due to inner brackets)
      -- changing to `execute-silent:...` removes the need to care for
      -- brackets within the command with the limitation of not using
      -- potfix (must be the last part of the arg), from `man fzf`:
      --
      --   action-name:...
      --      The last one is the special form that frees you from parse
      --      errors as it does not expect the closing character. The catch is
      --      that it should be the last one in the comma-separated list of
      --      key-action pairs.
      --
      local has_fzf036 = utils.has(opts, "fzf", { 0, 36 })
      opts.keymap.fzf[k] = {
        string.format("%sexecute-silent%s%s",
          type(v.prefix) == "string" and v.prefix or "",
          -- prefer "execute-silent:..." unless we have postfix
          has_fzf036 and type(v.postfix) == "string"
          and string.format("(%s)", shell_action)
          or string.format(":%s", shell_action),
          -- can't use postfix since we use "execute-silent:..."
          has_fzf036 and type(v.postfix) == "string" and v.postfix or ""),
        desc = v.desc or config.get_action_helpstr(v.fn)
      }
    end
  end
  return opts
end

---@param command string
---@param fzf_field_expression string
---@param opts table
---@return table
M.setup_fzf_interactive_flags = function(command, fzf_field_expression, opts)
  -- query cannot be 'nil'
  opts.query = opts.query or ""

  -- by redirecting the error stream to stdout
  -- we make sure a clear error message is displayed
  -- when the user enters bad regex expressions
  local initial_command = command
  if (opts.stderr_to_stdout ~= false) and not initial_command:match("2>") then
    initial_command = command .. " 2>&1"
  end

  local reload_command = initial_command
  if type(opts.query_delay) == "number" then
    reload_command = string.format("sleep %.2f; %s", opts.query_delay / 1000, reload_command)
  end
  -- See the note in `make_entry.preprocess`, the NEQ condition on Windows
  -- along with fzf's lacking escape sequence causes the empty query condition
  -- to fail on spaces, comma and semicolon (and perhaps other use cases),
  -- moving the test to our cmd wrapper solves it for anything but "native"
  local no_query_condi = (opts.exec_empty_query or opts.argv_expr) and ""
      or string.format(
        utils._if_win(
        -- due to the reload command already being shellescaped and fzf's {q}
        -- also escaping the query with ^"<query>"^ any spaces in the query
        -- will fail the command, by adding caret escaping before fzf's
        -- we fool CMD.exe to not terminate the quote and thus an empty query
        -- will generate the expression ^^"^" which translates to ^""
        -- our specialized libuv.shellescape will also double the escape
        -- sequence if a "!" is found in our string as explained in:
        -- https://ss64.com/nt/syntax-esc.html
        -- TODO: open an upstream bug rgd ! as without the double escape
        -- if an ! is found in the command (i.e. -g "rg ... -g !.git")
        -- sending a caret will require doubling (i.e. sending ^^ for ^)
          utils.has(opts, "fzf", { 0, 51 }) and [[IF %s NEQ ^"^" ]] or [[IF ^%s NEQ ^^"^" ]],
          "[ -z %s ] || "),
        -- {q} for fzf is automatically shell escaped
        fzf_field_expression
      )

  if opts._is_skim then
    -- skim interactive mode does not need a piped command
    opts.__fzf_init_cmd = nil
    opts.prompt = opts.__prompt or opts.prompt or opts.fzf_opts["--prompt"]
    if opts.prompt then
      opts.fzf_opts["--prompt"] = opts.prompt:match("[^%*]+")
      opts.fzf_opts["--cmd-prompt"] = opts.prompt
      -- save original prompt and reset the current one since
      -- we're using the '--cmd-prompt' as the "main" prompt
      -- required for resume to have the asterisk prompt prefix
      opts.__prompt = opts.prompt
      opts.prompt = nil
    end
    -- since we surrounded the skim placeholder with quotes
    -- we need to escape them in the initial query
    opts.fzf_opts["--cmd-query"] = utils.sk_escape(opts.query)
    -- '--query' was set by 'resume()', skim has the option to switch back and
    -- forth between interactive command and fuzzy matching (using 'ctrl-q')
    -- setting both '--query' and '--cmd-query' will use <query> to fuzzy match
    -- on top of our result set, double filtering our results (undesirable)
    opts.fzf_opts["--query"] = nil
    opts.query = nil
    -- setup as interactive
    opts._fzf_cli_args = string.format("--interactive --cmd %s",
      libuv.shellescape(no_query_condi .. reload_command))
  else
    -- **send an empty table to avoid running $FZF_DEFAULT_COMMAND
    -- The above seems to create a hang in some systems
    -- use `true` as $FZF_DEFAULT_COMMAND instead (#510)
    opts.__fzf_init_cmd = utils.shell_nop()
    if opts.exec_empty_query or (opts.query and #opts.query > 0) then
      local q = not utils.__IS_WINDOWS and opts.query
          or libuv.escape_fzf(opts.query, utils.has(opts, "fzf", { 0, 52 }) and 0.52 or 0)
      -- gsub doesn't like single % on rhs
      local escaped_q = libuv.shellescape(q):gsub("%%", "%%%%")
      opts.__fzf_init_cmd = initial_command:gsub(fzf_field_expression, escaped_q)
    end
    opts.fzf_opts["--disabled"] = true
    opts.fzf_opts["--query"] = opts.query
    -- OR with true to avoid fzf's "Command failed:" message
    if opts.silent_fail ~= false then
      reload_command = reload_command .. " || " .. utils.shell_nop()
    end
    opts._fzf_cli_args = string.format("--bind=%s", libuv.shellescape(
      string.format("change:reload:%s%s", no_query_condi, reload_command)))
  end

  return opts
end

-- query placeholder for "live" queries
M.fzf_query_placeholder = "<query>"

---@param opts {field_index: boolean, _is_skim: boolean}
---@return string
M.fzf_field_expression = function(opts)
  -- fzf already adds single quotes around the placeholder when expanding.
  -- for skim we surround it with double quotes or single quote searches fail
  return opts and opts.field_index or opts._is_skim and [["{}"]] or "{q}"
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
