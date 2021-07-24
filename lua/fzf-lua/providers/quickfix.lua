if not pcall(require, "fzf") then
  return
end

-- local fzf = require "fzf"
-- local fzf_helpers = require("fzf.helpers")
-- local path = require "fzf-lua.path"
local core = require "fzf-lua.core"
local utils = require "fzf-lua.utils"
local config = require "fzf-lua.config"

local M = {}

local quickfix_run = function(opts, cfg, locations)
  if not locations then return {} end
  local results = {}
  for _, entry in ipairs(locations) do
    table.insert(results, core.make_entry_lcol(opts, entry))
  end

  opts = config.getopts(opts, cfg, {
    "cwd", "prompt", "actions", "winopts",
    "file_icons", "color_icons", "git_icons",
    "separator"
  })

  if not opts.cwd then opts.cwd = vim.loop.cwd() end

  opts.fzf_fn = function (cb)
    for _, x in ipairs(results) do
      x = core.make_entry_file(opts, x)
      cb(x, function(err)
        if err then return end
          -- close the pipe to fzf, this
          -- removes the loading indicator in fzf
          cb(nil, function() end)
      end)
    end
    utils.delayed_cb(cb)
  end

  --[[ opts.cb_selected = function(_, x)
    return x
  end ]]

  local line_placeholder = 2
  if opts.file_icons == true or opts.git_icons == true then
    line_placeholder = line_placeholder+1
  end

  opts.cli_args = "--delimiter='[: \\t]'"
  opts.filespec = string.format("{%d}", line_placeholder-1)
  opts.preview_args = string.format("--highlight-line={%d}", line_placeholder)
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
  opts.preview_offset = string.format("+{%d}-/2", line_placeholder)
  return core.fzf_files(opts)
end

M.quickfix = function(opts)
  local locations = vim.fn.getqflist()
  if vim.tbl_isempty(locations) then
    utils.info("Quickfix list is empty.")
    return
  end

  return quickfix_run(opts, config.quickfix, locations)
end

M.loclist = function(opts)
  local locations = vim.fn.getloclist(0)

  for _, value in pairs(locations) do
    value.filename = vim.api.nvim_buf_get_name(value.bufnr)
  end

  if vim.tbl_isempty(locations) then
    utils.info("Location list is empty.")
    return
  end

  return quickfix_run(opts, config.loclist, locations)
end

return M
