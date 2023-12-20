local path = require "fzf-lua.path"
local utils = require "fzf-lua.utils"
local actions = require "fzf-lua.actions"

local M = {}

if utils.__HAS_DEVICONS then
  M._has_devicons, M._devicons = pcall(require, "nvim-web-devicons")

  -- get the devicons module path
  M._devicons_path = M._has_devicons and M._devicons and M._devicons.setup
      and debug.getinfo(M._devicons.setup, "S").source:gsub("^@", "")
  if utils.__IS_WINDOWS then M._devicons_path = vim.fs.normalize(M._devicons_path) end
end

M._diricon_escseq = function()
  local hlgroup = utils.map_get(M, "__resume_data.opts.hls.dir_icon") or M.globals.__HLS.dir_icon
  local _, escseq = utils.ansi_from_hl(hlgroup)
  return escseq
end

-- get icons proxy for the headless instance
M._devicons_geticons = function()
  if not M._has_devicons or not M._devicons or not M._devicons.get_icons then
    return
  end
  -- force refresh if `bg` changed from dark/light (#855)
  if M.__DEVICONS and vim.o.bg == M.__DEVICONS_BG then
    return M.__DEVICONS
  end
  -- save the current background
  M.__DEVICONS_BG = vim.o.bg
  -- rpc request cannot return a table that has mixed elements
  -- of both indexed items and key value, it will fail with
  -- "Cannot convert given lua table"
  -- NOTES:
  -- (1) devicons.get_icons() returns the default icon in [1]
  -- (2) we cannot rely on having either .name or .color (#817)
  local all_devicons = M._devicons.get_icons()
  if not all_devicons or vim.tbl_isempty(all_devicons) then
    -- something is wrong with devicons
    -- can't use `error` due to fast event
    print("[Fzf-lua] error: devicons.get_icons() is nil or empty!")
    return
  end
  -- We only need the name, icon and color properties
  local default_icon = all_devicons[1] or {}
  M.__DEVICONS = {
    ["<default>"] = {
      name = default_icon.name or "Default",
      icon = default_icon.icon or "",
      color = default_icon.color or "#6d8086",
    }
  }
  for k, v in pairs(all_devicons) do
    -- skip all indexed (numeric) entries
    if type(k) == "string" then
      M.__DEVICONS[k] = {
        name = v.name or k,
        icon = v.icon or "",
        color = v.color or (function()
          -- some devicons customizations remove `info.color`
          -- retrieve the color from the highlight group (#801)
          local hlgroup = "DevIcon" .. (v.name or k)
          local hexcol = utils.hexcol_from_hl(hlgroup, "fg")
          if hexcol and #hexcol > 0 then
            return hexcol
          end
        end)(),
      }
    end
  end
  return M.__DEVICONS
end

-- set this so that make_entry won't get nil err when setting remotely
M.__resume_data = {}

-- set|get the latest wrapped process PID
-- NOTE: we don't store this closure in `opts` (or store a ref to `opts`)
-- as together with `__resume_data` it can create a memory leak having to
-- store recursive copies of the `opts` table (#723)
M.set_pid = function(pid)
  M.__pid = pid
end

M.get_pid = function()
  return M.__pid
end

M.resume_get = function(what, opts)
  assert(opts.__resume_key)
  if type(opts.__resume_get) == "function" then
    -- override was set (live_grep, live_workspace_symbols)
    return opts.__resume_get(what, opts)
  end
  local fn_key = tostring(opts.__resume_key):match("[^%s]+$")
  what = string.format("__resume_map.%s%s", fn_key,
    type(what) == "string" and ("." .. what) or "")
  -- _G.dump("resume_get", what, utils.map_get(M, what))
  return utils.map_get(M, what)
end

-- store an option in both the resume options and provider specific __call_opts
M.resume_set = function(what, val, opts)
  assert(opts.__resume_key)
  if type(opts.__resume_set) == "function" then
    -- override was set (live_grep, live_workspace_symbols)
    return opts.__resume_set(what, val, opts)
  end
  local fn_key = tostring(opts.__resume_key):match("[^%s]+$")
  local key1 = string.format("__resume_map.%s%s", fn_key,
    type(what) == "string" and ("." .. what) or "")
  local key2 = string.format("__resume_data.opts.%s", what)
  utils.map_set(M, key1, val)
  utils.map_set(M, key2, val)
  -- backward compatibility for users using `get_last_query`
  if what == "query" then
    utils.map_set(M, "__resume_data.last_query", val)
  end
  -- _G.dump("resume_set", key1, utils.map_get(M, key1))
end

---@param opts {resume: boolean, __call_opts: table}
---@return table
function M.resume_opts(opts)
  assert(opts.resume and opts.__call_opts)
  local __call_opts = M.resume_get(nil, opts)
  opts = vim.tbl_deep_extend("keep", opts, __call_opts or {})
  opts.__call_opts = vim.tbl_deep_extend("keep", opts.__call_opts, __call_opts or {})
  -- _G.dump("__call_opts", opts.__call_opts)
  return opts
end

-- proxy table (with logic) for accessing the global config
M.setup_opts = {}
M.globals = setmetatable({}, {
  __index = function(_, index)
    -- bind tables are logical exception, if specified, do not merge with defaults
    -- normalize all binds as lowercase or we can have duplicate keys (#654)
    if index == "actions" then
      return {
        files = utils.map_tolower(
          utils.map_get(M.setup_opts, "actions.files") or M.defaults.actions.files),
        buffers = utils.map_tolower(
          utils.map_get(M.setup_opts, "actions.buffers") or M.defaults.actions.buffers),
      }
    elseif index == "keymap" then
      return {
        fzf = utils.map_tolower(
          utils.map_get(M.setup_opts, "keymap.fzf") or M.defaults.keymap.fzf),
        builtin = utils.map_tolower(
          utils.map_get(M.setup_opts, "keymap.builtin") or M.defaults.keymap.builtin),
      }
    end
    -- build normalized globals, option priority below:
    --   (1) provider specific globals (post-setup)
    --   (2) generic global-defaults (post-setup), i.e. `setup({ defaults = { ... } })`
    --   (3) fzf-lua's true defaults (pre-setup, static)
    local fzflua_default = utils.map_get(M.defaults, index)
    local setup_default = utils.map_get(M.setup_opts.defaults, index)
    local setup_value = utils.map_get(M.setup_opts, index)
    -- values that aren't tables can't get merged, return highest priority
    if setup_value ~= nil and type(setup_value) ~= "table" then
      return setup_value
    elseif setup_default ~= nil and type(setup_default) ~= "table" then
      return setup_default
    elseif fzflua_default ~= nil and type(fzflua_default) ~= "table" then
      return fzflua_default
    elseif fzflua_default == nil and setup_value == nil then
      return
    end
    -- (1) use fzf-lua's true defaults (pre-setup) as our options base
    local ret = utils.tbl_deep_clone(fzflua_default) or {}
    if (fzflua_default and fzflua_default.prompt) or (setup_value and setup_value.prompt) then
      -- (2) the existence of the `prompt` key implies we're dealing with a provider
      -- override global provider defaults supplied by the user's setup `defaults` table
      ret = vim.tbl_deep_extend("force", ret, M.setup_opts.defaults or {})
    end
    -- (3) override with the specific provider options from the users's `setup` option
    ret = vim.tbl_deep_extend("force", ret, utils.map_get(M.setup_opts, index) or {})
    return ret
  end,
  __newindex = function(_, index, _)
    assert(false, string.format("modifying globals directly isn't allowed [index: %s]", index))
  end
})

do
  -- store circular refs for globals/defaults
  -- used by M.globals.__index and M.defaults.<provider>._actions
  local m = require("fzf-lua.defaults")
  M.defaults = m.defaults
  m.globals = M.globals
end

---@param opts table<string, unknown>|fun():table?
---@param globals string|table?
---@param __resume_key string?
function M.normalize_opts(opts, globals, __resume_key)
  if not opts then opts = {} end

  -- opts can also be a function that returns an opts table
  if type(opts) == "function" then
    opts = opts()
  end

  -- expand opts that were specified with a dot
  -- e.g. `:FzfLua files winopts.border=single`
  for k, v in pairs(opts) do
    if k:match("%.") then
      utils.map_set(opts, k, v)
      opts[k] = nil
    end
  end

  -- save the user's original call params separately
  opts.__call_opts = opts.__call_opts or utils.deepcopy(opts)
  opts.__call_fn = utils.__FNCREF2__()

  -- resume storage data lookup key, default to the calling function ref
  -- __FNCREF2__ will use the 2nd function ref in the stack (calling fn)
  opts.__resume_key = __resume_key
      or opts.__resume_key
      or (type(globals) == "string" and globals)
      or (type(globals) == "table" and globals.__resume_key)
      or utils.__FNCREF2__()

  if type(globals) == "string" then
    -- globals is a string, generate provider globals
    globals = M.globals[globals]
    assert(type(globals) == "table")
  else
    -- backward compat: globals sent directly as table
    -- merge with setup options "defaults" table
    globals = vim.tbl_deep_extend("keep", globals, M.setup_opts.defaults or {})
  end

  -- merge current opts with revious __call_opts on resume
  if opts.resume then
    opts = M.resume_opts(opts)
  end

  -- normalize all binds as lowercase or we can have duplicate keys (#654)
  ---@param m {fzf: table<string, unknown>, builtin: table<string, unknown>}
  ---@return {fzf: table<string, unknown>, builtin: table<string, unknown>}?
  local keymap_tolower = function(m)
    return m and {
      fzf = utils.map_tolower(m.fzf),
      builtin = utils.map_tolower(m.builtin)
    } or nil
  end
  opts.keymap = keymap_tolower(opts.keymap)
  opts.actions = utils.map_tolower(opts.actions)
  globals.keymap = keymap_tolower(globals.keymap)
  globals.actions = utils.map_tolower(globals.actions)

  -- inherit from globals.actions?
  if type(globals._actions) == "function" then
    globals.actions = vim.tbl_deep_extend("keep", globals.actions or {}, globals._actions())
  end

  -- merge with provider defaults from globals (defaults + setup options)
  opts = vim.tbl_deep_extend("keep", opts, utils.tbl_deep_clone(globals))

  -- Merge required tables from globals
  for _, k in ipairs({
    "winopts", "keymap", "fzf_opts", "fzf_tmux_opts", "hls"
  }) do
    opts[k] = vim.tbl_deep_extend("keep",
      -- must clone or map will be saved as reference
      -- and then overwritten if found in 'backward_compat'
      type(opts[k]) == "function" and opts[k]() or opts[k] or {},
      type(M.globals[k]) == "function" and M.globals[k]() or
      type(M.globals[k]) == "table" and utils.tbl_deep_clone(M.globals[k]) or {})
  end

  -- prioritize fzf-tmux split pane flags over the
  -- popup flag `-p` from fzf-lua defaults (#865)
  if type(opts.fzf_tmux_opts) == "table" then
    for _, flag in ipairs({ "-u", "-d", "-l", "-r" }) do
      if opts.fzf_tmux_opts[flag] then
        opts.fzf_tmux_opts["-p"] = nil
      end
    end
  end

  -- Merge `winopts` with outputs from `winopts_fn`
  local winopts_fn = opts.winopts_fn or M.globals.winopts_fn
  if type(winopts_fn) == "function" then
    opts.winopts = vim.tbl_deep_extend("force", opts.winopts, winopts_fn() or {})
  end

  -- Merge arrays from globals|defaults, can't use 'vim.tbl_xxx'
  -- for these as they only work for maps, ie. '{ key = value }'
  for _, k in ipairs({ "file_ignore_patterns" }) do
    for _, m in ipairs({ globals, M.globals }) do
      if m[k] then
        for _, item in ipairs(m[k]) do
          if not opts[k] then opts[k] = {} end
          table.insert(opts[k], item)
        end
      end
    end
  end

  -- these options are copied from globals unless specifically set
  -- also check if we need to override 'opts.prompt' from cli args
  -- if we don't override 'opts.prompt' 'FzfWin.save_query' will
  -- fail to remove the prompt part from resume saved query (#434)
  for _, s in ipairs({ "fzf_args", "fzf_cli_args", "fzf_raw_args" }) do
    if opts[s] == nil then
      opts[s] = M.globals[s]
    end
    local pattern_prefix = "%-%-prompt="
    local pattern_prompt = ".-"
    local surround = opts[s] and opts[s]:match(pattern_prefix .. "(.)")
    -- prompt was set without surrounding quotes
    -- technically an error but we can handle it gracefully instead
    if surround and surround ~= [[']] and surround ~= [["]] then
      surround = ""
      pattern_prompt = "[^%s]+"
    end
    if surround then
      local pattern_capture = pattern_prefix ..
          ("%s(%s)%s"):format(surround, pattern_prompt, surround)
      local pattern_gsub = pattern_prefix ..
          ("%s%s%s"):format(surround, pattern_prompt, surround)
      if opts[s]:match(pattern_gsub) then
        opts.prompt = opts[s]:match(pattern_capture)
        opts[s] = opts[s]:gsub(pattern_gsub, "")
      end
    end
  end

  -- backward compatibility, rhs overrides lhs
  -- (rhs being the "old" option)
  local backward_compat = {
    { "winopts.row",                  "winopts.win_row" },
    { "winopts.col",                  "winopts.win_col" },
    { "winopts.width",                "winopts.win_width" },
    { "winopts.height",               "winopts.win_height" },
    { "winopts.border",               "winopts.win_border" },
    { "winopts.on_create",            "winopts.window_on_create" },
    { "winopts.preview.wrap",         "preview_wrap" },
    { "winopts.preview.border",       "preview_border" },
    { "winopts.preview.hidden",       "preview_opts" },
    { "winopts.preview.vertical",     "preview_vertical" },
    { "winopts.preview.horizontal",   "preview_horizontal" },
    { "winopts.preview.layout",       "preview_layout" },
    { "winopts.preview.flip_columns", "flip_columns" },
    { "winopts.preview.default",      "default_previewer" },
    { "winopts.preview.delay",        "previewers.builtin.delay" },
    { "winopts.preview.title",        "previewers.builtin.title" },
    { "winopts.preview.title_pos",    "winopts.preview.title_align" },
    { "winopts.preview.scrollbar",    "previewers.builtin.scrollbar" },
    { "winopts.preview.scrollchar",   "previewers.builtin.scrollchar" },
    { "cwd_header",                   "show_cwd_header" },
    { "cwd_prompt",                   "show_cwd_prompt" },
    { "resume",                       "continue_last_search" },
    { "resume",                       "repeat_last_search" },
    { "hls.normal",                   "winopts.hl_normal" },
    { "hls.border",                   "winopts.hl_border" },
    { "hls.cursor",                   "previewers.builtin.hl_cursor" },
    { "hls.cursorline",               "previewers.builtin.hl_cursorline" },
    { "hls",                          "winopts.hl" },
  }

  -- iterate backward compat map, retrieve values from opts or globals
  for _, t in ipairs(backward_compat) do
    local new_key, old_key = t[1], t[2]
    local old_val = utils.map_get(opts, old_key) or utils.map_get(M.globals, old_key)
    local new_val = utils.map_get(opts, new_key)
    if old_val ~= nil then
      if type(old_val) == "table" and type(new_val) == "table" then
        utils.map_set(opts, new_key, vim.tbl_deep_extend("keep", new_val, old_val))
      else
        utils.map_set(opts, new_key, old_val)
      end
      utils.map_set(opts, old_key, nil)
      -- utils.warn(string.format("option moved/renamed: '%s' -> '%s'", old_key, new_key))
    end
  end

  -- Setup completion options
  if opts.complete then
    opts.actions = opts.actions or {}
    opts.actions["default"] = actions.complete
  end

  -- Merge highlight overrides with defaults, we only do this after the
  -- backward compat copy due to the migration of `winopts.hl` -> `hls`
  opts.hls = vim.tbl_deep_extend("keep", opts.hls or {}, M.globals.__HLS)

  -- Cache provider specific highlights so we don't call vim functions
  -- within a "fast event" (`vim.in_fast_event()`) and err with:
  -- E5560: vimL function must not be called in a lua loop callback
  for _, hl_opt in ipairs(opts._cached_hls or {}) do
    local hlgroup = opts.hls[hl_opt]
    assert(hlgroup ~= nil) -- must exist
    local _, escseq = utils.ansi_from_hl(hlgroup)
    utils.cache_ansi_escseq(hlgroup, escseq)
  end

  if type(opts.previewer) == "function" then
    -- we use a function so the user can override
    -- globals.winopts.preview.default
    opts.previewer = opts.previewer()
  end
  if type(opts.previewer) == "table" then
    -- merge with the default builtin previewer
    opts.previewer = vim.tbl_deep_extend("keep",
      opts.previewer, M.globals.previewers.builtin)
  end

  -- we need the original `cwd` with `autochdir=true` (#882)
  -- use `_cwd` to not interfere with supplied users' options
  -- as this can have unintended effects (e.g. in "buffers")
  if vim.o.autochdir and not opts.cwd then
    opts._cwd = vim.loop.cwd()
  end

  if opts.cwd and #opts.cwd > 0 then
    opts.cwd = vim.fn.expand(opts.cwd)
    if not vim.loop.fs_stat(opts.cwd) then
      utils.warn(("Unable to access '%s', removing 'cwd' option."):format(opts.cwd))
      opts.cwd = nil
    else
      -- relative paths in cwd are inaccessible when using multiprocess
      -- as the external process have no awareness of our current working
      -- directory so we must convert to full path (#375)
      if not path.starts_with_separator(opts.cwd) then
        opts.cwd = path.join({ vim.loop.cwd(), opts.cwd })
      end
    end
  end


  -- test for valid git_repo
  opts.git_icons = opts.git_icons and path.is_git_repo(opts, true)

  local executable = function(binary, fncerr, strerr)
    if binary and vim.fn.executable(binary) ~= 1 then
      fncerr(("'%s' is not a valid executable, %s"):format(binary, strerr))
      return false
    end
    return true
  end

  opts.fzf_bin = opts.fzf_bin or M.globals.fzf_bin
  opts.fzf_bin = opts.fzf_bin and vim.fn.expand(opts.fzf_bin) or nil
  if not opts.fzf_bin or
      not executable(opts.fzf_bin, utils.warn, "fallback to 'fzf'.") then
    -- default|fallback to fzf
    opts.fzf_bin = "fzf"
    -- try fzf plugin if fzf is not installed globally
    if vim.fn.executable(opts.fzf_bin) ~= 1 then
      local ok, fzf_plug = pcall(vim.api.nvim_call_function, "fzf#exec", {})
      if ok and fzf_plug then
        opts.fzf_bin = fzf_plug
      end
    end
    if not executable(opts.fzf_bin, utils.err,
          "aborting. Please make sure 'fzf' is in installed.") then
      return nil
    end
  end

  -- are we using skim?
  opts._is_skim = opts.fzf_bin:find("sk") ~= nil

  -- enforce fzf minimum requirements
  if not opts._is_skim then
    local FZF_VERSION, rc, err = utils.fzf_version(opts)
    opts.__FZF_VERSION = FZF_VERSION
    if not opts.__FZF_VERSION then
      utils.err(string.format(
        "'fzf --version' failed with error %s: %s", rc, err))
      return nil
    elseif opts.__FZF_VERSION < 0.24 then
      utils.err(string.format(
        "fzf version %.2f is lower than minimum (0.24), aborting.",
        opts.__FZF_VERSION))
      return nil
    elseif opts.__FZF_VERSION < 0.27 then
      -- remove `--border=none`, fails when < 0.27
      opts.fzf_opts = opts.fzf_opts or {}
      opts.fzf_opts["--border"] = false
    end
  end

  -- are we using fzf-tmux
  opts._is_fzf_tmux = vim.env.TMUX and opts.fzf_bin:match("fzf%-tmux$")

  -- libuv.spawn_nvim_fzf_cmd() pid callback
  opts._set_pid = M.set_pid
  opts._get_pid = M.get_pid

  -- setup devicons terminal highlight groups does nothing unless
  -- neovim `bg` is changed, call via utils/loadstring to prevent
  -- circular require and also make sure "make_entry.lua" isn't
  -- loaded before devicons vars are setup by this module
  -- TODO: cleanup the background update and devicons load logic
  utils.setup_devicon_term_hls()

  -- mark as normalized
  opts._normalized = true

  return opts
end

M.bytecode = function(s, datatype)
  local keys = utils.strsplit(s, ".")
  local iter = M
  for i = 1, #keys do
    iter = iter[keys[i]]
    if not iter then break end
    if i == #keys and type(iter) == datatype then
      -- Not sure if second argument 'true' is needed
      -- can't find any references for it other than
      -- it being used in packer.nvim
      return string.dump(iter, true)
    end
  end
end

M.set_action_helpstr = function(fn, helpstr)
  assert(type(fn) == "function")
  M._action_to_helpstr[fn] = helpstr
end

M.get_action_helpstr = function(fn)
  return M._action_to_helpstr[fn]
end

M._action_to_helpstr = {
  [actions.dummy_abort]         = "abort",
  [actions.file_edit]           = "file-edit",
  [actions.file_edit_or_qf]     = "file-edit-or-qf",
  [actions.file_split]          = "file-split",
  [actions.file_vsplit]         = "file-vsplit",
  [actions.file_tabedit]        = "file-tabedit",
  [actions.file_sel_to_qf]      = "file-selection-to-qf",
  [actions.file_sel_to_ll]      = "file-selection-to-loclist",
  [actions.file_switch]         = "file-switch",
  [actions.file_switch_or_edit] = "file-switch-or-edit",
  [actions.buf_edit]            = "buffer-edit",
  [actions.buf_edit_or_qf]      = "buffer-edit-or-qf",
  [actions.buf_sel_to_qf]       = "buffer-selection-to-qf",
  [actions.buf_sel_to_ll]       = "buffer-selection-to-loclist",
  [actions.buf_split]           = "buffer-split",
  [actions.buf_vsplit]          = "buffer-vsplit",
  [actions.buf_tabedit]         = "buffer-tabedit",
  [actions.buf_del]             = "buffer-delete",
  [actions.buf_switch]          = "buffer-switch",
  [actions.buf_switch_or_edit]  = "buffer-switch-or-edit",
  [actions.colorscheme]         = "set-colorscheme",
  [actions.run_builtin]         = "run-builtin",
  [actions.ex_run]              = "edit-cmd",
  [actions.ex_run_cr]           = "exec-cmd",
  [actions.exec_menu]           = "exec-menu",
  [actions.search]              = "edit-search",
  [actions.search_cr]           = "exec-search",
  [actions.goto_mark]           = "goto-mark",
  [actions.goto_jump]           = "goto-jump",
  [actions.keymap_apply]        = "keymap-apply",
  [actions.keymap_edit]         = "keymap-edit",
  [actions.keymap_split]        = "keymap-split",
  [actions.keymap_vsplit]       = "keymap-vsplit",
  [actions.keymap_tabedit]      = "keymap-tabedit",
  [actions.spell_apply]         = "spell-apply",
  [actions.set_filetype]        = "set-filetype",
  [actions.packadd]             = "packadd",
  [actions.help]                = "help-open",
  [actions.help_vert]           = "help-vertical",
  [actions.help_tab]            = "help-tab",
  [actions.man]                 = "man-open",
  [actions.man_vert]            = "man-vertical",
  [actions.man_tab]             = "man-tab",
  [actions.git_switch]          = "git-switch",
  [actions.git_checkout]        = "git-checkout",
  [actions.git_reset]           = "git-reset",
  [actions.git_stage]           = "git-stage",
  [actions.git_unstage]         = "git-unstage",
  [actions.git_stage_unstage]   = "git-stage-unstage",
  [actions.git_stash_pop]       = "git-stash-pop",
  [actions.git_stash_drop]      = "git-stash-drop",
  [actions.git_stash_apply]     = "git-stash-apply",
  [actions.git_buf_edit]        = "git-buffer-edit",
  [actions.git_buf_tabedit]     = "git-buffer-tabedit",
  [actions.git_buf_split]       = "git-buffer-split",
  [actions.git_buf_vsplit]      = "git-buffer-vsplit",
  [actions.git_yank_commit]     = "git-yank-commit",
  [actions.arg_add]             = "arg-list-add",
  [actions.arg_del]             = "arg-list-delete",
  [actions.toggle_ignore]       = "toggle-ignore",
  [actions.grep_lgrep]          = "grep<->lgrep",
  [actions.sym_lsym]            = "sym<->lsym",
  [actions.tmux_buf_set_reg]    = "set-register",
  [actions.paste_register]      = "paste-register",
  [actions.set_qflist]          = "set-{qf|loc}list",
  [actions.apply_profile]       = "apply-profile",
  [actions.complete]            = "complete",
}

return M
