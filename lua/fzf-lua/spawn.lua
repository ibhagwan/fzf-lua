---@diagnostic disable-next-line: deprecated
-- This file should only be loaded from the headless instance
local uv = vim.uv or vim.loop
assert(#vim.api.nvim_list_uis() == 0)

local sysname = uv.os_uname().sysname
local _is_win = sysname:match("Windows") and true or false

-- path to this file
local __FILE__ = debug.getinfo(1, "S").source:gsub("^@", "")

-- add the current folder to package.path so we can 'require'
-- prepend this folder first, so our modules always get first
-- priority over some unknown random module with the same name
package.path = ("%s/?.lua;"):format(vim.fn.fnamemodify(__FILE__, ":h:h")) .. package.path

-- due to 'os.exit' neovim doesn't delete the temporary
-- directory, save it so we can delete prior to exit (#329)
-- NOTE: opted to delete the temp dir at the start due to:
--   (1) spawn_stdio doesn't need a temp directory
--   (2) avoid dangling temp dirs on process kill (i.e. live_grep)
local tmpdir = vim.fn.fnamemodify(vim.fn.tempname(), ":h")
if tmpdir and #tmpdir > 0 then
  -- io.stdout:write(string.format("[DEBUG] tmpdir=%s\n", tmpdir))
  -- _G.dump(vim.uv.fs_stat(tmpdir))
  vim.fn.delete(tmpdir, "rf")
end

-- neovim might also automatically start the RPC server which will
-- generate a named pipe temp file, e.g. `/run/user/1000/nvim.14249.0`
-- we don't need the server in the headless "child" process, stopping
-- the server also deletes the temp file
if vim.v.servername and #vim.v.servername > 0 then
  pcall(vim.fn.serverstop, vim.v.servername)
end

-- global var indicating a headless instance
_G._fzf_lua_is_headless = true

---@param pipename string
---@return uv.uv_pipe_t
local pipe_open = function(pipename)
  local fd = assert(uv.fs_open(pipename, "w", -1))
  local pipe = assert(uv.new_pipe(false))
  pipe:open(fd)
  return pipe
end

---@param handle file
---@return fzf-lua.Pipe
local function wrap_io(handle)
  local closing = false
  ---@class fzf-lua.Pipe: uv.uv_pipe_t
  local pipe = {}
  ---@param _ fzf-lua.Pipe
  ---@param data string
  ---@param cb fun(err: any): nil
  pipe.write = function(_, data, cb)
    local ok, err = handle:write(data)
    if cb then cb(not ok and (err or "write error") or nil) end
  end
  pipe.is_active = function() return not closing end
  pipe.is_closing = function() return closing end
  pipe.close = function(_) closing = true end
  return pipe
end

local posix_exec = function(cmd)
  if type(cmd) ~= "string" or _is_win or not pcall(require, "ffi") then return end
  require("ffi").cdef([[int execl(const char *, const char *, ...);]])
  require("ffi").C.execl("/bin/sh", "sh", "-c", cmd, nil)
end

---@type fzf-lua.SpawnStdioOpts
local opts = require("fzf-lua.libuv").deserialize(assert(_G.arg[1]))

-- setup global vars
for k, v in pairs(opts.g or {}) do _G[k] = v end

-- Requiring make_entry will create the pseudo `_G.FzfLua` global
-- Must be called after global vars are created or devicons will
-- err with "fzf-lua fatal: '_G._fzf_lua_server', '_G._devicons_path' both nil"
require("fzf-lua.make_entry")
local libuv = require("fzf-lua.libuv")

-- still need load_fn from str val? now deserialize do all the thing automatically
-- or because we want to debugprint them, so we still make a string?
local fn_transform = libuv.load_fn(opts.fn_transform) or opts.fn_transform
-- TODO: this should have new semantic? "push"/"fetch" the state to/from worker
-- also maybe we can merge rpc.lua/spawn.lua
local fn_preprocess = libuv.load_fn(opts.fn_preprocess) or opts.fn_preprocess
local fn_postprocess = libuv.load_fn(opts.fn_postprocess) or opts.fn_postprocess

-- stdin/stdout are already buffered, not stderr. This means
-- that every character is flushed immediately which caused
-- rendering issues on Mac (#316, #287) and Linux (#414)
-- switch 'stderr' stream to 'line' buffering
-- https://www.lua.org/manual/5.2/manual.html#pdf-file%3asetvbuf
io.stderr:setvbuf "line"
-- opts.{stdout,stderr} is opt-in after #252
local stderr = type(opts.stderr) == "string" and pipe_open(opts.stderr) or wrap_io(io.stderr)
local stdout = type(opts.stdout) == "string" and pipe_open(opts.stdout) or wrap_io(io.stdout)
local redir = (opts.stderr_to_stdout or (opts.stderr_to_stdout == nil and sysname == "Darwin"))
    and stdout or stderr
local EOL = _G._EOL or opts.multiline and "\0" or "\n" ---@as string
-- TODO: do we need different verbose level?
local vdbg = opts.debug == "v" or opts.debug == 2

local argv = function(i)
  local idx = tonumber(i) or #_G.arg
  local arg = _G.arg[idx]
  if vdbg then
    io.stdout:write(("[DEBUG] raw_argv(%d) = %s" .. EOL):format(idx, arg))
  end
  -- TODO: maybe not needed anymore? since we're not using v:argv
  if _is_win then
    arg = libuv.unescape_fzf(arg, FzfLua.utils.has(opts, "fzf", { 0, 52 }) and 0.52 or 0)
  end
  if vdbg then
    io.stdout:write(("[DEBUG] esc_argv(%d) = %s" .. EOL):format(idx, libuv.shellescape(arg)))
  end
  return arg
end

-- Since the `rg` command will be wrapped inside the shell escaped
-- 'nvim -l ...', we won't be able to search single quotes
-- NOTE: since we cannot guarantee the positional index
-- of arguments (#291), we use the last argument instead
if opts.is_live and type(opts.contents) == "string" then
  opts.contents = FzfLua.make_entry.expand_query(opts, assert(argv()), opts.contents)
end

---@type fzf-lua.content|fzf-lua.shell.data2?
local content = opts.contents
if type(content) == "string" and content:match("%-%-color[=%s]+never") then
  -- perf: skip stripping ansi coloring in `make_file.entry`
  opts.no_ansi_colors = true
end

if vdbg then
  for k, v in vim.spairs(opts) do
    stdout:write(string.format("[DEBUG] %s=%s" .. EOL, k, vim.inspect(v)))
  end
elseif opts.debug then
  stdout:write("[DEBUG] [mt] " .. tostring(content) .. EOL)
end

local function exit(exit_code, msg)
  if msg then stderr:write(msg) end
  os.exit(exit_code)
end

---@param pipe uv.uv_pipe_t
---@param data uv.buffer
---@param cb? fun(err: any): nil
local function pipe_write(pipe, data, cb)
  if pipe:is_closing() then return end
  pipe:write(data, function(err)
    -- if the user cancels the call prematurely with
    -- <C-c>, err will be either EPIPE or ECANCELED
    -- don't really need to do anything since the
    -- processes will be killed anyways with os.exit()
    if err then stderr:write(("pipe:write error: %s" .. EOL):format(err)) end
    if cb then cb(err) end
  end)
end

local on_finish = function(code)
  if stdout ~= io.stdout and not stdout:is_closing() then stdout:close() end
  if stderr ~= io.stderr and not stderr:is_closing() then stderr:close() end
  if vim.in_fast_event() and fn_postprocess then
    vim.schedule(function()
      fn_postprocess(opts)
      exit(code)
    end)
    -- No child process was spawned (content was table/function, not a string command).
    -- `on_finish` has already scheduled `fn_postprocess` + `os.exit` via `vim.schedule`,
    -- we need to pump the event loop so the scheduled callback fires.
    -- Use `vim.wait` to process `vim.schedule` callbacks (unlike `uv.run`).
    vim.wait(10000)
  else
    if fn_postprocess then fn_postprocess(opts) end
    exit(code)
  end
end

-- seems no longer needed if we already run in thread
-- both fn_preprocess/fn_postprocess need to be done in thread
-- if fn_preprocess then fn_preprocess(opts) end
if type(content) ~= "string" then
  if opts.is_live then ---@cast content fzf-lua.shell.data2
    local res = content(vim.list_slice(_G.arg, 2), opts)
    if not res then return on_finish(0), nil end ---@cast res-?
    content = res
  end
  if opts.debug then io.stdout:write(("[DEBUG] [mt] %s" .. EOL):format(content)) end
end

if not fn_transform and not fn_postprocess and posix_exec(content) then
  return
end

local session = require("fzf-lua.job").transform({
  cwd = opts.cwd,
  content = assert(content),
  cb_finish = on_finish,
  output_pipe = stdout,
  cb_err = opts.stderr ~= false and function(data) redir:write(data) end or nil,
  EOL = EOL,
  opts = opts,
})

if not session then return on_finish(1) end

-- the pid don't really matter if stream closed..
-- local done = function() return uv.os_getpriority(session.pid) == nil and session:can_finish() end
local done = function() return session:can_finish() end
while not done() do
  vim.wait(100, done)
end
