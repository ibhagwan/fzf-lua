local uv = vim.uv or vim.loop
local core = require "fzf-lua.core"
local path = require "fzf-lua.path"
local utils = require "fzf-lua.utils"
local shell = require "fzf-lua.shell"
local libuv = require "fzf-lua.libuv"
local config = require "fzf-lua.config"
local make_entry = require "fzf-lua.make_entry"

local M = {}

local get_files_cmd = function(opts)
  if opts.raw_cmd and #opts.raw_cmd > 0 then
    return opts.raw_cmd
  end
  if opts.cmd and #opts.cmd > 0 then
    return opts.cmd
  end
  local search_paths = (function()
    -- NOTE: deepcopy to avoid recursive shellescapes with `actions.toggle_ignore`
    local search_paths = type(opts.search_paths) == "table" and vim.deepcopy(opts.search_paths)
        or type(opts.search_paths) == "string" and { tostring(opts.search_paths) }
    -- Make paths relative, note this will not work well with resuming if changing
    -- the cwd, this is by design for perf reasons as having to deal with full paths
    -- will result in more code routes taken in `make_entry.file`
    if type(search_paths) == "table" then
      for i, p in ipairs(search_paths) do
        search_paths[i] = libuv.shellescape(path.relative_to(path.normalize(p), uv.cwd()))
      end
      return table.concat(search_paths, " ")
    end
  end)()
  local command = nil
  if vim.fn.executable("fdfind") == 1 then
    command = string.format("fdfind %s%s", opts.fd_opts,
      search_paths and string.format(" . %s", search_paths) or "")
  elseif vim.fn.executable("fd") == 1 then
    command = string.format("fd %s%s", opts.fd_opts,
      search_paths and string.format(" . %s", search_paths) or "")
  elseif vim.fn.executable("rg") == 1 then
    command = string.format("rg %s%s", opts.rg_opts,
      search_paths and string.format(" %s", search_paths) or "")
  elseif utils.__IS_WINDOWS then
    command = "dir /s/b/a:-d"
  else
    command = string.format("find -L %s %s",
      search_paths and search_paths or ".", opts.find_opts)
  end
  return command
end

M.files = function(opts)
  opts = config.normalize_opts(opts, "files")
  if not opts then return end
  if opts.ignore_current_file then
    local curbuf = vim.api.nvim_buf_get_name(0)
    if #curbuf > 0 then
      curbuf = path.relative_to(curbuf, opts.cwd or uv.cwd())
      opts.file_ignore_patterns = opts.file_ignore_patterns or {}
      table.insert(opts.file_ignore_patterns,
        "^" .. utils.lua_regex_escape(curbuf) .. "$")
    end
  end
  opts.cmd = get_files_cmd(opts)
  if utils.__IS_WINDOWS and opts.cmd:match("^dir") and not opts.cwd then
    -- `dir` command returns absolute paths with ^M for EOL
    -- `make_entry.file` will strip the ^M
    -- set `opts.cwd` for relative path display
    opts.cwd = uv.cwd()
  end
  local contents = core.mt_cmd_wrapper(opts)
  opts = core.set_title_flags(opts, { "cmd" })
  opts = core.set_header(opts, opts.headers or { "actions", "cwd" })
  return core.fzf_exec(contents, opts)
end

M.args = function(opts)
  opts = config.normalize_opts(opts, "args")
  if not opts then return end

  if vim.fn.argc() == 0 then
    utils.warn("arglist is empty.")
    return
  end

  opts.func_async_callback = false
  opts.__fn_reload = opts.__fn_reload or function(_)
    return function(cb)
      local argc = vim.fn.argc()

      -- use coroutine & vim.schedule to avoid
      -- E5560: vimL function must not be called in a lua loop callback
      coroutine.wrap(function()
        local co = coroutine.running()

        -- local start = os.time(); for _ = 1,10000,1 do
        for i = 0, argc - 1 do
          vim.schedule(function()
            local s = vim.fn.argv(i)
            local st = uv.fs_stat(s)
            if opts.files_only == false or st and st.type == "file" then
              s = make_entry.file(s, opts)
              cb(s, function()
                coroutine.resume(co)
              end)
            else
              coroutine.resume(co)
            end
          end)
          coroutine.yield()
        end
        -- end; print("took", os.time()-start, "seconds.")

        -- done
        cb(nil)
      end)()
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
