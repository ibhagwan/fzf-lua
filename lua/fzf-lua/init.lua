local uv = vim.uv or vim.loop
local path = require "fzf-lua.path"
local utils = require "fzf-lua.utils"
local config = require "fzf-lua.config"

local M = {}

do
  local function source_vimL(path_parts)
    local vimL_file = path.join(path_parts)
    if uv.fs_stat(vimL_file) then
      vim.cmd("source " .. vimL_file)
      -- print(string.format("loaded '%s'", vimL_file))
    end
  end

  local currFile = debug.getinfo(1, "S").source:gsub("^@", "")
  vim.g.fzf_lua_directory = path.normalize(path.parent(currFile))
  vim.g.fzf_lua_root = path.parent(path.parent(vim.g.fzf_lua_directory))

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
      if win and win:hidden() then
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
  if opts.nbsp then utils.nbsp = opts.nbsp end
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
  return M.win.hide()
end

function M.unhide()
  return M.win.unhide()
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

M.builtin = function(opts)
  ---@type fzf-lua.config.Builtin
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

-- generate api typings
-- for _, v in vim.spairs(exported_modules) do print(([[M.%s = require("fzf-lua.%s")]]):format(v, v)) end
-- for k, v in vim.spairs(lazyloaded_modules) do print(([[M.%s = require(%q).%s]]):format(k, v[1], v[2])) end
lazyloaded_modules = nil
exported_modules = nil
do return M end
---@format disable
M.win = require("fzf-lua.win")
M.core = require("fzf-lua.core")
M.path = require("fzf-lua.path")
M.utils = require("fzf-lua.utils")
M.libuv = require("fzf-lua.libuv")
M.shell = require("fzf-lua.shell")
M.config = require("fzf-lua.config")
M.actions = require("fzf-lua.actions")
M.make_entry = require("fzf-lua.make_entry")
M.args = require("fzf-lua.providers.files").args ---@type fun(opts: fzf-lua.config.Args.p?): thread?, string?, table?
M.autocmds = require("fzf-lua.providers.nvim").autocmds ---@type fun(opts: fzf-lua.config.Autocmds.p?): thread?, string?, table?
M.awesome_colorschemes = require("fzf-lua.providers.colorschemes").awesome_colorschemes ---@type fun(opts: fzf-lua.config.AwesomeColorschemes.p?): thread?, string?, table?
M.blines = require("fzf-lua.providers.buffers").blines ---@type fun(opts: fzf-lua.config.Blines.p?): thread?, string?, table?
M.btags = require("fzf-lua.providers.tags").btags ---@type fun(opts: fzf-lua.config.Btags.p?): thread?, string?, table?
M.buffers = require("fzf-lua.providers.buffers").buffers ---@type fun(opts: fzf-lua.config.Buffers.p?): thread?, string?, table?
M.changes = require("fzf-lua.providers.nvim").changes ---@type fun(opts: fzf-lua.config.Changes.p?): thread?, string?, table?
M.colorschemes = require("fzf-lua.providers.colorschemes").colorschemes ---@type fun(opts: fzf-lua.config.Colorschemes.p?): thread?, string?, table?
M.combine = require("fzf-lua.providers.meta").combine
M.command_history = require("fzf-lua.providers.nvim").command_history ---@type fun(opts: fzf-lua.config.CommandHistory.p?): thread?, string?, table?
M.commands = require("fzf-lua.providers.nvim").commands ---@type fun(opts: fzf-lua.config.Commands.p?): thread?, string?, table?
M.complete_bline = require("fzf-lua.complete").bline ---@type fun(opts: fzf-lua.config.CompleteBline.p?): thread?, string?, table?
M.complete_file = require("fzf-lua.complete").file ---@type fun(opts: fzf-lua.config.CompleteFile.p?): thread?, string?, table?
M.complete_line = require("fzf-lua.complete").line ---@type fun(opts: fzf-lua.config.CompleteLine.p?): thread?, string?, table?
M.complete_path = require("fzf-lua.complete").path ---@type fun(opts: fzf-lua.config.CompletePath.p?): thread?, string?, table?
M.dap_breakpoints = require("fzf-lua.providers.dap").breakpoints ---@type fun(opts: fzf-lua.config.DapBreakpoints.p?): thread?, string?, table?
M.dap_commands = require("fzf-lua.providers.dap").commands ---@type fun(opts: fzf-lua.config.DapCommands.p?): thread?, string?, table?
M.dap_configurations = require("fzf-lua.providers.dap").configurations ---@type fun(opts: fzf-lua.config.DapConfigurations.p?): thread?, string?, table?
M.dap_frames = require("fzf-lua.providers.dap").frames ---@type fun(opts: fzf-lua.config.DapFrames.p?): thread?, string?, table?
M.dap_variables = require("fzf-lua.providers.dap").variables ---@type fun(opts: fzf-lua.config.DapVariables.p?): thread?, string?, table?
M.deregister_ui_select = require("fzf-lua.providers.ui_select").deregister
M.diagnostics_document = require("fzf-lua.providers.diagnostic").diagnostics ---@type fun(opts: fzf-lua.config.DiagnosticsDocument.p?): thread?, string?, table?
M.diagnostics_workspace = require("fzf-lua.providers.diagnostic").all ---@type fun(opts: fzf-lua.config.DiagnosticsWorkspace.p?): thread?, string?, table?
M.files = require("fzf-lua.providers.files").files ---@type fun(opts: fzf-lua.config.Files.p?): thread?, string?, table?
M.filetypes = require("fzf-lua.providers.nvim").filetypes ---@type fun(opts: fzf-lua.config.Filetypes.p?): thread?, string?, table?
M.fzf_exec = require("fzf-lua.core").fzf_exec
M.fzf_live = require("fzf-lua.core").fzf_live
M.fzf_wrap = require("fzf-lua.core").fzf_wrap
M.git_bcommits = require("fzf-lua.providers.git").bcommits ---@type fun(opts: fzf-lua.config.GitBcommits.p?): thread?, string?, table?
M.git_blame = require("fzf-lua.providers.git").blame ---@type fun(opts: fzf-lua.config.GitBlame.p?): thread?, string?, table?
M.git_branches = require("fzf-lua.providers.git").branches ---@type fun(opts: fzf-lua.config.GitBranches.p?): thread?, string?, table?
M.git_worktrees = require("fzf-lua.providers.git").worktrees ---@type fun(opts: fzf-lua.config.GitWorktrees.p?): thread?, string?, table?
M.git_commits = require("fzf-lua.providers.git").commits ---@type fun(opts: fzf-lua.config.GitCommits.p?): thread?, string?, table?
M.git_diff = require("fzf-lua.providers.git").diff ---@type fun(opts: fzf-lua.config.GitDiff.p?): thread?, string?, table?
M.git_files = require("fzf-lua.providers.git").files ---@type fun(opts: fzf-lua.config.GitFiles.p?): thread?, string?, table?
M.git_hunks = require("fzf-lua.providers.git").hunks ---@type fun(opts: fzf-lua.config.GitHunks.p?): thread?, string?, table?
M.git_stash = require("fzf-lua.providers.git").stash ---@type fun(opts: fzf-lua.config.GitStash.p?): thread?, string?, table?
M.git_status = require("fzf-lua.providers.git").status ---@type fun(opts: fzf-lua.config.GitStatus.p?): thread?, string?, table?
M.git_tags = require("fzf-lua.providers.git").tags ---@type fun(opts: fzf-lua.config.GitTags.p?): thread?, string?, table?
M.global = require("fzf-lua.providers.meta").global ---@type fun(opts: fzf-lua.config.Global.p?): thread?, string?, table?
M.grep = require("fzf-lua.providers.grep").grep ---@type fun(opts: fzf-lua.config.Grep.p?): thread?, string?, table?
M.grep_cWORD = require("fzf-lua.providers.grep").grep_cWORD ---@type fun(opts: fzf-lua.config.GrepCWORD.p?): thread?, string?, table?
M.grep_curbuf = require("fzf-lua.providers.grep").grep_curbuf ---@type fun(opts: fzf-lua.config.GrepCurbuf.p?): thread?, string?, table?
M.grep_cword = require("fzf-lua.providers.grep").grep_cword ---@type fun(opts: fzf-lua.config.GrepCword.p?): thread?, string?, table?
M.grep_last = require("fzf-lua.providers.grep").grep_last ---@type fun(opts: fzf-lua.config.GrepLast.p?): thread?, string?, table?
M.grep_loclist = require("fzf-lua.providers.grep").grep_loclist ---@type fun(opts: fzf-lua.config.GrepLoclist.p?): thread?, string?, table?
M.grep_project = require("fzf-lua.providers.grep").grep_project ---@type fun(opts: fzf-lua.config.GrepProject.p?): thread?, string?, table?
M.grep_quickfix = require("fzf-lua.providers.grep").grep_quickfix ---@type fun(opts: fzf-lua.config.GrepQuickfix.p?): thread?, string?, table?
M.grep_visual = require("fzf-lua.providers.grep").grep_visual ---@type fun(opts: fzf-lua.config.GrepVisual.p?): thread?, string?, table?
M.help_tags = require("fzf-lua.providers.helptags").helptags ---@type fun(opts: fzf-lua.config.HelpTags.p?): thread?, string?, table?
M.helptags = require("fzf-lua.providers.helptags").helptags ---@type fun(opts: fzf-lua.config.HelpTags.p?): thread?, string?, table?
M.highlights = require("fzf-lua.providers.colorschemes").highlights ---@type fun(opts: fzf-lua.config.Highlights.p?): thread?, string?, table?
M.jumps = require("fzf-lua.providers.nvim").jumps ---@type fun(opts: fzf-lua.config.Jumps.p?): thread?, string?, table?
M.keymaps = require("fzf-lua.providers.nvim").keymaps ---@type fun(opts: fzf-lua.config.Keymaps.p?): thread?, string?, table?
M.lgrep_curbuf = require("fzf-lua.providers.grep").lgrep_curbuf ---@type fun(opts: fzf-lua.config.LgrepCurbuf.p?): thread?, string?, table?
M.lgrep_loclist = require("fzf-lua.providers.grep").lgrep_loclist ---@type fun(opts: fzf-lua.config.LgrepLoclist.p?): thread?, string?, table?
M.lgrep_quickfix = require("fzf-lua.providers.grep").lgrep_quickfix ---@type fun(opts: fzf-lua.config.LgrepQuickfix.p?): thread?, string?, table?
M.lines = require("fzf-lua.providers.buffers").lines ---@type fun(opts: fzf-lua.config.Lines.p?): thread?, string?, table?
M.live_grep = require("fzf-lua.providers.grep").live_grep ---@type fun(opts: fzf-lua.config.LiveGrep.p?): thread?, string?, table?
M.live_grep_glob = require("fzf-lua.providers.grep").live_grep_glob ---@type fun(opts: fzf-lua.config.LiveGrepGlob.p?): thread?, string?, table?
M.live_grep_native = require("fzf-lua.providers.grep").live_grep_native ---@type fun(opts: fzf-lua.config.LiveGrepNative.p?): thread?, string?, table?
M.live_grep_resume = require("fzf-lua.providers.grep").live_grep_resume ---@type fun(opts: fzf-lua.config.LiveGrepResume.p?): thread?, string?, table?
M.loclist = require("fzf-lua.providers.quickfix").loclist ---@type fun(opts: fzf-lua.config.Loclist.p?): thread?, string?, table?
M.loclist_stack = require("fzf-lua.providers.quickfix").loclist_stack ---@type fun(opts: fzf-lua.config.LoclistStack.p?): thread?, string?, table?
M.lsp_code_actions = require("fzf-lua.providers.lsp").code_actions ---@type fun(opts: fzf-lua.config.LspCodeActions.p?): thread?, string?, table?
M.lsp_declarations = require("fzf-lua.providers.lsp").declarations ---@type fun(opts: fzf-lua.config.LspDeclarations.p?): thread?, string?, table?
M.lsp_definitions = require("fzf-lua.providers.lsp").definitions ---@type fun(opts: fzf-lua.config.LspDefinitions.p?): thread?, string?, table?
M.lsp_document_diagnostics = require("fzf-lua.providers.diagnostic").diagnostics ---@type fun(opts: fzf-lua.config.LspDocumentDiagnostics.p?): thread?, string?, table?
M.lsp_document_symbols = require("fzf-lua.providers.lsp").document_symbols ---@type fun(opts: fzf-lua.config.LspDocumentSymbols.p?): thread?, string?, table?
M.lsp_finder = require("fzf-lua.providers.lsp").finder ---@type fun(opts: fzf-lua.config.LspFinder.p?): thread?, string?, table?
M.lsp_implementations = require("fzf-lua.providers.lsp").implementations ---@type fun(opts: fzf-lua.config.LspImplementations.p?): thread?, string?, table?
M.lsp_incoming_calls = require("fzf-lua.providers.lsp").incoming_calls ---@type fun(opts: fzf-lua.config.LspIncomingCalls.p?): thread?, string?, table?
M.lsp_live_workspace_symbols = require("fzf-lua.providers.lsp").live_workspace_symbols ---@type fun(opts: fzf-lua.config.LspLiveWorkspaceSymbols.p?): thread?, string?, table?
M.lsp_outgoing_calls = require("fzf-lua.providers.lsp").outgoing_calls ---@type fun(opts: fzf-lua.config.LspOutgoingCalls.p?): thread?, string?, table?
M.lsp_references = require("fzf-lua.providers.lsp").references ---@type fun(opts: fzf-lua.config.LspReferences.p?): thread?, string?, table?
M.lsp_typedefs = require("fzf-lua.providers.lsp").typedefs ---@type fun(opts: fzf-lua.config.LspTypedefs.p?): thread?, string?, table?
M.lsp_workspace_diagnostics = require("fzf-lua.providers.diagnostic").all ---@type fun(opts: fzf-lua.config.LspWorkspaceDiagnostics.p?): thread?, string?, table?
M.lsp_workspace_symbols = require("fzf-lua.providers.lsp").workspace_symbols ---@type fun(opts: fzf-lua.config.LspWorkspaceSymbols.p?): thread?, string?, table?
M.man_pages = require("fzf-lua.providers.manpages").manpages ---@type fun(opts: fzf-lua.config.ManPages.p?): thread?, string?, table?
M.manpages = require("fzf-lua.providers.manpages").manpages ---@type fun(opts: fzf-lua.config.ManPages.p?): thread?, string?, table?
M.marks = require("fzf-lua.providers.nvim").marks ---@type fun(opts: fzf-lua.config.Marks.p?): thread?, string?, table?
M.menus = require("fzf-lua.providers.nvim").menus ---@type fun(opts: fzf-lua.config.Menus.p?): thread?, string?, table?
M.nvim_options = require("fzf-lua.providers.nvim").nvim_options ---@type fun(opts: fzf-lua.config.NvimOptions.p?): thread?, string?, table?
M.oldfiles = require("fzf-lua.providers.oldfiles").oldfiles ---@type fun(opts: fzf-lua.config.Oldfiles.p?): thread?, string?, table?
M.packadd = require("fzf-lua.providers.nvim").packadd ---@type fun(opts: fzf-lua.config.Packadd.p?): thread?, string?, table?
M.profiles = require("fzf-lua.providers.meta").profiles ---@type fun(opts: fzf-lua.config.Profiles.p?): thread?, string?, table?
M.quickfix = require("fzf-lua.providers.quickfix").quickfix ---@type fun(opts: fzf-lua.config.Quickfix.p?): thread?, string?, table?
M.quickfix_stack = require("fzf-lua.providers.quickfix").quickfix_stack ---@type fun(opts: fzf-lua.config.QuickfixStack.p?): thread?, string?, table?
M.register_ui_select = require("fzf-lua.providers.ui_select").register
M.registers = require("fzf-lua.providers.nvim").registers ---@type fun(opts: fzf-lua.config.Registers.p?): thread?, string?, table?
M.resume = require("fzf-lua.core").fzf_resume
M.search_history = require("fzf-lua.providers.nvim").search_history ---@type fun(opts: fzf-lua.config.SearchHistory.p?): thread?, string?, table?
M.spell_suggest = require("fzf-lua.providers.nvim").spell_suggest ---@type fun(opts: fzf-lua.config.SpellSuggest.p?): thread?, string?, table?
M.spellcheck = require("fzf-lua.providers.buffers").spellcheck ---@type fun(opts: fzf-lua.config.Spellcheck.p?): thread?, string?, table?
M.tabs = require("fzf-lua.providers.buffers").tabs ---@type fun(opts: fzf-lua.config.Tabs.p?): thread?, string?, table?
M.tags = require("fzf-lua.providers.tags").tags ---@type fun(opts: fzf-lua.config.Tags.p?): thread?, string?, table?
M.tags_grep = require("fzf-lua.providers.tags").grep ---@type fun(opts: fzf-lua.config.TagsGrep.p?): thread?, string?, table?
M.tags_grep_cWORD = require("fzf-lua.providers.tags").grep_cWORD ---@type fun(opts: fzf-lua.config.TagsGrepCWORD.p?): thread?, string?, table?
M.tags_grep_cword = require("fzf-lua.providers.tags").grep_cword ---@type fun(opts: fzf-lua.config.TagsGrepCword.p?): thread?, string?, table?
M.tags_grep_visual = require("fzf-lua.providers.tags").grep_visual ---@type fun(opts: fzf-lua.config.TagsGrepVisual.p?): thread?, string?, table?
M.tags_live_grep = require("fzf-lua.providers.tags").live_grep ---@type fun(opts: fzf-lua.config.TagsLiveGrep.p?): thread?, string?, table?
M.tagstack = require("fzf-lua.providers.nvim").tagstack ---@type fun(opts: fzf-lua.config.Tagstack.p?): thread?, string?, table?
M.tmux_buffers = require("fzf-lua.providers.tmux").buffers ---@type fun(opts: fzf-lua.config.TmuxBuffers.p?): thread?, string?, table?
M.treesitter = require("fzf-lua.providers.buffers").treesitter ---@type fun(opts: fzf-lua.config.Treesitter.p?): thread?, string?, table?
M.zoxide = require("fzf-lua.providers.files").zoxide ---@type fun(opts: fzf-lua.config.Zoxide.p?): thread?, string?, table?
