if not pcall(require, "fzf") then
  return
end

-- local fzf = require "fzf"
local fzf_helpers = require("fzf.helpers")
-- local path = require "fzf-lua.path"
local core = require "fzf-lua.core"
local utils = require "fzf-lua.utils"
local config = require "fzf-lua.config"

local M = {}

local quickfix_run = function(opts, cfg, locations)
  if not locations then return {} end
  local results = {}
  for _, entry in ipairs(locations) do
    local filename = entry.filename or vim.api.nvim_buf_get_name(entry.bufnr)
    table.insert(results, string.format("%s:%s:%s:\t%s",
      filename, --utils.ansi_codes.magenta(filename),
      utils.ansi_codes.green(tostring(entry.lnum)),
      utils.ansi_codes.blue(tostring(entry.col)),
      entry.text))
  end

  opts = config.getopts(opts, cfg, {
    "cwd", "prompt", "actions", "winopts",
    "file_icons", "color_icons", "git_icons",
    "separator"
  })

  opts.fzf_fn = function (cb)
    for _, x in ipairs(results) do
      x = core.make_entry_file(opts, x)
      cb(x, function(err)
        if err then return end
        -- cb(nil) -- to close the pipe to fzf, this removes the loading
                   -- indicator in fzf
      end)
    end
  end

  --[[ opts.cb_selected = function(_, x)
    return x
  end ]]

  opts.cli_args = "--delimiter='[: \\t]'"
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
