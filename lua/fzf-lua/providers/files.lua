local core = require "fzf-lua.core"
local utils = require "fzf-lua.utils"
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
  opts = config.normalize_opts(opts, config.globals.files)
  if not opts then return end
  opts.cmd = get_files_cmd(opts)
  local contents = core.mt_cmd_wrapper(opts)
  opts = core.set_header(opts, opts.headers or { "cwd" })
  return core.fzf_exec(contents, opts)
end

M.args = function(opts)
  opts = config.normalize_opts(opts, config.globals.args)
  if not opts then return end

  if opts.fzf_opts["--header"] == nil then
    opts.fzf_opts["--header"] = vim.fn.shellescape((":: %s to delete")
      :format(utils.ansi_codes.yellow("<Ctrl-x>")))
  end

  local contents = function(cb)
    local function add_entry(x, co)
      x = make_entry.file(x, opts)
      if not x then return end
      cb(x, function(err)
        coroutine.resume(co)
        if err then
          -- close the pipe to fzf, this
          -- removes the loading indicator in fzf
          cb(nil)
        end
      end)
      coroutine.yield()
    end

    -- run in a coroutine for async progress indication
    coroutine.wrap(function()
      local co = coroutine.running()

      local entries = vim.fn.execute("args")
      entries = utils.strsplit(entries, "%s\n")
      -- remove the current file indicator
      -- remove all non-files
      -- local start = os.time(); for _ = 1,10000,1 do
      for _, s in ipairs(entries) do
        if s:match("^%[") then
          s = s:gsub("^%[", ""):gsub("%]$", "")
        end
        local st = vim.loop.fs_stat(s)
        if opts.files_only == false or
            st and st.type == "file" then
          add_entry(s, co)
        end
      end
      -- end; print("took", os.time()-start, "seconds.")

      -- done
      cb(nil)
    end)()
  end

  opts = core.set_header(opts, opts.headers or { "cwd" })
  return core.fzf_exec(contents, opts)
end

return M
