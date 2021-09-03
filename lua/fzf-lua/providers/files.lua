if not pcall(require, "fzf") then
  return
end

local fzf_helpers = require("fzf.helpers")
local core = require "fzf-lua.core"
local utils = require "fzf-lua.utils"
local config = require "fzf-lua.config"

local M = {}

local get_files_cmd = function(opts)
  if opts.raw_cmd and #opts.raw_cmd>0 then
    return opts.raw_cmd
  end
  if opts.cmd and #opts.cmd>0 then
    return opts.cmd
  end
  local command = nil
  if vim.fn.executable("fd") == 1 then
    if not opts.cwd or #opts.cwd == 0 then
      command = string.format('fd %s', opts.fd_opts)
    else
      command = string.format('fd %s . %s', opts.fd_opts,
        vim.fn.shellescape(vim.fn.expand(opts.cwd)))
    end
  else
    command = string.format('find -L %s %s',
      utils._if(opts.cwd and #opts.cwd>0,
      vim.fn.shellescape(vim.fn.expand(opts.cwd)), '.'),
      opts.find_opts)
  end
  return command
end

M.files = function(opts)

  opts = config.normalize_opts(opts, config.globals.files)

  local command = get_files_cmd(opts)

  opts.fzf_fn = fzf_helpers.cmd_line_transformer(command,
    function(x)
      return core.make_entry_file(opts, x)
    end)

  return core.fzf_files(opts)
end

return M
