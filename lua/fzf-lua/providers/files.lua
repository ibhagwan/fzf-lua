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
  if not opts then return end

  local command = get_files_cmd(opts)

  opts.fzf_fn = fzf_helpers.cmd_line_transformer(command,
    function(x)
      return core.make_entry_file(opts, x)
    end)

  return core.fzf_files(opts)
end

local last_query = ""

M.files_resume = function(opts)

  opts = config.normalize_opts(opts, config.globals.files)
  if not opts then return end
  if opts._is_skim then
    utils.info("'files_resume' is not supported with 'sk'")
    return
  end

  local raw_act = require("fzf.actions").raw_action(function(args)
    last_query = args[1]
  end, "{q}")

  local command = get_files_cmd(opts)

  opts._fzf_cli_args = ('--query="%s" --bind=change:execute:%s'):
    format(last_query, vim.fn.shellescape(raw_act))

  opts.fzf_fn = fzf_helpers.cmd_line_transformer(command,
    function(x)
      return core.make_entry_file(opts, x)
    end)

  return core.fzf_files(opts)
end

return M
