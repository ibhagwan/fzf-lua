if not pcall(require, "fzf") then
  return
end

local fzf = require "fzf"
local config = require "fzf-lua.config"


local M = {}

function M.setup(opts)
  local globals = vim.tbl_deep_extend("keep", opts, config.globals)
  -- backward compatibility before winopts was it's own struct
  for k, _ in pairs(globals.winopts) do
    if opts[k] ~= nil then globals.winopts[k] = opts[k] end
  end
  -- empty BAT_CONFIG_PATH so we don't conflict
  -- with '$XDG_DATA_HOME/bat/config'
  vim.env.BAT_CONFIG_PATH = ''
  -- override the bat preview theme if set by caller
  if globals.bat_theme and #globals.bat_theme > 0 then
    vim.env.BAT_THEME = globals.bat_theme
  end
  -- reset default window opts if set by user
  fzf.default_window_options = config.winopts()
  -- set the fzf binary if set by the user
  if globals.fzf_bin ~= nil then
    if fzf.default_options ~= nil and
      vim.fn.executable(globals.fzf_bin) == 1 then
      fzf.default_options.fzf_binary = globals.fzf_bin
    else
      globals.fzf_bin = nil
    end
  end
  -- reset our globals based on user opts
  -- this doesn't happen automatically
  config.globals = globals
  globals = nil
  -- _G.dump(config.globals)
end

-- we usually send winopts with every fzf.fzf call
-- but set default window options just in case
fzf.default_window_options = config.winopts()

M.fzf_files = require'fzf-lua.core'.fzf_files
M.files = require'fzf-lua.providers.files'.files
M.grep = require'fzf-lua.providers.grep'.grep
M.live_grep = require'fzf-lua.providers.grep'.live_grep
M.grep_last = require'fzf-lua.providers.grep'.grep_last
M.grep_cword = require'fzf-lua.providers.grep'.grep_cword
M.grep_cWORD = require'fzf-lua.providers.grep'.grep_cWORD
M.grep_visual = require'fzf-lua.providers.grep'.grep_visual
M.grep_curbuf = require'fzf-lua.providers.grep'.grep_curbuf
M.git_files = require'fzf-lua.providers.files'.git_files
M.oldfiles = require'fzf-lua.providers.oldfiles'.oldfiles
M.quickfix = require'fzf-lua.providers.quickfix'.quickfix
M.loclist = require'fzf-lua.providers.quickfix'.loclist
M.buffers = require'fzf-lua.providers.buffers'.buffers
M.help_tags = require'fzf-lua.providers.helptags'.helptags
M.man_pages = require'fzf-lua.providers.manpages'.manpages
M.colorschemes = require'fzf-lua.providers.colorschemes'.colorschemes

M.lsp_typedefs = require'fzf-lua.providers.lsp'.typedefs
M.lsp_references = require'fzf-lua.providers.lsp'.references
M.lsp_definitions = require'fzf-lua.providers.lsp'.definitions
M.lsp_declarations = require'fzf-lua.providers.lsp'.declarations
M.lsp_implementations = require'fzf-lua.providers.lsp'.implementations
M.lsp_document_symbols = require'fzf-lua.providers.lsp'.document_symbols
M.lsp_workspace_symbols = require'fzf-lua.providers.lsp'.workspace_symbols
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
