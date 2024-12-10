-- make value truthy so we can load the path module and subsequently
-- the libuv module without overriding the global require used only
-- for spawn_stdio headless instances, this way we can call
-- require("fzf-lua") from test specs (which also run headless)
vim.g.fzf_lua_directory = ""

local uv = vim.uv or vim.loop
local path = require "fzf-lua.path"
local utils = require "fzf-lua.utils"
local config = require "fzf-lua.config"

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

  -- Manually source the vimL script containing ':FzfLua' cmd
  -- does nothing if already loaded due to `vim.g.loaded_fzf_lua`
  source_vimL({ vim.g.fzf_lua_root, "plugin", "fzf-lua.vim" })
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
    vim.g.fzf_lua_server = vim.fn.serverstart("fzf-lua." .. os.time())
  end
end

local M = {}

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
    { "FzfLuaFilePart", "file_part",
      {
        default = default,
        link = utils.__HAS_NVIM_08 and "@none" or "Normal",
      }
    },
    -- Fzf terminal hls, colors from `vim.api.nvim_get_color_map()`
    { "FzfLuaHeaderBind", "header_bind",
      { default = default, fg = is_light and "MediumSpringGreen" or "BlanchedAlmond" } },
    { "FzfLuaHeaderText", "header_text",
      { default = default, fg = is_light and "Brown4" or "Brown1" } },
    { "FzfLuaPathColNr", "path_colnr",   -- qf|diag|lsp
      { default = default, fg = is_light and "CadetBlue4" or "CadetBlue1" } },
    { "FzfLuaPathLineNr", "path_linenr", -- qf|diag|lsp
      { default = default, fg = is_light and "MediumSpringGreen" or "LightGreen" } },
    { "FzfLuaLiveSym", "live_sym",       -- lsp_live_workspace_symbols query
      { default = default, fg = is_light and "Brown4" or "Brown1" } },
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
    if utils.__HAS_NVIM_07 then
      vim.api.nvim_set_hl(0, hl_name, hl_def)
    else
      if hl_def.link then
        vim.cmd(string.format("hi! %s link %s %s",
          hl_def.default and "default" or "",
          hl_name, hl_def.link))
      else
        vim.cmd(string.format("hi! %s %s %s%s%s",
          hl_def.default and "default" or "", hl_name,
          hl_def.fg and string.format(" guifg=%s", hl_def.fg) or "",
          hl_def.bg and string.format(" guibg=%s", hl_def.bg) or "",
          hl_def.bold and " gui=bold" or ""))
      end
    end
  end

  -- linking to a cleared hl is bugged in neovim 0.8.x
  -- resulting in a pink background for hls linked to `Normal`
  if vim.fn.has("nvim-0.9") == 0 and vim.fn.has("nvim-0.8") == 1 then
    for _, a in ipairs(highlights) do
      local hl_name, opt_name = a[1], a[2]
      if utils.is_hl_cleared(hl_name) then
        -- reset any invalid hl, this will cause our 'winhighlight'
        -- string to look something akin to `Normal:,FloatBorder:`
        -- which uses terminal fg|bg colors instead
        utils.map_set(config.setup_opts, "__HLS." .. opt_name, "")
      end
    end
  end

  -- Init the colormap singleton
  utils.COLORMAP()
end

-- Setup highlights at least once on load in
-- case the user decides not to call `setup()`
M.setup_highlights()

local function load_profiles(profiles)
  local ret = {}
  profiles = type(profiles) == "table" and profiles
      or type(profiles) == "string" and { profiles }
      or {}
  for _, profile in ipairs(profiles) do
    local fname = path.join({ vim.g.fzf_lua_directory, "profiles", profile .. ".lua" })
    local profile_opts = utils.load_profile_fname(fname, nil, true)
    if type(profile_opts) == "table" then
      if profile_opts[1] then
        -- profile requires loading base profile(s)
        profile_opts = vim.tbl_deep_extend("keep",
          profile_opts, load_profiles(profile_opts[1]))
      end
      if type(profile_opts.fn_load) == "function" then
        profile_opts.fn_load()
        profile_opts.fn_load = nil
      end
      ret = vim.tbl_deep_extend("force", ret, profile_opts)
    end
  end
  return ret
end

function M.setup(opts, do_not_reset_defaults)
  opts = type(opts) == "table" and opts or {}
  if opts[1] then
    -- Did the user supply profile(s) to load?
    opts = vim.tbl_deep_extend("keep", opts, load_profiles(opts[1]))
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
    end
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

do
  -- lazy load modules, run inside a local 'do' scope
  -- so 'lazyloaded_modules' is not stored in mem
  local lazyloaded_modules = {
    resume = { "fzf-lua.core", "fzf_resume" },
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
    git_stash = { "fzf-lua.providers.git", "stash" },
    git_commits = { "fzf-lua.providers.git", "commits" },
    git_bcommits = { "fzf-lua.providers.git", "bcommits" },
    git_blame = { "fzf-lua.providers.git", "blame" },
    git_branches = { "fzf-lua.providers.git", "branches" },
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
    profiles = { "fzf-lua.providers.module", "profiles" },
    complete_path = { "fzf-lua.complete", "path" },
    complete_file = { "fzf-lua.complete", "file" },
    complete_line = { "fzf-lua.complete", "line" },
    complete_bline = { "fzf-lua.complete", "bline" },
  }

  for k, v in pairs(lazyloaded_modules) do
    M[k] = function(...)
      -- override self so this function is only called once
      -- we use an additional wrapper in order to save the
      -- current provider info: {cmd-name|module|function}
      M[k] = function(...)
        M.set_info {
          cmd = k,
          mod = v[1],
          fnc = v[2],
        }
        return require(v[1])[v[2]](...)
      end
      return M[k](...)
    end
  end
end

M.get_info = function(filter)
  if filter and filter.winobj and type(M.__INFO) == "table" then
    M.__INFO.winobj = utils.fzf_winobj()
  end
  return M.__INFO
end

M.set_info = function(x)
  M.__INFO = x
end

M.get_last_query = function()
  return M.config.__resume_data and M.config.__resume_data.last_query
end

M.setup_fzfvim_cmds = function(...)
  local fn = loadstring("return require'fzf-lua.profiles.fzf-vim'.fn_load")()
  return fn(...)
end

function M.hide()
  return loadstring("return require'fzf-lua'.win.hide()")()
end

function M.unhide()
  return loadstring("return require'fzf-lua'.win.unhide()")()
end

-- export the defaults module and deref
M.defaults = require("fzf-lua.defaults").defaults

-- API shortcuts
M.fzf_exec = require("fzf-lua.core").fzf_exec
M.fzf_live = require("fzf-lua.core").fzf_live
M.fzf_wrap = require("fzf-lua.core").fzf_wrap
-- M.fzf_raw = require( "fzf-lua.fzf").raw_fzf

-- exported modules
M._exported_modules = {
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
  "_exported_modules",
  "__INFO",
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
}

for _, m in ipairs(M._exported_modules) do
  M[m] = require("fzf-lua." .. m)
end

M._excluded_metamap = {}
for _, t in pairs({ M._excluded_meta, M._exported_modules }) do
  for _, m in ipairs(t) do
    M._excluded_metamap[m] = true
  end
end

M.builtin = function(opts)
  opts = config.normalize_opts(opts, "builtin")
  if not opts then return end
  opts.metatable = M
  opts.metatable_exclude = M._excluded_metamap
  return require "fzf-lua.providers.module".metatable(opts)
end

return M
