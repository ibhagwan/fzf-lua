if not pcall(require, "fzf") then
  return
end

local utils = require "fzf-lua.utils"
local config = require "fzf-lua.config"

do
  -- workaround nvim-fzf calls this from 'nvim_fzfvim' which doesn't
  -- get called properly on the latest nightly?
  -- NVIM v0.6.0-dev+569-g2ecf0a4c6
  local path = require "fzf-lua.path"
  local currFile = debug.getinfo(1, 'S').source:gsub("^@", "")
  vim.g.fzf_lua_directory = path.parent(currFile)

  if not vim.g.nvim_fzf_directory then
    local nvim_fzf_directory = path.join({
      path.parent(path.parent(path.parent(path.parent(currFile)))),
      "nvim-fzf"
    })
    if vim.loop.fs_stat(nvim_fzf_directory) then
      vim.g.nvim_fzf_directory = nvim_fzf_directory
    end
    utils.info(("vim.g.nvim_fzf_directory = '%s'"):format(nvim_fzf_directory))
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
  if opts.keymap and opts.keymap.fzf then
    globals.keymap.fzf = opts.keymap.fzf
  end
  if opts.keymap and opts.keymap.builtin then
    globals.keymap.builtin = opts.keymap.builtin
  end
  -- deprecated options
  if globals.previewers.builtin.keymap then
    utils.warn("'previewers.builtin.keymap' moved under 'keymap.builtin', see ':help fzf-lua-customization'")
  end
  if globals.previewers.builtin.wrap ~= nil then
    utils.warn("'previewers.builtin.wrap' is not longer in use, set 'winopts.preview.wrap' to 'wrap' or 'nowrap' instead")
  end
  if globals.previewers.builtin.hidden ~= nil then
    utils.warn("'previewers.builtin.hidden' is not longer in use, set 'winopts.preview.hidden' to 'hidden' or 'nohidden' instead")
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

M.files = require'fzf-lua.providers.files'.files
M.files_resume = require'fzf-lua.providers.files'.files_resume
M.args = require'fzf-lua.providers.files'.args
M.grep = require'fzf-lua.providers.grep'.grep
M.live_grep = require'fzf-lua.providers.grep'.live_grep
M.live_grep_native = require'fzf-lua.providers.grep'.live_grep_native
M.live_grep_resume = require'fzf-lua.providers.grep'.live_grep_resume
M.live_grep_glob = require'fzf-lua.providers.grep'.live_grep_glob
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


-- exported modules
local _modules = {
  'win',
  'core',
  'path',
  'utils',
  'libuv',
  'config',
  'actions',
}

for _, m in ipairs(_modules) do
  M[m] = require("fzf-lua." .. m)
end

-- API shortcuts
M.fzf = require'fzf-lua.core'.fzf
M.raw_fzf = require'fzf-lua.fzf'.raw_fzf

M.builtin = function(opts)
  if not opts then opts = {} end
  opts.metatable = M
  opts.metatable_exclude = {
    ["setup"]   = false,
    ["fzf"]     = false,
    ["raw_fzf"] = false,
  }
  for _, m in ipairs(_modules) do
    opts.metatable_exclude[m] = false
  end
  return require'fzf-lua.providers.module'.metatable(opts)
end

return M
