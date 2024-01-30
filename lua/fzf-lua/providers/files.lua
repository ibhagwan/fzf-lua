local core = require "fzf-lua.core"
local path = require "fzf-lua.path"
local utils = require "fzf-lua.utils"
local shell = require "fzf-lua.shell"
local config = require "fzf-lua.config"
local make_entry = require "fzf-lua.make_entry"

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
  if opts.raw_cmd and #opts.raw_cmd > 0 then
    return opts.raw_cmd
  end
  if opts.cmd and #opts.cmd > 0 then
    return opts.cmd
  end
  local command = nil
  if vim.fn.executable("fdfind") == 1 then
    command = string.format("fdfind %s", opts.fd_opts)
  elseif vim.fn.executable("fd") == 1 then
    command = string.format("fd %s", opts.fd_opts)
  elseif vim.fn.executable("rg") == 1 then
    command = string.format("rg %s", opts.rg_opts)
  else
    POSIX_find_compat(opts.find_opts)
    command = string.format("find -L . %s", opts.find_opts)
  end
  return command
end

M.files = function(opts)
  opts = config.normalize_opts(opts, "files")
  if not opts then return end
  if opts.ignore_current_file then
    local curbuf = vim.api.nvim_buf_get_name(0)
    if #curbuf > 0 then
      curbuf = path.relative(curbuf, opts.cwd or vim.loop.cwd())
      opts.file_ignore_patterns = opts.file_ignore_patterns or {}
      table.insert(opts.file_ignore_patterns,
        "^" .. utils.lua_regex_escape(curbuf) .. "$")
    end
  end
  opts.cmd = get_files_cmd(opts)
  local contents = core.mt_cmd_wrapper(opts)
  opts = core.set_header(opts, opts.headers or { "actions", "cwd" })
  return core.fzf_exec(contents, opts)
end

M.args = function(opts)
  opts = config.normalize_opts(opts, "args")
  if not opts then return end

  opts.__fn_reload = opts.__fn_reload or function(_)
    local entries = vim.fn.execute("args")
    entries = utils.strsplit(entries, "%s\n")

    return function(cb)
      -- remove the current file indicator
      -- remove all non-files
      -- local start = os.time(); for _ = 1,10000,1 do
      for _, s in ipairs(entries) do
        if s:match("^%[") then
          s = s:gsub("^%[", ""):gsub("%]$", "")
        end
        local st = vim.loop.fs_stat(s)
        if opts.files_only == false or st and st.type == "file" then
          s = make_entry.file(s, opts)
          cb(s)
        end
      end
      -- end; print("took", os.time()-start, "seconds.")

      -- done
      cb(nil)
    end
  end

  -- build the "reload" cmd and remove '-- {+}' from the initial cmd
  local reload, id = shell.reload_action_cmd(opts, "{+}")
  local contents = reload:gsub("%-%-%s+{%+}$", "")
  opts.__reload_cmd = reload

  opts._fn_pre_fzf = function()
    shell.set_protected(id)
  end

  opts = core.set_header(opts, opts.headers or { "actions", "cwd" })
  return core.fzf_exec(contents, opts)
end

return M
