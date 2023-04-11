local path = require "fzf-lua.path"
local utils = require "fzf-lua.utils"
local actions = require "fzf-lua.actions"

-- Clear the default command or it would interfere with our options
-- not needed anymore, we are pretty much overriding all options
-- with our cli args, in addition this could conflict with fzf.vim
-- vim.env.FZF_DEFAULT_OPTS = ''

local M = {}

M._has_devicons, M._devicons = pcall(require, "nvim-web-devicons")

-- get the devicons module path
M._devicons_path = M._has_devicons and M._devicons and M._devicons.setup
    and debug.getinfo(M._devicons.setup, "S").source:gsub("^@", "")

-- get icons proxy for the headless instance
M._devicons_geticons = function()
  if not M._has_devicons or not M._devicons or not M._devicons.get_icons then
    return
  end
  -- rpc request cannot return a table that has mixed elements
  -- of both indexed items and key value, it will fail with
  -- "Cannot convert given lua table"
  -- devicons.get_icons() returns the default icon in the first index
  -- if we delete it the conversion succeeds as a key-value only map
  -- must use 'tbl_deep_extend' or 'table.remove' will delete
  -- nvim-web-devicons default icon as 'get_icons' returns a ref
  local icons = vim.tbl_deep_extend("keep", {}, M._devicons.get_icons())
  -- the default icon in [1] is not a gurantee as nvim-web-devicons
  -- can be configured with `default = false`
  if icons[1] and icons[1].name == "Default" then
    local default = table.remove(icons, 1)
    icons["<default>"] = default
  end
  return icons
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

-- Reset globals to default
function M.reset_defaults()
  local m = require("fzf-lua.defaults")
  M.DEFAULTS = m
  M.defaults = m.defaults
  M.globals = utils.deepcopy(M.defaults)
  m.globals = M.globals
end

-- Call once so we aren't dependent on calling setup()
M.reset_defaults()

function M.normalize_opts(opts, defaults)
  if not opts then opts = {} end

  -- opts can also be a function that returns an opts table
  if type(opts) == "function" then
    opts = opts()
  end

  -- ignore case for keybinds or conflicts may occur (#654)
  local keymap_tolower = function(m)
    return m and {
          fzf = utils.map_tolower(m.fzf),
          builtin = utils.map_tolower(m.builtin)
        } or nil
  end
  opts.keymap = keymap_tolower(opts.keymap)
  opts.actions = utils.map_tolower(opts.actions)
  defaults.keymap = keymap_tolower(defaults.keymap)
  defaults.actions = utils.map_tolower(defaults.actions)
  if M.globals.actions then
    M.globals.actions.files = utils.map_tolower(M.globals.actions.files)
    M.globals.actions.buffers = utils.map_tolower(M.globals.actions.buffers)
  end
  M.globals.keymap = keymap_tolower(M.globals.keymap)

  -- save the user's call parameters separately
  -- we reuse those with 'actions.grep_lgrep'
  opts.__call_opts = opts.__call_opts or utils.deepcopy(opts)

  -- inherit from globals.actions?
  if type(defaults._actions) == "function" then
    defaults.actions = vim.tbl_deep_extend("keep",
      defaults.actions or {},
      defaults._actions())
  end

  -- First, merge with provider defaults
  -- we must clone the 'defaults' tbl, otherwise 'opts.actions.default'
  -- overrides 'config.globals.lsp.actions.default' in neovim 6.0
  -- which then prevents the default action of all other LSP providers
  -- https://github.com/ibhagwan/fzf-lua/issues/197
  opts = vim.tbl_deep_extend("keep", opts, utils.tbl_deep_clone(defaults))

  -- Merge required tables from globals
  for _, k in ipairs({
    "winopts", "keymap", "fzf_opts", "fzf_tmux_opts", "previewers"
  }) do
    opts[k] = vim.tbl_deep_extend("keep",
      -- must clone or map will be saved as reference
      -- and then overwritten if found in 'backward_compat'
      opts[k] or {}, utils.tbl_deep_clone(M.globals[k]) or {})
  end

  -- Merge arrays from globals|defaults, can't use 'vim.tbl_xxx'
  -- for these as they only work for maps, ie. '{ key = value }'
  for _, k in ipairs({ "file_ignore_patterns" }) do
    for _, m in ipairs({ defaults, M.globals }) do
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

  local function get_opt(o, t1, t2)
    if t1[o] ~= nil then
      return t1[o]
    else
      return t2[o]
    end
  end

  -- Merge global resume options
  opts.global_resume = get_opt("global_resume", opts, M.globals)

  -- Backward compat: renamed '{continue|repeat}_last_search'
  if opts.resume == nil then
    for _, o in ipairs({ "repeat_last_search", "continue_last_search" }) do
      if opts[o] ~= nil then
        opts.resume = opts[o]
      end
    end
  end

  -- global option overrides. If exists, these options will
  -- be used in a "LOGICAL AND" against the local option (#188)
  -- e.g.:
  --    git_icons = TRUE
  --    global_git_icons = FALSE
  -- the resulting 'git_icons' would be:
  --    git_icons = TRUE && FALSE (==FALSE)
  for _, o in ipairs({ "file_icons", "git_icons", "color_icons" }) do
    local g_opt = get_opt("global_" .. o, opts, M.globals)
    if g_opt ~= nil then
      opts[o] = opts[o] and g_opt
    end
  end

  -- backward compatibility, rhs overrides lhs
  -- (rhs being the "old" option)
  local backward_compat = {
    ["winopts.row"]                  = "winopts.win_row",
    ["winopts.col"]                  = "winopts.win_col",
    ["winopts.width"]                = "winopts.win_width",
    ["winopts.height"]               = "winopts.win_height",
    ["winopts.border"]               = "winopts.win_border",
    ["winopts.on_create"]            = "winopts.window_on_create",
    ["winopts.preview.wrap"]         = "preview_wrap",
    ["winopts.preview.border"]       = "preview_border",
    ["winopts.preview.hidden"]       = "preview_opts",
    ["winopts.preview.vertical"]     = "preview_vertical",
    ["winopts.preview.horizontal"]   = "preview_horizontal",
    ["winopts.preview.layout"]       = "preview_layout",
    ["winopts.preview.flip_columns"] = "flip_columns",
    ["winopts.preview.default"]      = "default_previewer",
    ["winopts.hl.normal"]            = "winopts.hl_normal",
    ["winopts.hl.border"]            = "winopts.hl_border",
    ["winopts.hl.cursor"]            = "previewers.builtin.hl_cursor",
    ["winopts.hl.cursorline"]        = "previewers.builtin.hl_cursorline",
    ["winopts.preview.delay"]        = "previewers.builtin.delay",
    ["winopts.preview.title"]        = "previewers.builtin.title",
    ["winopts.preview.title_align"]  = "previewers.builtin.title_align",
    ["winopts.preview.scrollbar"]    = "previewers.builtin.scrollbar",
    ["winopts.preview.scrollchar"]   = "previewers.builtin.scrollchar",
    -- Diagnostics & LSP symbols separation options
    ["diag_icons"]                   = "lsp.lsp_icons",
  }

  -- recursive key loopkup, can also set new value
  local map_recurse = function(m, s, v, w)
    local keys = utils.strsplit(s, ".")
    local val, map = m, nil
    for i = 1, #keys do
      map = val
      val = val[keys[i]]
      if not val then break end
      if v ~= nil and i == #keys then map[keys[i]] = v end
    end
    if v and w then utils.warn(w) end
    return val
  end

  -- iterate backward compat map, retrieve values from opts or globals
  for k, v in pairs(backward_compat) do
    map_recurse(opts, k, map_recurse(opts, v) or map_recurse(M.globals, v))
    -- ,("'%s' is now defined under '%s'"):format(v, k))
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

  -- are we using fzf-tmux
  opts._is_fzf_tmux = vim.env.TMUX and opts.fzf_bin:match("fzf%-tmux$")

  -- libuv.spawn_nvim_fzf_cmd() pid callback
  opts._set_pid = M.set_pid
  opts._get_pid = M.get_pid

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

-- returns nil if not found
M.get_global = function(s)
  local keys = utils.strsplit(s, ".")
  local iter = M.globals
  for i = 1, #keys do
    iter = iter[keys[i]]
    if not iter then break end
    if i == #keys then
      return iter
    end
  end
end

-- builds the tree if needed
M.set_global = function(s, value)
  local keys = utils.strsplit(s, ".")
  local iter = M.globals
  for i = 1, #keys do
    if i == #keys then
      iter[keys[i]] = value
    else
      -- build the new leaf on parent
      -- to preserve original table ref
      local parent = iter
      if not parent[keys[i]] then
        parent[keys[i]] = {}
      end
      iter = parent[keys[i]]
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
  [actions.git_stage]           = "git-stage",
  [actions.git_unstage]         = "git-unstage",
  [actions.git_reset]           = "git-reset",
  [actions.git_stash_pop]       = "git-stash-pop",
  [actions.git_stash_drop]      = "git-stash-drop",
  [actions.git_stash_apply]     = "git-stash-apply",
  [actions.git_buf_edit]        = "git-buffer-edit",
  [actions.git_buf_tabedit]     = "git-buffer-tabedit",
  [actions.git_buf_split]       = "git-buffer-split",
  [actions.git_buf_vsplit]      = "git-buffer-vsplit",
  [actions.arg_add]             = "arg-list-add",
  [actions.arg_del]             = "arg-list-delete",
  [actions.grep_lgrep]          = "grep<->lgrep",
  [actions.sym_lsym]            = "sym<->lsym",
  [actions.tmux_buf_set_reg]    = "set-register",
  [actions.paste_register]      = "paste-register",
  [actions.set_qflist]          = "set-{qf|loc}list",
  [actions.apply_profile]       = "apply-profile",
  [actions.complete_insert]     = "complete-insert",
}

return M
