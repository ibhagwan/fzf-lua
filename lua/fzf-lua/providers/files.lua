local core = require "fzf-lua.core"
local utils = require "fzf-lua.utils"
local shell = require "fzf-lua.shell"
local config = require "fzf-lua.config"
local libuv = require "fzf-lua.libuv"

local M = {}

local function POSIX_find_compat(opts)
  local ver = utils.find_version()
  -- POSIX find does not have '--version'
  -- we assume POSIX when 'ver==nil'
  if not ver and opts:match("%-printf") then
    utils.warn("POSIX find does not support the '-printf' option." ..
      " Install 'fd' or set 'files.find_opts' to '-type f'.")
  end
end

local get_files_cmd = function(opts)
  if opts.raw_cmd and #opts.raw_cmd>0 then
    return opts.raw_cmd
  end
  if opts.cmd and #opts.cmd>0 then
    return opts.cmd
  end
  local command = nil
  if vim.fn.executable("fd") == 1 then
    command = string.format('fd %s', opts.fd_opts)
  else
    POSIX_find_compat(opts.find_opts)
    command = string.format('find -L . %s', opts.find_opts)
  end
  return command
end

M.files = function(opts)

  opts = config.normalize_opts(opts, config.globals.files)
  if not opts then return end

  local command = get_files_cmd(opts)

  opts.fzf_fn = libuv.spawn_nvim_fzf_cmd(
    { cmd = command, cwd = opts.cwd, pid_cb = opts._pid_cb },
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

  local raw_act = shell.raw_action(function(args)
    last_query = args[1]
  end, "{q}")

  local command = get_files_cmd(opts)

  opts.fzf_opts['--query'] = vim.fn.shellescape(last_query)
  opts._fzf_cli_args = ('--bind=change:execute-silent:%s'):
    format(vim.fn.shellescape(raw_act))

  opts.fzf_fn = libuv.spawn_nvim_fzf_cmd(
    {cmd = command, cwd = opts.cwd},
    function(x)
      return core.make_entry_file(opts, x)
    end)

  return core.fzf_files(opts)
end

M.args = function(opts)
  opts = config.normalize_opts(opts, config.globals.args)
  if not opts then return end

  local entries = vim.fn.execute("args")
  entries = utils.strsplit(entries, "%s\n")
  -- remove the current file indicator
  -- remove all non-files
  local args = {}
  for _, s in ipairs(entries) do
    if s:match('^%[') then
      s = s:gsub('^%[', ''):gsub('%]$', '')
    end
    local st = vim.loop.fs_stat(s)
    if opts.files_only == false or
       st and st.type == 'file' then
      table.insert(args, s)
    end
  end
  entries = nil

  opts.fzf_fn = function (cb)
    for _, x in ipairs(args) do
      x = core.make_entry_file(opts, x)
      if x then
        cb(x, function(err)
          if err then return end
            -- close the pipe to fzf, this
            -- removes the loading indicator in fzf
            cb(nil, function() end)
        end)
      end
    end
    utils.delayed_cb(cb)
  end

  return core.fzf_files(opts)
end

return M
