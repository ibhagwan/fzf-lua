local path = require "fzf-lua.path"
local utils = require "fzf-lua.utils"
local config = require "fzf-lua.config"

do
  -- using the latest nightly 'NVIM v0.6.0-dev+569-g2ecf0a4c6'
  -- plugin '.vim' initialization sometimes doesn't get called
  local currFile = debug.getinfo(1, "S").source:gsub("^@", "")
  vim.g.fzf_lua_directory = path.parent(currFile)

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
    vim.g.fzf_lua_server = vim.fn.serverstart()
  end
end

local M = {}

function M.setup_highlights()
  local highlights = {
    FzfLuaNormal            = { "winopts.hl.normal", "Normal" },
    FzfLuaBorder            = { "winopts.hl.border", "Normal" },
    FzfLuaCursor            = { "winopts.hl.cursor", "Cursor" },
    FzfLuaCursorLine        = { "winopts.hl.cursorline", "CursorLine" },
    FzfLuaCursorLineNr      = { "winopts.hl.cursornr", "CursorLineNr" },
    FzfLuaSearch            = { "winopts.hl.search", "IncSearch" },
    FzfLuaTitle             = { "winopts.hl.title", "FzfLuaNormal" },
    FzfLuaScrollBorderEmpty = { "winopts.hl.scrollborder_e", "FzfLuaBorder" },
    FzfLuaScrollBorderFull  = { "winopts.hl.scrollborder_f", "FzfLuaBorder" },
    FzfLuaScrollFloatEmpty  = { "winopts.hl.scrollfloat_e", "PmenuSbar" },
    FzfLuaScrollFloatFull   = { "winopts.hl.scrollfloat_f", "PmenuThumb" },
    FzfLuaHelpNormal        = { "winopts.hl.help_normal", "FzfLuaNormal" },
    FzfLuaHelpBorder        = { "winopts.hl.help_border", "FzfLuaBorder" },
  }
  for hl_name, v in pairs(highlights) do
    -- define a new linked highlight and then override the
    -- default config with the new FzfLuaXXX hl. This leaves
    -- the choice for direct call option overrides (via winopts)
    local hl_link = config.get_global(v[1])
    if not hl_link or vim.fn.hlID(hl_link) == 0 then
      -- revert to default if hl option or link doesn't exist
      hl_link = v[2]
    end
    if vim.fn.has("nvim-0.7") == 1 then
      vim.api.nvim_set_hl(0, hl_name, { default = true, link = hl_link })
    else
      vim.cmd(string.format("hi! link %s %s", hl_name, hl_link))
    end
    -- save new highlight groups under 'winopts.__hl'
    config.set_global(v[1]:gsub("%.hl%.", ".__hl."), hl_name)
  end

  for _, v in pairs(highlights) do
    local opt_path = v[1]:gsub("%.hl%.", ".__hl.")
    local hl = config.get_global(opt_path)
    if utils.is_hl_cleared(hl) then
      -- reset any invalid hl, this will cause our 'winhighlight'
      -- string to look something akin to `Normal:,FloatBorder:`
      -- which uses terminal fg|bg colors instead
      config.set_global(opt_path, "")
    end
  end
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
      opts = vim.tbl_deep_extend("keep", opts, profile_opts)
    end
  end
  -- Reset to defaults and merge with user options
  if not do_not_reset_defaults then
    config.reset_defaults()
  end
  -- Make sure opts is a table or override
  local globals = vim.tbl_deep_extend("keep", opts, config.globals)
  -- backward compatibility before winopts was it's own struct
  for k, _ in pairs(globals.winopts) do
    if opts[k] ~= nil then globals.winopts[k] = opts[k] end
  end
  -- backward compatibility for 'fzf_binds'
  if opts.fzf_binds then
    utils.warn("'fzf_binds' is deprecated, moved under 'keymap.fzf', " ..
      "see ':help fzf-lua-customization'")
    globals.keymap.fzf = opts.fzf_binds
  end
  -- do not merge, override the bind tables
  for t, v in pairs({
    ["keymap"]  = { "fzf", "builtin" },
    ["actions"] = { "files", "buffers" },
  }) do
    for _, k in ipairs(v) do
      if opts[t] and opts[t][k] then
        globals[t][k] = opts[t][k]
      end
    end
  end
  -- override BAT_CONFIG_PATH to prevent a
  -- conflict with '$XDG_DATA_HOME/bat/config'
  local bat_theme = globals.previewers.bat.theme or globals.previewers.bat_native.theme
  local bat_config = globals.previewers.bat.config or globals.previewers.bat_native.config
  if bat_config then
    vim.env.BAT_CONFIG_PATH = vim.fn.expand(bat_config)
  end
  -- override the bat preview theme if set by caller
  if bat_theme and #bat_theme > 0 then
    vim.env.BAT_THEME = bat_theme
  end
  -- set lua_io if caller requested
  utils.set_lua_io(globals.lua_io)
  -- set custom &nbsp if caller requested
  if globals.nbsp then utils.nbsp = globals.nbsp end
  -- reset our globals based on user opts
  -- this doesn't happen automatically
  config.globals = globals
  config.DEFAULTS.globals = globals
  -- setup highlights
  M.setup_highlights()
end

M.defaults = config.globals

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

M.set_last_query = function(query)
  M.config.__resume_data = M.config.__resume_data or {}
  M.config.__resume_data.last_query = query
end

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
  "complete_path",
  "complete_file",
  "complete_line",
  "complete_bline",
  "defaults",
  "_excluded_meta",
  "_excluded_metamap",
  "_exported_modules",
  "__INFO",
  "get_info",
  "set_info",
  "get_last_query",
  "set_last_query",
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
  if not opts then opts = {} end
  opts.metatable = M
  opts.metatable_exclude = M._excluded_metamap
  return require "fzf-lua.providers.module".metatable(opts)
end

return M
