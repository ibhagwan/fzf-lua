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

M.oldfiles = function(opts)
  opts = config.getopts(opts, config.oldfiles, {
    "prompt", "actions", "winopts",
    "file_icons", "color_icons", "git_icons",
    "include_current_session", "cwd_only",
  })

  local current_buffer = vim.api.nvim_get_current_buf()
  local current_file = vim.api.nvim_buf_get_name(current_buffer)
  local results = {}

  if opts.include_current_session then
    for _, buffer in ipairs(vim.split(vim.fn.execute(':buffers! t'), "\n")) do
      local match = tonumber(string.match(buffer, '%s*(%d+)'))
      if match then
        local file = vim.api.nvim_buf_get_name(match)
        if vim.loop.fs_stat(file) and match ~= current_buffer then
          table.insert(results, file)
        end
      end
    end
  end

  for _, file in ipairs(vim.v.oldfiles) do
    if vim.loop.fs_stat(file) and not vim.tbl_contains(results, file) and file ~= current_file then
      table.insert(results, file)
    end
  end

  if opts.cwd_only then
    opts.cwd = vim.loop.cwd()
    local cwd = opts.cwd
    cwd = cwd:gsub([[\]],[[\\]])
    results = vim.tbl_filter(function(file)
      return vim.fn.matchstrpos(file, cwd)[2] ~= -1
    end, results)
  end

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
    cb(nil, function() end)
  end

  --[[ opts.cb_selected = function(_, x)
    print("o:", x)
  end ]]

  return core.fzf_files(opts)
end

return M
