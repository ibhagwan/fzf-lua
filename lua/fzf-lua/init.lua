if not pcall(require, "fzf") then
  return
end

local fzf = require "fzf"
local utils = require "fzf-lua.utils"
local config = require "fzf-lua.config"

local M = {}

local getopt = function(opts, key, expected_type, default)
  if opts and opts[key] ~= nil then
    if expected_type == "any" or type(opts[key]) == expected_type then
        return opts[key]
    else
      utils.info(
        string.format("Expected '%s' for config option '%s', got '%s'",
        expected_type, key, type(opts[key]))
      )
    end
  elseif default ~= nil then
      return default
  else
      return nil
  end
end

local setopt = function(cfg, opts, key, type)
  cfg[tostring(key)] = getopt(opts, key, type, cfg[tostring(key)])
end

local setopts = function(cfg, opts, tbl)
  for k, v in pairs(tbl) do
    setopt(cfg, opts, k, v)
  end
end

local setopt_tbl = function(cfg, opts, key)
  if opts and opts[key] then
    for k, v in pairs(opts[key]) do
      if not cfg[key] then cfg[key] = {} end
      cfg[key][k] = v
    end
  end
end

function M.setup(opts)
  setopts(config, opts, {
    win_height          = "number",
    win_width           = "number",
    win_row             = "number",
    win_col             = "number",
    win_border          = "any",    -- boolean|table (borderchars)
    winopts_raw         = "function",
    default_prompt      = "string",
    fzf_args            = "string",
    fzf_layout          = "string",
    fzf_binds           = "table",
    preview_cmd         = "string",
    preview_border      = "string",
    preview_wrap        = "string",
    preview_opts        = "string",
    preview_vertical    = "string",
    preview_horizontal  = "string",
    preview_layout      = "string",
    flip_columns        = "number",
    window_on_create    = "function",
    bat_theme           = "string",
    bat_opts            = "string",
  })
  setopts(config.files, opts.files, {
    prompt              = "string",
    cmd                 = "string",
    git_icons           = "boolean",
    file_icons          = "boolean",
    color_icons         = "boolean",
    fd_opts             = "string",
    find_opts           = "string",
    git_diff_cmd        = "string",
    git_untracked_cmd   = "string",
  })
  setopts(config.grep, opts.grep, {
    prompt              = "string",
    input_prompt        = "string",
    cmd                 = "string",
    git_icons           = "boolean",
    file_icons          = "boolean",
    color_icons         = "boolean",
    rg_opts             = "string",
    grep_opts           = "string",
    git_diff_cmd        = "string",
    git_untracked_cmd   = "string",
  })
  setopts(config.oldfiles, opts.oldfiles, {
    prompt                  = "string",
    git_icons               = "boolean",
    file_icons              = "boolean",
    color_icons             = "boolean",
    git_diff_cmd            = "string",
    git_untracked_cmd       = "string",
    cwd_only                = "boolean",
    include_current_session = "boolean",
  })
  setopts(config.quickfix, opts.quickfix, {
    prompt                  = "string",
    cwd                     = "string",
    separator               = "string",
    git_icons               = "boolean",
    file_icons              = "boolean",
    color_icons             = "boolean",
    git_diff_cmd            = "string",
    git_untracked_cmd       = "string",
  })
  setopts(config.loclist, opts.loclist, {
    prompt                  = "string",
    cwd                     = "string",
    separator               = "string",
    git_icons               = "boolean",
    file_icons              = "boolean",
    color_icons             = "boolean",
    git_diff_cmd            = "string",
    git_untracked_cmd       = "string",
  })
  setopts(config.lsp, opts.lsp, {
    prompt                  = "string",
    cwd                     = "string",
    severity                = "string",
    severity_exact          = "string",
    severity_bound          = "string",
    lsp_icons               = "boolean",
    git_icons               = "boolean",
    file_icons              = "boolean",
    color_icons             = "boolean",
    git_diff_cmd            = "string",
    git_untracked_cmd       = "string",
  })
  setopts(config.git, opts.git, {
    prompt              = "string",
    cmd                 = "string",
    git_icons           = "boolean",
    file_icons          = "boolean",
    color_icons         = "boolean",
  })
  setopts(config.buffers, opts.buffers, {
    prompt                = "string",
    git_prompt            = "string",
    file_icons            = "boolean",
    color_icons           = "boolean",
    sort_lastused         = "boolean",
    show_all_buffers      = "boolean",
    ignore_current_buffer = "boolean",
    cwd_only              = "boolean",
  })
  setopts(config.colorschemes, opts.colorschemes, {
    prompt                = "string",
    live_preview          = "boolean",
    post_reset_cb         = "function",
  })
  setopts(config.manpages, opts.manpages, {
    prompt                = "string",
    cmd                   = "string",
  })
  setopts(config.helptags, opts.helptags, {
    prompt                = "string",
  })
  -- table overrides without losing defaults
  for _, k in ipairs({
    "git", "files", "oldfiles", "buffers",
    "grep", "quickfix", "loclist",
    "colorschemes", "helptags", "manpages",
  }) do
    setopt_tbl(config[k], opts[k], "actions")
    setopt_tbl(config[k], opts[k], "winopts")
  end
  setopt_tbl(config.git, opts.git, "icons")
  setopt_tbl(config.lsp, opts.lsp, "icons")
  setopt_tbl(config, opts, "file_icon_colors")
  -- override the bat preview theme if set by caller
  if config.bat_theme and #config.bat_theme > 0 then
    vim.env.BAT_THEME = config.bat_theme
  end
  -- reset default window opts if set by user
  fzf.default_window_options = config.winopts()
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

return M
