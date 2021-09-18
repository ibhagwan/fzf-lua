if not pcall(require, "fzf") then
  return
end

local fzf = require "fzf"
local utils = require "fzf-lua.utils"
local config = require "fzf-lua.config"


local M = {}

function M.setup(opts)
  local globals = vim.tbl_deep_extend("keep", opts, config.globals)
  -- backward compatibility before winopts was it's own struct
  for k, _ in pairs(globals.winopts) do
    if opts[k] ~= nil then globals.winopts[k] = opts[k] end
  end
  -- deprecate message for window_on_create
  if globals.winopts.window_on_create then
    utils.warn(
      "setting highlights using 'window_on_create' is " ..
      "deprecated, use 'winopts.hl_xxx' instead.")
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
  -- reset our globals based on user opts
  -- this doesn't happen automatically
  config.globals = globals
  globals = nil
end

M.fzf_files = require'fzf-lua.core'.fzf_files
M.files = require'fzf-lua.providers.files'.files
M.files_resume = require'fzf-lua.providers.files'.files_resume
M.grep = require'fzf-lua.providers.grep'.grep
M.live_grep = require'fzf-lua.providers.grep'.live_grep_resume
M.live_grep_native = require'fzf-lua.providers.grep'.live_grep_native
M.live_grep_resume = require'fzf-lua.providers.grep'.live_grep_resume
M.grep_last = require'fzf-lua.providers.grep'.grep_last
M.grep_cword = require'fzf-lua.providers.grep'.grep_cword
M.grep_cWORD = require'fzf-lua.providers.grep'.grep_cWORD
M.grep_visual = require'fzf-lua.providers.grep'.grep_visual
M.grep_curbuf = require'fzf-lua.providers.grep'.grep_curbuf
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

M.builtin = function(opts)
  if not opts then opts = {} end
  opts.metatable = M
  opts.metatable_exclude = { ["setup"] = false, ["fzf_files"] = false }
  return require'fzf-lua.providers.module'.metatable(opts)
end

return M
