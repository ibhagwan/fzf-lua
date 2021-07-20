if not pcall(require, "fzf") then
  return
end

-- local fzf = require "fzf"
local fzf_helpers = require("fzf.helpers")
local path = require "fzf-lua.path"
local core = require "fzf-lua.core"
local utils = require "fzf-lua.utils"
local config = require "fzf-lua.config"

local M = {}

local get_grep_cmd = function(opts)

  local command = nil
  if opts.cmd and #opts.cmd > 0 then
    command = opts.cmd
  elseif vim.fn.executable("rg") == 1 then
    command = string.format("rg %s", opts.rg_opts)
  else
    command = string.format("grep %s", opts.grep_opts)
  end

  -- filename takes precedence over directory
  local search_path = ''
  if opts.filename and #opts.filename>0 then
    search_path = vim.fn.shellescape(opts.filename)
  elseif opts.cwd and #opts.cwd>0 then
    search_path = vim.fn.shellescape(opts.cwd)
  end

  return string.format("%s -- %s %s", command,
    utils._if(opts.last_search and #opts.last_search>0,
      vim.fn.shellescape(opts.last_search), "{q}"),
      search_path
  )
end

M.grep = function(opts)

  opts = config.getopts(opts, config.grep, {
    "cmd", "prompt", "actions", "winopts",
    "file_icons", "color_icons", "git_icons",
    "search", "input_prompt",
    "rg_opts", "grep_opts",
  })

  if opts.search and #opts.search>0 then
    opts.search = utils.rg_escape(opts.search)
  end

  if opts.repeat_last_search == true then
    opts.search = config.grep.last_search
  end
  -- save the next search as last_search so we
  -- let the caller have an option to run the
  -- same search again
  if not opts.search or #opts.search == 0 then
    config.grep.last_search = vim.fn.input(opts.input_prompt)
  else
    config.grep.last_search = opts.search
  end
  opts.last_search = config.grep.last_search
  if not opts.last_search or #opts.last_search == 0 then
    utils.info("Please provider valid search string")
    return
  end

  local command = get_grep_cmd(opts)

  opts.fzf_fn = fzf_helpers.cmd_line_transformer(
    command,
    function(x)
      return core.make_entry_file(opts, x)
    end)

  --[[ opts.cb_selected = function(_, x)
    return x
  end ]]

  opts.cli_args = "--delimiter='[: ]'"
  opts.preview_args = "--highlight-line={3}"    -- bat higlight
  --[[
    # Preview with bat, matching line in the middle of the window below
    # the fixed header of the top 3 lines
    #
    #   ~3    Top 3 lines as the fixed header
    #   +{2}  Base scroll offset extracted from the second field
    #   +3    Extra offset to compensate for the 3-line header
    #   /2    Put in the middle of the preview area
    #
    '--preview-window '~3:+{2}+3/2''
  ]]
  opts.preview_offset = "+{3}-/2"
  core.fzf_files(opts)
end


M.live_grep = function(opts)

  opts = config.getopts(opts, config.grep, {
    "cmd", "prompt", "actions", "winopts",
    "file_icons", "color_icons", "git_icons",
    "search", "input_prompt",
    "rg_opts", "grep_opts",
  })

  if opts.search and #opts.search>0 then
    opts.search = utils.rg_escape(opts.search)
  end

  -- resetting last_search will return
  -- {q} placeholder in our command
  opts.last_search = opts.search
  local initial_command = get_grep_cmd(opts)
  opts.last_search = nil
  local reload_command = get_grep_cmd(opts) .. " || true"

  --[[ local fzf_binds = utils.tbl_deep_clone(config.fzf_binds)
  table.insert(fzf_binds, string.format("change:reload:%s", reload_command))
  opts.fzf_binds = vim.fn.shellescape(table.concat(fzf_binds, ',')) ]]

  opts.cli_args = "--delimiter='[: ]' " ..
    string.format("--phony --query=%s --bind=%s",
      utils._if(opts.search and #opts.search>0, opts.search, [['']]),
      vim.fn.shellescape(string.format("change:reload:%s", reload_command)))

  opts.preview_args = "--highlight-line={3}"    -- bat higlight
  --[[
    # Preview with bat, matching line in the middle of the window below
    # the fixed header of the top 3 lines
    #
    #   ~3    Top 3 lines as the fixed header
    #   +{2}  Base scroll offset extracted from the second field
    #   +3    Extra offset to compensate for the 3-line header
    #   /2    Put in the middle of the preview area
    #
    '--preview-window '~3:+{2}+3/2''
  ]]
  opts.preview_offset = "+{3}-/2"


  -- TODO:
  -- this is not getting called past the initial command
  -- until we fix that we cannot use icons as they interfere
  -- with the extension parsing
  opts.git_icons = false
  opts.file_icons = false
  opts.filespec = '{1}'
  opts.preview_offset = "+{2}-/2"
  opts.preview_args = "--highlight-line={2}"    -- bat higlight

  opts.fzf_fn = fzf_helpers.cmd_line_transformer(
    initial_command,
    function(x)
      return core.make_entry_file(opts, x)
    end)

  core.fzf_files(opts)
end

M.grep_last = function(opts)
  if not opts then opts = {} end
  opts.repeat_last_search = true
  return M.grep(opts)
end

M.grep_cword = function(opts)
  if not opts then opts = {} end
  opts.search = vim.fn.expand("<cword>")
  return M.grep(opts)
end

M.grep_cWORD = function(opts)
  if not opts then opts = {} end
  opts.search = vim.fn.expand("<cWORD>")
  return M.grep(opts)
end

M.grep_visual = function(opts)
  if not opts then opts = {} end
  opts.search = utils.get_visual_selection()
  return M.grep(opts)
end

M.grep_curbuf = function(opts)
  if not opts then opts = {} end
  opts.rg_opts = config.grep.rg_opts .. " --with-filename"
  opts.filename = vim.api.nvim_buf_get_name(0)
  if #opts.filename > 0 then
    opts.filename = path.relative(opts.filename, vim.loop.cwd())
    return M.live_grep(opts)
  else
    utils.info("Rg current buffer requires actual file on disk")
    return
  end
end

return M
