local uv = vim.uv or vim.loop
local fzf = require "fzf-lua.fzf"
local path = require "fzf-lua.path"
local utils = require "fzf-lua.utils"
local config = require "fzf-lua.config"
local actions = require "fzf-lua.actions"
local win = require "fzf-lua.win"
local libuv = require "fzf-lua.libuv"
local shell = require "fzf-lua.shell"

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
      if o.is_live then
        return "Fuzzy Search"
      else
        return "Regex Search"
      end
    end,
  },
  [actions.sym_lsym]          = {
    function(o)
      if o.is_live then
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
  [actions.list_del]          = { "delete" },
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
    ---@type fzf-lua.fncContent
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

---@alias fzf-lua.fzfCb fun(entry?: string|number, cb?: function)
---@alias fzf-lua.fncContent fun(wnl: fzf-lua.fzfCb, w: fzf-lua.fzfCb)
---@alias fzf-lua.content fzf-lua.fncContent|(string|number)[]|string

-- Main API, see:
-- https://github.com/ibhagwan/fzf-lua/wiki/Advanced
---@param contents fzf-lua.content
---@param opts? fzf-lua.config.Base|{}
---@return thread?, string?, table?
M.fzf_exec = function(contents, opts)
  assert(contents, "must supply contents")
  opts = config.normalize_opts(opts or {}, {})
  if not opts then return end
  if type(contents) == "table" and type(contents[1]) == "table" then
    contents = contents_from_arr(contents)
  end
  local cmd = shell.stringify_mt(contents, opts)
      or shell.stringify(contents, opts, nil)
  return M.fzf_wrap(cmd, opts, true)
end

local nop = function(opts)
  return not opts.fn_transform
      and not opts.fn_preprocess
      and not opts.fn_postprocess
end

---@param opts table
---@return boolean
M.can_transform = function(opts)
  return utils.has(opts, "fzf", { 0, 45 })
      and opts.is_live -- currently only used for "live" picker
      and opts.rg_glob
      and not opts.multiprocess
      and nop(opts)
end

-- Append query placeholder if not found in command
local add_query_placeholder = function(cmd)
  if type(cmd) ~= "string" or cmd:match(M.fzf_query_placeholder) then return cmd end
  return ("%s %s"):format(((cmd):gsub("%s*$", "")), M.fzf_query_placeholder)
end

---@param contents string|fzf-lua.shell.data2
---@return fzf-lua.shell.data2
local cmd2fnc = function(contents)
  if type(contents) == "function" then return contents end
  -- Append query placeholder if not found in command
  local cmd = add_query_placeholder(contents)
  return function(args, _)
    local query = args[1] or ""
    query = (query:gsub("%%", "%%%%"))
    query = libuv.shellescape(query)
    return M.expand_query(cmd, query)
  end
end

-- AKA "live": fzf acts as a selector only (fuzzy matching is disabled)
-- each keypress reloads fzf's input usually based on the typed query
-- utilizes fzf's 'change:reload' event or skim's "interactive" mode
---@param contents string|fzf-lua.shell.data2
---@param opts? fzf-lua.config.Base|{}
---@return thread?, string?, table?
M.fzf_live = function(contents, opts)
  opts = opts or {}
  opts.is_live = true
  opts = config.normalize_opts(opts, {})
  if not opts then return end
  local fzf_field_index = M.fzf_field_index(opts)
  local cmd ---@type string
  if type(contents) == "function" and M.can_transform(opts) then
    cmd = shell.stringify_data(
      function(items) return contents(items, opts) end, opts, fzf_field_index)
  else
    contents = add_query_placeholder(contents)
    local mtcmd = shell.stringify_mt(contents, opts)
    cmd = mtcmd and M.expand_query(mtcmd, fzf_field_index)
        or type(contents) == "string" and nop(opts) and M.expand_query(contents, fzf_field_index)
        or shell.stringify(cmd2fnc(contents), opts, fzf_field_index)
  end
  M.setup_fzf_live_flags(cmd, opts)
  return M.fzf_wrap(cmd, opts, true)
end

M.fzf_resume = function(opts)
  -- First try to unhide the window
  if win.unhide() then return end
  if not config.__resume_data or not config.__resume_data.opts then
    utils.info("No resume data available.")
    return
  end
  opts = utils.tbl_deep_extend("force", config.__resume_data.opts, opts or {})
  assert(opts == config.__resume_data.opts)
  opts.cwd = opts.cwd and libuv.expand(opts.cwd) or nil
  M.fzf_wrap(config.__resume_data.contents, config.__resume_data.opts)
end

---@param cmd string?
---@param opts table
---@param convert_actions boolean?
---@return thread?, string, table
M.fzf_wrap = function(cmd, opts, convert_actions)
  opts = opts or {}
  M.set_header(opts)
  if convert_actions and type(opts.actions) == "table" then
    opts = M.convert_reload_actions(cmd, opts)
    opts = M.convert_exec_silent_actions(opts)
  end
  -- Do not strt fzf, return the stringified contents and opts onlu
  -- used by the "combine" picker to merge inputs
  if opts._start == false then return nil, cmd, opts end
  local _co, fn_selected
  coroutine.wrap(function()
    _co = coroutine.running()
    -- xpcall to get full traceback https://www.lua.org/pil/8.5.html
    local _, err = (jit and xpcall or require("fzf-lua.lib.copcall").xpcall)(function()
      if type(opts.cb_co) == "function" then opts.cb_co(_co) end
      local selected, exit_code = M.fzf(cmd, opts)
      -- If aborted (e.g. unhide process kill), do nothing
      if not tonumber(exit_code) then return end
      -- Default fzf exit callback acts upon the selected items
      fn_selected = opts.fn_selected or actions.act
      if not fn_selected then return end
      -- errors thrown here gets silenced possibly
      -- due to a coroutine, so catch explicitly
      fn_selected(selected, opts)
    end, debug.traceback)
    -- ignore existing swap file error, the choices dialog will still be
    -- displayed to user to make a selection once fzf-lua exits (#1011)
    if err then
      if fn_selected and err:match("Vim%(edit%):E325") then return end
      utils.error("fn_selected threw an error: " .. err)
    end
  end)()
  return _co, cmd, opts
end

---@param contents string?
---@param opts {}?
---@return string[]?
---@return integer? exit_code
M.fzf = function(contents, opts)
  -- Disable opening from the command-line window `:q`
  -- creates all kinds of issues, will fail on `nvim_win_close`
  if vim.fn.win_gettype() == "command" then
    utils.info("Unable to open from the command-line window. See `:help E11`.")
    return nil, nil
  end
  -- normalize with globals if not already normalized
  opts = config.normalize_opts(opts or {}, {})
  if not opts then return nil, nil end
  -- Store contents for unhide
  opts._contents = contents
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
  -- store last call opts for resume
  config.resume_set(nil, opts.__call_opts, opts)
  -- caller specified not to resume this call (used by "builtin" provider)
  if not opts.no_resume then
    config.__resume_data = config.__resume_data or {}
    config.__resume_data.opts = opts
    config.__resume_data.contents = contents
  end

  -- update context and save a copy in options (for actions)
  -- call before creating the window or fzf_winobj is not nil
  opts.__CTX = utils.CTX(opts._ctx)
  opts.__INFO = FzfLua.get_info()

  -- setup the fzf window and preview layout
  local fzf_win = win:new(opts)
  -- instantiate the previewer
  local previewer = require("fzf-lua.previewer").new(opts.previewer, opts)
  if previewer then
    -- Attach the previewer to the windows
    fzf_win:attach_previewer(previewer)
    -- Setup --preview/--preview-window/--bind=zero:... etc
    if type(previewer.setup_opts) == "function" then
      opts = previewer:setup_opts(opts)
    end
  elseif opts.preview and type(opts.preview) ~= "string" then
    opts.preview = require("fzf-lua.previewer").normalize_spec(opts.preview, opts)
  elseif not opts.preview and not opts.fzf_opts["--preview"] then
    -- no preview available, override in case $FZF_DEFAULT_OPTS
    -- contains a preview which will most likely fail
    opts.fzf_opts["--preview-window"] = "hidden:right:0"
  end

  -- Create the window before we calculate the preview window layout
  local fzf_bufnr = fzf_win:create()

  -- setup layout for native previewers / split win background dummy preview
  if opts.fzf_opts["--preview-window"] == nil then
    opts.fzf_opts["--preview-window"] = M.preview_window(opts, fzf_win)
  end

  if utils.has(opts, "fzf", { 0, 46 })
      and opts.winopts.preview.layout == "flex"
      and tonumber(opts.winopts.preview.flip_columns) > 0
      -- Only enable flex layout native rotate if native previewer size > 0
      and not (opts.fzf_opts["--preview-window"] or ""):match(":0")
  then
    win.on_SIGWINCH(opts, nil, function(args)
      -- Only set the layout if preview isn't hidden
      if not tonumber(args[1]) then return end
      -- NOTE: do not use local ref `fzf_win` as it my change on resume (#2255)
      local winobj = utils.fzf_winobj()
      if not winobj then return end
      return string.format("change-preview-window(%s)", winobj:normalize_preview_layout().str)
    end)
  end

  -- live command may contain field index {q}, cannot be used as FZF_DEFAULT_COMMAND
  local selected, exit_code = fzf.raw_fzf(opts.is_live and utils.shell_nop() or contents,
    M.build_fzf_cli(opts),
    {
      fzf_bin = opts.fzf_bin,
      cwd = opts.cwd,
      pipe_cmd = opts.pipe_cmd,
      silent_fail = opts.silent_fail,
      is_fzf_tmux = opts._is_fzf_tmux,
      debug = opts.debug,
      RIPGREP_CONFIG_PATH = opts.RIPGREP_CONFIG_PATH,
    })
  -- kill fzf piped process PID
  -- NOTE: might be an overkill since we're using $FZF_DEFAULT_COMMAND
  -- to spawn the piped process and fzf is responsible for termination
  -- when the fzf process exists
  -- NOTE: can be an empty table due to tbl_deep_clone (#2260)
  if opts.PidObject and opts.PidObject.get then
    libuv.process_kill(opts.PidObject:get())
    opts.PidObject:set(nil)
  end
  -- If a hidden process was killed by [re-]starting a new picker do nothing
  if fzf_win:was_hidden() then return nil, nil end
  -- This was added by 'resume': when '--print-query' is specified
  -- we are guaranteed to have the query in the first line, save&remove it
  if selected and #selected > 0 then
    if not (opts._is_skim and opts.is_live) then
      -- reminder: this doesn't get called with 'live_grep' when using skim
      -- due to a bug where '--print-query --interactive' combo is broken:
      -- skim always prints an empty line where the typed query should be.
      config.resume_set("query", selected[1], opts)
    end
    table.remove(selected, 1)
  end
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
      utils.clear_CTX()
    end
  end
  return selected, exit_code
end

-- Best approximation of neovim border types to fzf border types
---@param winopts fzf-lua.config.Winopts|{}
---@param metadata fzf-lua.win.borderMetadata
---@return string|table
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
---@param fzf_win fzf-lua.Win
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
          { type = "fzf", name = "prev", layout = preview_pos, opts = o })
      end)()
      return border and string.format(":%s", border) or ""
    end)()
  )
  if utils.has(o, "fzf", { 0, 31 })
      -- fzf v0.45 added transform, v0.46 added resize event
      -- which we use for changing the layout on resize
      and not utils.has(o, "fzf", { 0, 46 })
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
    local fzf_prev_percent = tonumber(o.winopts.preview.horizontal:match(":(%d+)%%"))
    local fzf_prev_width = not fzf_prev_percent and
        tonumber(o.winopts.preview.horizontal:match(":(%d+)")) or nil
    fzf_prev_percent = fzf_prev_percent or 50
    local fzf_main_width = fzf_prev_width and (columns - fzf_prev_width)
        or math.ceil(columns * (100 - fzf_prev_percent) / 100)
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
  if o.preview_offset and #o.preview_offset > 0 then
    layout = layout .. ":" .. o.preview_offset
  end
  return layout
end

-- Create fzf --color arguments from a table of vim highlight groups.
M.create_fzf_colors = function(opts)
  -- In case the user already set fzf_opts["--color"] (#1052)
  if opts.fzf_opts and type(opts.fzf_opts["--color"]) == "string" then
    table.insert(opts._fzf_cli_args, "--color=" .. opts.fzf_opts["--color"])
  end
  if type(opts.fzf_colors) ~= "table" then return end
  local colors = opts.fzf_colors

  if opts.is_live then
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
        v = "execute-silent:" .. shell.stringify_data(v, opts)
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
M.build_fzf_cli = function(opts)
  -- below options can be specified directly in opts and will be
  -- prioritized: opts.<name> is prioritized over fzf_opts["--name"]
  for _, flag in ipairs({ "query", "prompt", "header", "preview" }) do
    if opts[flag] ~= nil then
      opts.fzf_opts["--" .. flag] = opts[flag]
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
              utils.warn("`fzf_opts` are automatically shellescaped."
                .. " Please remove surrounding quotes from %s=%s", k, v)
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
    local args = opts[o]
    if args then
      if type(args) ~= "table" then
        args = { tostring(args) }
      end
      for _, arg in ipairs(args) do
        table.insert(cli_args, arg)
      end
    end
  end
  return cli_args
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
      or type(opts._cmd) == "string" and opts._cmd
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
      if cmd:match(p) then
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

M.set_header = function(opts)
  opts = opts or {}
  opts._headers = opts._headers == nil and { "actions" } or opts._headers
  if opts.header ~= nil
      or opts.headers == false
      or type(opts._headers) ~= "table"
      or vim.tbl_isempty(opts._headers) then
    return opts
  end

  ---@param cwd string
  ---@return string
  local function normalize_cwd(cwd)
    if path.is_absolute(cwd) and not path.equals(cwd, uv.cwd()) then
      -- since we're always converting cwd to full path
      -- try to convert it back to relative for display
      cwd = path.relative_to(cwd, uv.cwd())
    end
    -- make our home dir path look pretty
    return path.HOME_to_tilde(cwd)
  end

  if opts.cwd_prompt then
    opts.prompt = normalize_cwd(opts.cwd or uv.cwd())
    if tonumber(opts.cwd_prompt_shorten_len) and
        #opts.prompt >= tonumber(opts.cwd_prompt_shorten_len) then
      opts.prompt = path.shorten(opts.prompt, tonumber(opts.cwd_prompt_shorten_val) or 1)
    end
    opts.prompt = path.add_trailing(opts.prompt)
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
            local def, to = nil, type(v) == "table" and v.header or nil
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
  -- override header text with the user's settings
  for _, h in ipairs(opts._headers) do
    assert(definitions[h])
    local hdr_text = opts[definitions[h].hdr_txt_opt]
    if hdr_text then
      definitions[h].hdr_txt_str = hdr_text
    end
  end
  -- build the header string
  local hdr_str
  for _, h in ipairs(opts._headers) do
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

-- converts actions defined with "reload=true" to use fzf's `reload` bind
-- provides a better UI experience without a visible interface refresh
---@param reload_cmd string?
---@param opts table
---@return table
M.convert_reload_actions = function(reload_cmd, opts)
  local fallback ---@type boolean?
  -- Does not work with fzf version < 0.36, fzf fails with
  -- "error 2: bind action not specified:" (#735)
  -- Not yet supported with skim
  if not utils.has(opts, "fzf", { 0, 36 })
      or utils.has(opts, "sk")
      or not reload_cmd then
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
      if type(v.prefix) == "string" and not v.prefix:match("%+$") then
        v.prefix = v.prefix .. "+"
      end
      if type(v.postfix) == "string" and not v.postfix:match("^%+") then
        v.postfix = "+" .. v.postfix
      end
      local cmd = shell.stringify_data2(v.fn, opts, v.field_index or "{+}")
      opts.keymap.fzf[k] = {
        string.format("%s%sexecute-silent(%s)+%s(%s)%s",
          type(v.prefix) == "string" and v.prefix or "",
          unbind and (unbind .. "+") or "",
          cmd,
          M.can_transform(opts) and "transform" or "reload", -- contents is not "cmd" but "reload:cmd"
          reload_cmd,
          type(v.postfix) == "string" and v.postfix or ""),
        desc = v.desc or config.get_action_helpstr(v.fn)
      }
    end
  end

  if rebind then
    table.insert(opts._fzf_cli_args,
      "--bind=" .. libuv.shellescape(string.format("load:+%s", rebind)))
  end
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
      local cmd = shell.stringify_data2(v.fn, opts, v.field_index or "{+}")
      opts.keymap.fzf[k] = {
        string.format("%sexecute-silent%s%s",
          type(v.prefix) == "string" and v.prefix or "",
          -- prefer "execute-silent:..." unless we have postfix
          has_fzf036 and type(v.postfix) == "string"
          and string.format("(%s)", cmd)
          or string.format(":%s", cmd),
          -- can't use postfix since we use "execute-silent:..."
          has_fzf036 and type(v.postfix) == "string" and v.postfix or ""),
        desc = v.desc or config.get_action_helpstr(v.fn)
      }
    end
  end
  return opts
end

---@param command string
---@param opts table
M.setup_fzf_live_flags = function(command, opts)
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

  if opts._is_skim then
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
    table.insert(opts._fzf_cli_args, string.format("--interactive --cmd %s",
      libuv.shellescape(reload_command)))
  else
    opts.fzf_opts["--disabled"] = true
    opts.fzf_opts["--query"] = opts.query
    -- OR with true to avoid fzf's "Command failed:" message
    if opts.silent_fail ~= false then
      reload_command = reload_command .. " || " .. utils.shell_nop()
    end
    local query = opts.query and tostring(opts.query) or ""
    local action = M.can_transform(opts) and "transform" or "reload"
    table.insert(opts._fzf_cli_args, "--bind="
      .. libuv.shellescape(string.format("change:+%s:%s", action, reload_command)))
    if opts.exec_empty_query or #query > 0 or type(opts.contents) == "function" then
      table.insert(opts._fzf_cli_args, "--bind="
        .. libuv.shellescape(string.format("start:+%s:%s", action, reload_command)))
    end
  end
end

-- query placeholder for "live" queries
M.fzf_query_placeholder = "<query>"

---@param opts { field_index?: boolean, _is_skim?: boolean }
---@return string
M.fzf_field_index = function(opts)
  -- fzf already adds single quotes around the placeholder when expanding.
  -- for skim we surround it with double quotes or single quote searches fail
  return opts and opts.field_index or opts._is_skim and [["{}"]] or "{q}"
end

---@param cmd string
---@param fzf_field_index string
---@return string
M.expand_query = function(cmd, fzf_field_index)
  if cmd:match(M.fzf_query_placeholder) then
    return (cmd:gsub(M.fzf_query_placeholder, fzf_field_index))
  else
    return ("%s %s"):format(cmd, fzf_field_index)
  end
end

return M
