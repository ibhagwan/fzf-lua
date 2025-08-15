local uv = vim.uv or vim.loop
local core = require "fzf-lua.core"
local path = require "fzf-lua.path"
local utils = require "fzf-lua.utils"
local libuv = require "fzf-lua.libuv"
local config = require "fzf-lua.config"
local make_entry = require "fzf-lua.make_entry"

local M = {}

---@param opts table
---@return string
M.get_files_cmd = function(opts)
  if opts.raw_cmd and #opts.raw_cmd > 0 then
    return opts.raw_cmd
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
  if opts.cmd and #opts.cmd > 0 then
    command = opts.cmd
  elseif vim.fn.executable("fdfind") == 1 then
    command = string.format("fdfind %s%s", opts.fd_opts,
      search_paths and string.format(" . %s", search_paths) or "")
  elseif vim.fn.executable("fd") == 1 then
    command = string.format("fd %s%s", opts.fd_opts,
      search_paths and string.format(" . %s", search_paths) or "")
  elseif vim.fn.executable("rg") == 1 then
    command = string.format("rg %s%s", opts.rg_opts,
      search_paths and string.format(" %s", search_paths) or "")
  elseif utils.__IS_WINDOWS then
    command = "dir " .. opts.dir_opts
  else
    command = string.format("find %s %s",
      search_paths and search_paths or ".", opts.find_opts)
  end
  for k, v in pairs({
    follow = opts.toggle_follow_flag or "-L",
    hidden = opts.toggle_hidden_flag or "--hidden",
    no_ignore = opts.toggle_ignore_flag or "--no-ignore",
  }) do
    (function()
      local toggle, is_find = opts[k], nil
      -- Do nothing unless opt was set
      if opts[k] == nil then return end
      if command:match("^dir") then return end
      if command:match("^find") then
        if k == "no_ignore" then return end
        if k == "hidden" then
          is_find = true
          toggle = not opts[k]
          v = [[\! -path '*/.*']]
        end
      end
      command = utils.toggle_cmd_flag(command, v, toggle, is_find)
    end)()
  end
  return command
end

M.files = function(opts)
  ---@type fzf-lua.config.Files
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
  opts.cmd = M.get_files_cmd(opts)
  if utils.__IS_WINDOWS and opts.cmd:match("^dir") and not opts.cwd then
    -- `dir` command returns absolute paths with ^M for EOL
    -- `make_entry.file` will strip the ^M
    -- set `opts.cwd` for relative path display
    opts.cwd = uv.cwd()
  end
  opts = core.set_title_flags(opts, { "cmd" })
  return core.fzf_exec(opts.cmd, opts)
end

M.args = function(opts)
  ---@type fzf-lua.config.Args
  opts = config.normalize_opts(opts, "args")
  if not opts then return end

  if vim.fn.argc() == 0 then
    utils.warn("arglist is empty.")
    return
  end

  local contents = function(cb)
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

  return core.fzf_exec(contents, opts)
end

M.zoxide = function(opts)
  ---@type fzf-lua.config.Zoxide
  opts = config.normalize_opts(opts, "zoxide")
  if not opts then return end

  if vim.fn.executable("zoxide") ~= 1 then
    utils.warn("Install zoxide to use this picker.")
    return
  end

  if opts.header == nil then
    opts.header = string.format("%8s\t%s", "score", "folder")
  end

  opts.preview = (function()
    if opts.preview then return opts.preview end
    return vim.fn.executable("lsd") == 1
        and "lsd -la --color=always --icon=always --group-directories-first --literal {2}"
        or vim.fn.executable("eza") == 1
        and "eza -la --color=always --icons -g --group-directories-first {2}"
        or "ls -la {2}"
  end)()

  return core.fzf_exec(opts.cmd, opts)
end

return M
