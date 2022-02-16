local utils = require "fzf-lua.utils"
local config = require "fzf-lua.config"

do
  -- using the latest nightly 'NVIM v0.6.0-dev+569-g2ecf0a4c6'
  -- pluging '.vim' initialization sometimes doesn't get called
  local path = require "fzf-lua.path"
  local currFile = debug.getinfo(1, 'S').source:gsub("^@", "")
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
  -- fixed $NVIM_LISTEN_ADDRESS different neovim instances will use the same path
  -- as their address and messages won't be recieved on older instances
  if not vim.g.fzf_lua_server then
    vim.g.fzf_lua_server = vim.fn.serverstart()
  end

end

local M = {}

function M.setup(opts)
  local globals = vim.tbl_deep_extend("keep", opts, config.globals)
  -- backward compatibility before winopts was it's own struct
  for k, _ in pairs(globals.winopts) do
    if opts[k] ~= nil then globals.winopts[k] = opts[k] end
  end
  -- backward compatibility for 'fzf_binds'
  if opts.fzf_binds then
    utils.warn("'fzf_binds' is deprecated, moved under 'keymap.fzf', see ':help fzf-lua-customization'")
    globals.keymap.fzf = opts.fzf_binds
  end
  -- do not merge, override the bind tables
  for t, v in pairs({
    ['keymap']  = { 'fzf',   'builtin' },
    ['actions'] = { 'files', 'buffers' },
  }) do
    for _, k in ipairs(v) do
      if opts[t] and opts[t][k] then
        globals[t][k] = opts[t][k]
      end
    end
  end
  -- override BAT_CONFIG_PATH to prevent a
  -- conflct with '$XDG_DATA_HOME/bat/config'
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
  globals = nil
end

M.resume = require'fzf-lua.core'.fzf_resume

M.files = require'fzf-lua.providers.files'.files
M.args = require'fzf-lua.providers.files'.args
M.grep = require'fzf-lua.providers.grep'.grep
M.live_grep = require'fzf-lua.providers.grep'.live_grep_mt
M.live_grep_old = require'fzf-lua.providers.grep'.live_grep_st
M.live_grep_native = require'fzf-lua.providers.grep'.live_grep_native
M.live_grep_resume = require'fzf-lua.providers.grep'.live_grep_resume
M.live_grep_glob = require'fzf-lua.providers.grep'.live_grep_glob_mt
M.live_grep_glob_old = require'fzf-lua.providers.grep'.live_grep_glob
M.grep_last = require'fzf-lua.providers.grep'.grep_last
M.grep_cword = require'fzf-lua.providers.grep'.grep_cword
M.grep_cWORD = require'fzf-lua.providers.grep'.grep_cWORD
M.grep_visual = require'fzf-lua.providers.grep'.grep_visual
M.grep_curbuf = require'fzf-lua.providers.grep'.grep_curbuf
M.lgrep_curbuf = require'fzf-lua.providers.grep'.lgrep_curbuf
M.grep_project = require'fzf-lua.providers.grep'.grep_project
M.git_files = require'fzf-lua.providers.git'.files
M.git_status = require'fzf-lua.providers.git'.status
M.git_commits = require'fzf-lua.providers.git'.commits
M.git_bcommits = require'fzf-lua.providers.git'.bcommits
M.git_branches = require'fzf-lua.providers.git'.branches
M.oldfiles = require'fzf-lua.providers.oldfiles'.oldfiles
M.quickfix = require'fzf-lua.providers.quickfix'.quickfix
M.loclist = require'fzf-lua.providers.quickfix'.loclist
M.buffers = require'fzf-lua.providers.buffers'.buffers
M.tabs = require'fzf-lua.providers.buffers'.tabs
M.lines = require'fzf-lua.providers.buffers'.lines
M.blines = require'fzf-lua.providers.buffers'.blines
M.help_tags = require'fzf-lua.providers.helptags'.helptags
M.man_pages = require'fzf-lua.providers.manpages'.manpages
M.colorschemes = require'fzf-lua.providers.colorschemes'.colorschemes

M.tags = require'fzf-lua.providers.tags'.tags
M.btags = require'fzf-lua.providers.tags'.btags
M.jumps = require'fzf-lua.providers.nvim'.jumps
M.changes = require'fzf-lua.providers.nvim'.changes
M.tagstack = require'fzf-lua.providers.nvim'.tagstack
M.marks = require'fzf-lua.providers.nvim'.marks
M.keymaps = require'fzf-lua.providers.nvim'.keymaps
M.registers = require'fzf-lua.providers.nvim'.registers
M.commands = require'fzf-lua.providers.nvim'.commands
M.command_history = require'fzf-lua.providers.nvim'.command_history
M.search_history = require'fzf-lua.providers.nvim'.search_history
M.spell_suggest = require'fzf-lua.providers.nvim'.spell_suggest
M.filetypes = require'fzf-lua.providers.nvim'.filetypes
M.packadd = require'fzf-lua.providers.nvim'.packadd

M.lsp_typedefs = require'fzf-lua.providers.lsp'.typedefs
M.lsp_references = require'fzf-lua.providers.lsp'.references
M.lsp_definitions = require'fzf-lua.providers.lsp'.definitions
M.lsp_declarations = require'fzf-lua.providers.lsp'.declarations
M.lsp_implementations = require'fzf-lua.providers.lsp'.implementations
M.lsp_document_symbols = require'fzf-lua.providers.lsp'.document_symbols
M.lsp_workspace_symbols = require'fzf-lua.providers.lsp'.workspace_symbols
M.lsp_live_workspace_symbols = require'fzf-lua.providers.lsp'.live_workspace_symbols
M.lsp_code_actions = require'fzf-lua.providers.lsp'.code_actions
M.lsp_document_diagnostics = require'fzf-lua.providers.lsp'.diagnostics
M.lsp_workspace_diagnostics = require'fzf-lua.providers.lsp'.workspace_diagnostics

M.register_ui_select = require'fzf-lua.providers.ui_select'.register
M.deregister_ui_select = require'fzf-lua.providers.ui_select'.deregister

M.dap_commands = require'fzf-lua.providers.dap'.commands
M.dap_configurations = require'fzf-lua.providers.dap'.configurations
M.dap_breakpoints = require'fzf-lua.providers.dap'.breakpoints
M.dap_variables = require'fzf-lua.providers.dap'.variables
M.dap_frames = require'fzf-lua.providers.dap'.frames

-- API shortcuts
M.fzf = require'fzf-lua.core'.fzf
M.fzf_wrap = require'fzf-lua.core'.fzf_wrap
M.raw_fzf = require'fzf-lua.fzf'.raw_fzf

-- exported modules
M._exported_modules = {
  'win',
  'core',
  'path',
  'utils',
  'libuv',
  'shell',
  'config',
  'actions',
}

-- excluded from builtin / auto-complete
M._excluded_meta = {
  'setup',
  'fzf',
  'fzf_wrap',
  'raw_fzf',
  '_excluded_meta',
  '_excluded_metamap',
  '_exported_modules',
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
  return require'fzf-lua.providers.module'.metatable(opts)
end

return M
