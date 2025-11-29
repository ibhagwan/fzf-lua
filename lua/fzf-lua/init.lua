---@diagnostic disable: duplicate-require
local gen = _G.arg[0] == "lua/fzf-lua/init.lua"
if gen then
  vim.opt.rtp:append(vim.fn.fnamemodify(debug.getinfo(1, "S").source:gsub("^@", ""), ":h:h:h:p"))
end

---@diagnostic disable-next-line: deprecated
local uv = vim.uv or vim.loop
local path = require "fzf-lua.path"
local utils = require "fzf-lua.utils"
local config = require "fzf-lua.config"

---@class fzf-lua
local M = {}

do
  local function source_vimL(path_parts)
    local vimL_file = path.join(path_parts)
    if uv.fs_stat(vimL_file) then
      vim.cmd("source " .. vim.fn.fnameescape(vimL_file))
      -- print(string.format("loaded '%s'", vimL_file))
    end
  end

  local currFile = debug.getinfo(1, "S").source:gsub("^@", "")
  vim.g.fzf_lua_directory = path.normalize(assert(path.parent(currFile)))
  vim.g.fzf_lua_root = path.parent(assert(path.parent(vim.g.fzf_lua_directory)))

  -- Autoload scipts dynamically loaded on `vim.fn[fzf_lua#...]` call
  -- `vim.fn.exists("*fzf_lua#...")` will return 0 unless we manuall source
  source_vimL({ vim.g.fzf_lua_root, "autoload", "fzf_lua.vim" })
  -- Set var post source as the top of the file `require` will return 0
  -- due to it potentially being loaded before "autoload/fzf_lua.vim"
  utils.__HAS_AUTOLOAD_FNS = vim.fn.exists("*fzf_lua#getbufinfo") == 1

  -- Create a new RPC server (tmp socket) to listen to messages (actions/headless)
  -- this is safer than using $NVIM_LISTEN_ADDRESS. If the user is using a custom
  -- fixed $NVIM_LISTEN_ADDRESS, different neovim instances will use the same path
  -- as their address and messages won't be received on older instances
  if not vim.g.fzf_lua_server then
    local ok, srv = pcall(vim.fn.serverstart, "fzf-lua." .. os.time())
    if ok then
      vim.g.fzf_lua_server = srv
    else
      error(string.format(
        "serverstart(): %s. Please make sure 'XDG_RUNTIME_DIR' (%s) is writeable",
        srv, vim.fn.stdpath("run")))
    end
  end

  -- Workaround for using `:wqa` with "hide"
  -- https://github.com/neovim/neovim/issues/14061
  vim.api.nvim_create_autocmd("ExitPre", {
    group = vim.api.nvim_create_augroup("FzfLuaNvimQuit", { clear = true }),
    callback = function()
      local win = utils.fzf_winobj()
      if win and win:hidden() then ---@diagnostic disable-next-line: param-type-mismatch
        vim.api.nvim_buf_delete(win._hidden_fzf_bufnr, { force = true })
      end
    end,
  })

  -- Setup global var
  _G.FzfLua = M
end

-- Setup fzf-lua's highlights, use `override=true` to reset all highlights
function M.setup_highlights(override)
  local is_light = vim.o.bg == "light"
  local bg_changed = config.__HLS_STATE and config.__HLS_STATE.bg ~= vim.o.bg
  config.__HLS_STATE = { colorscheme = vim.g.colors_name, bg = vim.o.bg }
  -- we use `default = true` so calling this function doesn't override the colorscheme
  local default = not override
  local highlights = {
    { "FzfLuaNormal",            "normal",         { default = default, link = "Normal" } },
    { "FzfLuaBorder",            "border",         { default = default, link = "Normal" } },
    { "FzfLuaTitle",             "title",          { default = default, link = "FzfLuaNormal" } },
    { "FzfLuaTitleFlags",        "title_flags",    { default = default, link = "CursorLine" } },
    { "FzfLuaBackdrop",          "backdrop",       { default = default, bg = "Black" } },
    { "FzfLuaHelpNormal",        "help_normal",    { default = default, link = "FzfLuaNormal" } },
    { "FzfLuaHelpBorder",        "help_border",    { default = default, link = "FzfLuaBorder" } },
    { "FzfLuaPreviewNormal",     "preview_normal", { default = default, link = "FzfLuaNormal" } },
    { "FzfLuaPreviewBorder",     "preview_border", { default = default, link = "FzfLuaBorder" } },
    { "FzfLuaPreviewTitle",      "preview_title",  { default = default, link = "FzfLuaTitle" } },
    { "FzfLuaCursor",            "cursor",         { default = default, link = "Cursor" } },
    { "FzfLuaCursorLine",        "cursorline",     { default = default, link = "CursorLine" } },
    { "FzfLuaCursorLineNr",      "cursorlinenr",   { default = default, link = "CursorLineNr" } },
    { "FzfLuaSearch",            "search",         { default = default, link = "IncSearch" } },
    { "FzfLuaScrollBorderEmpty", "scrollborder_e", { default = default, link = "FzfLuaBorder" } },
    { "FzfLuaScrollBorderFull",  "scrollborder_f", { default = default, link = "FzfLuaBorder" } },
    { "FzfLuaScrollFloatEmpty",  "scrollfloat_e",  { default = default, link = "PmenuSbar" } },
    { "FzfLuaScrollFloatFull",   "scrollfloat_f",  { default = default, link = "PmenuThumb" } },
    { "FzfLuaDirIcon",           "dir_icon",       { default = default, link = "Directory" } },
    { "FzfLuaDirPart",           "dir_part",       { default = default, link = "Comment" } },
    { "FzfLuaFilePart",          "file_part",      { default = default, link = "@none" } },
    -- Fzf terminal hls, colors from `vim.api.nvim_get_color_map()`
    { "FzfLuaHeaderBind", "header_bind",
      { default = default, fg = is_light and "MediumSpringGreen" or "BlanchedAlmond" } },
    { "FzfLuaHeaderText", "header_text",
      { default = default, fg = is_light and "Brown4" or "Brown1" } },
    { "FzfLuaPathColNr", "path_colnr",   -- qf|diag|lsp
      { default = default, fg = is_light and "CadetBlue4" or "CadetBlue1" } },
    { "FzfLuaPathLineNr", "path_linenr", -- qf|diag|lsp
      { default = default, fg = is_light and "MediumSpringGreen" or "LightGreen" } },
    { "FzfLuaLivePrompt", "live_prompt", -- "live" queries prompt text color
      { default = default, fg = is_light and "PaleVioletRed1" or "PaleVioletRed1" } },
    { "FzfLuaLiveSym", "live_sym",       -- lsp_live_workspace_symbols query
      { default = default, fg = is_light and "PaleVioletRed1" or "PaleVioletRed1" } },
    -- lines|blines|treesitter
    { "FzfLuaBufId",     "buf_id",     { default = default, link = "TabLine" } },
    { "FzfLuaBufName",   "buf_name",   { default = default, link = "Directory" } },
    { "FzfLuaBufLineNr", "buf_linenr", { default = default, link = "LineNr" } },
    -- buffers|tabs
    { "FzfLuaBufNr", "buf_nr",
      { default = default, fg = is_light and "AquaMarine3" or "BlanchedAlmond" } },
    { "FzfLuaBufFlagCur", "buf_flag_cur",
      { default = default, fg = is_light and "Brown4" or "Brown1" } },
    { "FzfLuaBufFlagAlt", "buf_flag_alt",
      { default = default, fg = is_light and "CadetBlue4" or "CadetBlue1" } },
    { "FzfLuaTabTitle", "tab_title",   -- tabs only
      { default = default, fg = is_light and "CadetBlue4" or "LightSkyBlue1", bold = true } },
    { "FzfLuaTabMarker", "tab_marker", -- tabs only
      { default = default, fg = is_light and "MediumSpringGreen" or "BlanchedAlmond", bold = true } },
    -- commands
    { "FzfLuaCmdEx",         "cmd_ex",         { default = default, link = "Statement" } },
    { "FzfLuaCmdBuf",        "cmd_buf",        { default = default, link = "Added" } },
    { "FzfLuaCmdGlobal",     "cmd_global",     { default = default, link = "Directory" } },
    -- highlight groups for `fzf_colors=true`
    { "FzfLuaFzfNormal",     "fzf.normal",     { default = default, link = "FzfLuaNormal" } },
    { "FzfLuaFzfCursorLine", "fzf.cursorline", { default = default, link = "FzfLuaCursorLine" } },
    { "FzfLuaFzfMatch",      "fzf.match",      { default = default, link = "Special" } },
    { "FzfLuaFzfBorder",     "fzf.border",     { default = default, link = "FzfLuaBorder" } },
    { "FzfLuaFzfScrollbar",  "fzf.scrollbar",  { default = default, link = "FzfLuaFzfBorder" } },
    { "FzfLuaFzfSeparator",  "fzf.separator",  { default = default, link = "FzfLuaFzfBorder" } },
    { "FzfLuaFzfGutter",     "fzf.gutter",     { default = default, link = "FzfLuaNormal" } },
    { "FzfLuaFzfHeader",     "fzf.header",     { default = default, link = "FzfLuaTitle" } },
    { "FzfLuaFzfInfo",       "fzf.info",       { default = default, link = "NonText" } },
    { "FzfLuaFzfPointer",    "fzf.pointer",    { default = default, link = "Special" } },
    { "FzfLuaFzfMarker",     "fzf.marker",     { default = default, link = "FzfLuaFzfPointer" } },
    { "FzfLuaFzfSpinner",    "fzf.spinner",    { default = default, link = "FzfLuaFzfPointer" } },
    { "FzfLuaFzfPrompt",     "fzf.prompt",     { default = default, link = "Special" } },
    { "FzfLuaFzfQuery",      "fzf.query",      { default = default, link = "FzfLuaNormal" } },
  }
  for _, a in ipairs(highlights) do
    local hl_name, _, hl_def = a[1], a[2], a[3]
    -- If color was a linked colormap and bg changed set definition to override
    if hl_def.fg and bg_changed then
      local fg_current = vim.fn.synIDattr(vim.fn.synIDtrans(vim.fn.hlID(hl_name)), "fg")
      if fg_current and not fg_current:match("^#") and fg_current ~= hl_def.fg then
        hl_def.default = false
      end
    end
    vim.api.nvim_set_hl(0, hl_name, hl_def)
  end

  -- courtesy of fzf.vim
  do
    local termguicolors = vim.o.termguicolors
    vim.api.nvim_set_hl(0, "fzf1",
      {
        default = true,
        ctermfg = termguicolors and 1 or 161,
        ctermbg = termguicolors and 8 or 238,
        fg = "#E12672",
        bg = "#565656"
      })
    vim.api.nvim_set_hl(0, "fzf2",
      {
        default = true,
        ctermfg = termguicolors and 2 or 151,
        ctermbg = termguicolors and 8 or 238,
        fg = "#BCDDBD",
        bg =
        "#565656"
      })
    vim.api.nvim_set_hl(0, "fzf3",
      {
        default = true,
        ctermfg = termguicolors and 7 or 252,
        ctermbg = termguicolors and 8 or 238,
        fg = "#D9D9D9",
        bg = "#565656"
      })
  end

  -- Init the colormap singleton
  utils.COLORMAP()
end

-- Setup highlights at least once on load in
-- case the user decides not to call `setup()`
M.setup_highlights()

---@param opts? fzf-lua.profile|fzf-lua.Config|{}
---@param do_not_reset_defaults? boolean
function M.setup(opts, do_not_reset_defaults)
  opts = type(opts) == "table" and opts or {}
  -- Defaults to picker info in win title if neovim version >= 0.9, prompt otherwise
  opts[1] = opts[1] == nil and "default" or opts[1]
  if opts[1] then
    -- Did the user supply profile(s) to load?
    opts = vim.tbl_deep_extend("keep", opts,
      utils.load_profiles(opts[1], opts[2] == nil and 1 or opts[2]))
  end
  if do_not_reset_defaults then
    -- no defaults reset requested, merge with previous setup options
    opts = vim.tbl_deep_extend("keep", opts, config.setup_opts or {})
  end
  -- backward compat `global_{git|gile|color}_icons`
  -- converts `global_file_icons` to `defaults.file_icons`, etc
  for _, o in ipairs({ "file_icons", "git_icons", "color_icons" }) do
    local gopt = "global_" .. o
    if opts[gopt] ~= nil then
      opts.defaults = opts.defaults or {}
      opts.defaults[o] = opts[gopt]
      opts[gopt] = nil
      local oldk = ("%s = %s"):format(gopt, tostring(opts.defaults[o]))
      local newk = ("defaults = { %s = %s }"):format(gopt, tostring(opts.defaults[o]))
      vim.deprecate(oldk, newk, "Jan 2026", "FzfLua")
    end
  end
  -- backward compat, merge lsp.symbols into lsp.{document|workspace}_synbols
  if opts.lsp and opts.lsp.symbols then
    opts.lsp.document_symbols = vim.tbl_deep_extend("keep",
      opts.lsp.document_symbols or {}, opts.lsp.symbols)
    opts.lsp.workspace_symbols = vim.tbl_deep_extend("keep",
      opts.lsp.workspace_symbols or {}, opts.lsp.symbols)
  end
  -- set custom &nbsp if caller requested
  if type(opts.nbsp) == "string" then utils.nbsp = opts.nbsp end
  -- store the setup options
  config.setup_opts = opts
  -- setup highlights
  M.setup_highlights()
end

M.redraw = function()
  local winobj = require "fzf-lua".win.__SELF()
  if winobj then
    winobj:redraw()
  end
end

local lazyloaded_modules = {
  files = { "fzf-lua.providers.files", "files" },
  args = { "fzf-lua.providers.files", "args" },
  grep = { "fzf-lua.providers.grep", "grep" },
  grep_last = { "fzf-lua.providers.grep", "grep_last" },
  grep_cword = { "fzf-lua.providers.grep", "grep_cword" },
  grep_cWORD = { "fzf-lua.providers.grep", "grep_cWORD" },
  grep_visual = { "fzf-lua.providers.grep", "grep_visual" },
  grep_curbuf = { "fzf-lua.providers.grep", "grep_curbuf" },
  grep_quickfix = { "fzf-lua.providers.grep", "grep_quickfix" },
  grep_loclist = { "fzf-lua.providers.grep", "grep_loclist" },
  grep_project = { "fzf-lua.providers.grep", "grep_project" },
  live_grep = { "fzf-lua.providers.grep", "live_grep" },
  live_grep_native = { "fzf-lua.providers.grep", "live_grep_native" },
  live_grep_resume = { "fzf-lua.providers.grep", "live_grep_resume" },
  live_grep_glob = { "fzf-lua.providers.grep", "live_grep_glob" },
  lgrep_curbuf = { "fzf-lua.providers.grep", "lgrep_curbuf" },
  lgrep_quickfix = { "fzf-lua.providers.grep", "lgrep_quickfix" },
  lgrep_loclist = { "fzf-lua.providers.grep", "lgrep_loclist" },
  tags = { "fzf-lua.providers.tags", "tags" },
  btags = { "fzf-lua.providers.tags", "btags" },
  tags_grep = { "fzf-lua.providers.tags", "grep" },
  tags_grep_cword = { "fzf-lua.providers.tags", "grep_cword" },
  tags_grep_cWORD = { "fzf-lua.providers.tags", "grep_cWORD" },
  tags_grep_visual = { "fzf-lua.providers.tags", "grep_visual" },
  tags_live_grep = { "fzf-lua.providers.tags", "live_grep" },
  git_files = { "fzf-lua.providers.git", "files" },
  git_status = { "fzf-lua.providers.git", "status" },
  git_diff = { "fzf-lua.providers.git", "diff" },
  git_hunks = { "fzf-lua.providers.git", "hunks" },
  git_stash = { "fzf-lua.providers.git", "stash" },
  git_commits = { "fzf-lua.providers.git", "commits" },
  git_bcommits = { "fzf-lua.providers.git", "bcommits" },
  git_blame = { "fzf-lua.providers.git", "blame" },
  git_branches = { "fzf-lua.providers.git", "branches" },
  git_worktrees = { "fzf-lua.providers.git", "worktrees" },
  git_tags = { "fzf-lua.providers.git", "tags" },
  oldfiles = { "fzf-lua.providers.oldfiles", "oldfiles" },
  undotree = { "fzf-lua.providers.undotree", "undotree" },
  quickfix = { "fzf-lua.providers.quickfix", "quickfix" },
  quickfix_stack = { "fzf-lua.providers.quickfix", "quickfix_stack" },
  loclist = { "fzf-lua.providers.quickfix", "loclist" },
  loclist_stack = { "fzf-lua.providers.quickfix", "loclist_stack" },
  buffers = { "fzf-lua.providers.buffers", "buffers" },
  tabs = { "fzf-lua.providers.buffers", "tabs" },
  lines = { "fzf-lua.providers.buffers", "lines" },
  blines = { "fzf-lua.providers.buffers", "blines" },
  treesitter = { "fzf-lua.providers.buffers", "treesitter" },
  spellcheck = { "fzf-lua.providers.buffers", "spellcheck" },
  helptags = { "fzf-lua.providers.helptags", "helptags" },
  manpages = { "fzf-lua.providers.manpages", "manpages" },
  -- backward compat
  help_tags = { "fzf-lua.providers.helptags", "helptags" },
  man_pages = { "fzf-lua.providers.manpages", "manpages" },
  colorschemes = { "fzf-lua.providers.colorschemes", "colorschemes" },
  highlights = { "fzf-lua.providers.colorschemes", "highlights" },
  awesome_colorschemes = { "fzf-lua.providers.colorschemes", "awesome_colorschemes" },
  jumps = { "fzf-lua.providers.nvim", "jumps" },
  changes = { "fzf-lua.providers.nvim", "changes" },
  tagstack = { "fzf-lua.providers.nvim", "tagstack" },
  marks = { "fzf-lua.providers.nvim", "marks" },
  menus = { "fzf-lua.providers.nvim", "menus" },
  keymaps = { "fzf-lua.providers.nvim", "keymaps" },
  nvim_options = { "fzf-lua.providers.nvim", "nvim_options" },
  autocmds = { "fzf-lua.providers.nvim", "autocmds" },
  registers = { "fzf-lua.providers.nvim", "registers" },
  commands = { "fzf-lua.providers.nvim", "commands" },
  command_history = { "fzf-lua.providers.nvim", "command_history" },
  search_history = { "fzf-lua.providers.nvim", "search_history" },
  serverlist = { "fzf-lua.providers.nvim", "serverlist" },
  spell_suggest = { "fzf-lua.providers.nvim", "spell_suggest" },
  filetypes = { "fzf-lua.providers.nvim", "filetypes" },
  packadd = { "fzf-lua.providers.nvim", "packadd" },
  lsp_finder = { "fzf-lua.providers.lsp", "finder" },
  lsp_typedefs = { "fzf-lua.providers.lsp", "typedefs" },
  lsp_references = { "fzf-lua.providers.lsp", "references" },
  lsp_definitions = { "fzf-lua.providers.lsp", "definitions" },
  lsp_declarations = { "fzf-lua.providers.lsp", "declarations" },
  lsp_implementations = { "fzf-lua.providers.lsp", "implementations" },
  lsp_document_symbols = { "fzf-lua.providers.lsp", "document_symbols" },
  lsp_workspace_symbols = { "fzf-lua.providers.lsp", "workspace_symbols" },
  lsp_live_workspace_symbols = { "fzf-lua.providers.lsp", "live_workspace_symbols" },
  lsp_code_actions = { "fzf-lua.providers.lsp", "code_actions" },
  lsp_incoming_calls = { "fzf-lua.providers.lsp", "incoming_calls" },
  lsp_outgoing_calls = { "fzf-lua.providers.lsp", "outgoing_calls" },
  lsp_type_sub = { "fzf-lua.providers.lsp", "type_sub" },
  lsp_type_super = { "fzf-lua.providers.lsp", "type_super" },
  lsp_document_diagnostics = { "fzf-lua.providers.diagnostic", "diagnostics" },
  lsp_workspace_diagnostics = { "fzf-lua.providers.diagnostic", "all" },
  diagnostics_document = { "fzf-lua.providers.diagnostic", "diagnostics" },
  diagnostics_workspace = { "fzf-lua.providers.diagnostic", "all" },
  dap_commands = { "fzf-lua.providers.dap", "commands" },
  dap_configurations = { "fzf-lua.providers.dap", "configurations" },
  dap_breakpoints = { "fzf-lua.providers.dap", "breakpoints" },
  dap_variables = { "fzf-lua.providers.dap", "variables" },
  dap_frames = { "fzf-lua.providers.dap", "frames" },
  register_ui_select = { "fzf-lua.providers.ui_select", "register" },
  deregister_ui_select = { "fzf-lua.providers.ui_select", "deregister" },
  tmux_buffers = { "fzf-lua.providers.tmux", "buffers" },
  profiles = { "fzf-lua.providers.meta", "profiles" },
  combine = { "fzf-lua.providers.meta", "combine" },
  global = { "fzf-lua.providers.meta", "global" },
  complete_path = { "fzf-lua.complete", "path" },
  complete_file = { "fzf-lua.complete", "file" },
  complete_line = { "fzf-lua.complete", "line" },
  complete_bline = { "fzf-lua.complete", "bline" },
  zoxide = { "fzf-lua.providers.files", "zoxide" },
  -- API shortcuts
  resume = { "fzf-lua.core", "fzf_resume", false },
  fzf_wrap = { "fzf-lua.core", "fzf_wrap", false },
  fzf_exec = { "fzf-lua.core", "fzf_exec", true },
  fzf_live = { "fzf-lua.core", "fzf_live", true },
}

for k, v in pairs(lazyloaded_modules) do
  local v1, v2, v3 = v[1], v[2], v[3] -- avoid reference v (table) in a function
  M[k] = function(...)
    if v3 ~= false then utils.set_info({ cmd = k, mod = v1, fnc = v2 }) end
    return require(v1)[v2](...)
  end
end

M.get_info = utils.get_info

M.set_info = utils.set_info

M.get_last_query = function()
  return utils.get_info().last_query
end

M.setup_fzfvim_cmds = function(...)
  return require("fzf-lua.profiles.fzf-vim").fn_load(...)
end

function M.hide()
  return FzfLua.win.hide()
end

function M.unhide()
  return FzfLua.win.unhide()
end

-- export the defaults module and deref
M.defaults = require("fzf-lua.defaults").defaults

-- exported modules
local exported_modules = {
  "win",
  "core",
  "path",
  "utils",
  "libuv",
  "shell",
  "config",
  "actions",
  "make_entry",
}

-- excluded from builtin / auto-complete
---@private
M._excluded_meta = {
  "setup",
  "redraw",
  "fzf",
  "fzf_raw",
  "fzf_wrap",
  "fzf_exec",
  "fzf_live",
  "defaults",
  "_excluded_meta",
  "_excluded_metamap",
  "_exported_wapi",
  "get_info",
  "set_info",
  "get_last_query",
  "hide",
  "unhide",
  -- Exclude due to rename:
  --   help_tags -> helptags
  --   man_pages -> manpages
  "help_tags",
  "man_pages",
  "register_extension",
}

for _, m in ipairs(exported_modules) do
  M[m] = require("fzf-lua." .. m)
end

M._excluded_metamap = {}
for _, t in pairs({ M._excluded_meta, exported_modules }) do
  for _, m in ipairs(t) do
    M._excluded_metamap[m] = true
  end
end

M._exported_wapi = {
  toggle_preview_wrap = true,
  toggle_preview_ts_ctx = true,
  toggle_preview_undo_diff = true,
  preview_ts_ctx_inc_dec = true,
  preview_scroll = true,
  focus_preview = true,
  hide = true,
  unhide = true,
  toggle_help = true,
  toggle_fullscreen = true,
  toggle_preview = true,
  toggle_preview_cw = true,
  toggle_preview_behavior = true,
  win_leave = true,
  close_help = true,
  set_autoclose = true,
  autoclose = true,
}

---@param opts? fzf-lua.config.Builtin|{}
---@return thread?, string?, table?
M.builtin = function(opts)
  opts = config.normalize_opts(opts, "builtin")
  if not opts then return end
  opts.metatable = M
  opts.metatable_exclude = M._excluded_metamap
  return require "fzf-lua.providers.meta".metatable(opts)
end

M.register_extension = function(name, fun, default_opts, override)
  if not override and M[name] then
    utils.warn("Extension '%s' already exists, set 3rd arg to 'true' to override", name)
    return
  end
  M.defaults[name] = utils.deepcopy(default_opts)
  M[name] = function(...)
    utils.set_info({ cmd = name, fnc = name })
    return fun(...)
  end
end

if not gen then return M end
local buf = {}
local w = function(s) buf[#buf + 1] = s end
local mark = vim.pesc("---GENERATED from `make gen`")
for line in io.lines("lua/fzf-lua/types.lua") do
  w(line .. "\n")
  if line:match(mark) then
    break
  end
end
-- generate api typings
w("\n")
for _, v in vim.spairs(exported_modules) do
  w(([[FzfLua.%s = require("fzf-lua.%s")]] .. "\n"):format(v, v))
end
w("\n")
for k, v in vim.spairs(lazyloaded_modules) do
  w(([[FzfLua.%s = require(%q).%s]] .. "\n"):format(k, v[1], v[2]))
end
w("\n")

local obj = vim.system({ "sh", "-c", [[
  emmylua_doc_cli lua/fzf-lua/ --output-format json --output stdout | jq '.types[] | select(.name == "fzf-lua.Win")'
]] }):wait()
local res = vim.json.decode(obj.stdout or "")

w("---@class fzf-lua.win.api: fzf-lua.Win\n")
vim.iter(res.members):each(function(m)
  if not M._exported_wapi[m.name] then
    return
  end
  -- vim.print(m)
  local ty = {}
  ty[#ty + 1] = "---@field "
  ty[#ty + 1] = m.name
  ty[#ty + 1] = " "
  if m.is_async then ty[#ty + 1] = "async" end
  ty[#ty + 1] = "fun("

  local first = true
  vim.iter(m.params):each(function(p)
    if first then
      first = false
    else
      ty[#ty + 1] = ", "
    end
    ty[#ty + 1] = ("%s: %s"):format(p.name, p.typ)
  end)
  if ty[#ty + 1] == ", " then ty[#ty] = "" end

  ty[#ty + 1] = ")"
  vim.iter(m.returns):each(function(r)
    if first then
      first = false
      ty[#ty + 1] = ": "
    else
      ty[#ty + 1] = ", "
    end
    ty[#ty + 1] = r.typ
  end)
  ty[#ty + 1] = "\n"
  w(table.concat(ty, ""))
end)
assert(io.open("lua/fzf-lua/types.lua", "w")):write(table.concat(buf, ""))
