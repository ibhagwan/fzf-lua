local path = require "fzf-lua.path"
local utils = require "fzf-lua.utils"
local config = require "fzf-lua.config"

do
  -- using the latest nightly 'NVIM v0.6.0-dev+569-g2ecf0a4c6'
  -- plugin '.vim' initialization sometimes doesn't get called
  local currFile = debug.getinfo(1, "S").source:gsub("^@", "")
  vim.g.fzf_lua_directory = path.parent(currFile)
  if utils.__IS_WINDOWS then vim.g.fzf_lua_directory = vim.fs.normalize(vim.g.fzf_lua_directory) end

  -- Manually source the vimL script containing ':FzfLua' cmd
  if not vim.g.loaded_fzf_lua then
    local fzf_lua_vim = path.join({
      path.parent(path.parent(vim.g.fzf_lua_directory)),
      "plugin", "fzf-lua.vim"
    })
    if vim.loop.fs_stat(fzf_lua_vim) then
      vim.cmd(("source %s"):format(fzf_lua_vim))
      -- utils.info(("manually loaded '%s'"):format(fzf_lua_vim))
    end
  end

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
  -- we use `default = true` so calling this function doesn't override the colorscheme
  local default = not override
  local highlights = {
    { "FzfLuaNormal",            "normal",         { default = default, link = "Normal" } },
    { "FzfLuaBorder",            "border",         { default = default, link = "Normal" } },
    { "FzfLuaTitle",             "title",          { default = default, link = "FzfLuaNormal" } },
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
    -- Fzf terminal hls, colors from `vim.api.nvim_get_color_map()`
    { "FzfLuaHeaderBind",        "header_bind",    { default = default, fg = "BlanchedAlmond" } },
    { "FzfLuaHeaderText",        "header_text",    { default = default, fg = "Brown1" } },
    -- Provider specific highlights
    { "FzfLuaBufName",           "buf_name",       { default = default, fg = "LightMagenta" } },
    { "FzfLuaBufNr",             "buf_nr",         { default = default, fg = "BlanchedAlmond" } },
    { "FzfLuaBufLineNr",         "buf_linenr",     { default = default, fg = "MediumSpringGreen" } },
    { "FzfLuaBufFlagCur",        "buf_flag_cur",   { default = default, fg = "Brown1" } },
    { "FzfLuaBufFlagAlt",        "buf_flag_alt",   { default = default, fg = "CadetBlue1" } },
    { "FzfLuaTabTitle",          "tab_title",      { default = default, fg = "LightSkyBlue1", bold = true } },
    { "FzfLuaTabMarker",         "tab_marker",     { default = default, fg = "BlanchedAlmond", bold = true } },
    { "FzfLuaDirIcon",           "dir_icon",       { default = default, link = "Directory" } },
  }
  for _, a in ipairs(highlights) do
    local hl_name, _, hl_def = a[1], a[2], a[3]
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

function M.load_profile(profile)
  local fname = path.join({ vim.g.fzf_lua_directory, "profiles", profile .. ".lua" })
  return utils.load_profile(fname, nil, true)
end

function M.setup(opts, do_not_reset_defaults)
  opts = type(opts) == "table" and opts or {}
  if type(opts[1]) == "string" then
    -- Did the user request a specific profile?
    local profile_opts = M.load_profile(opts[1])
    if type(profile_opts) == "table" then
      if type(profile_opts.fn_load) == "function" then
        profile_opts.fn_load()
        profile_opts.fn_load = nil
      end
      opts = vim.tbl_deep_extend("keep", opts, profile_opts)
    end
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
    grep_project = { "fzf-lua.providers.grep", "grep_project" },
    live_grep = { "fzf-lua.providers.grep", "live_grep" },
    live_grep_native = { "fzf-lua.providers.grep", "live_grep_native" },
    live_grep_resume = { "fzf-lua.providers.grep", "live_grep_resume" },
    live_grep_glob = { "fzf-lua.providers.grep", "live_grep_glob" },
    lgrep_curbuf = { "fzf-lua.providers.grep", "lgrep_curbuf" },
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
    help_tags = { "fzf-lua.providers.helptags", "helptags" },
    man_pages = { "fzf-lua.providers.manpages", "manpages" },
    colorschemes = { "fzf-lua.providers.colorschemes", "colorschemes" },
    highlights = { "fzf-lua.providers.colorschemes", "highlights" },
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
    -- API shortcuts
    fzf = { "fzf-lua.core", "fzf" },
    fzf_raw = { "fzf-lua.fzf", "raw_fzf" },
    fzf_wrap = { "fzf-lua.core", "fzf_wrap" },
    fzf_exec = { "fzf-lua.core", "fzf_exec" },
    fzf_live = { "fzf-lua.core", "fzf_live" },
    fzf_complete = { "fzf-lua.complete", "fzf_complete" },
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

-- export the defaults module and deref
M.defaults = require("fzf-lua.defaults").defaults

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
  "load_profile",
  "setup",
  "fzf",
  "fzf_raw",
  "fzf_wrap",
  "fzf_exec",
  "fzf_live",
  "fzf_complete",
  "defaults",
  "_excluded_meta",
  "_excluded_metamap",
  "_exported_modules",
  "__INFO",
  "get_info",
  "set_info",
  "get_last_query",
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
