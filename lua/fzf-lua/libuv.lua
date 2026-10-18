---@diagnostic disable-next-line: deprecated
local uv = vim.uv or vim.loop

local _is_win = vim.fn.has("win32") == 1 or vim.fn.has("win64") == 1

local M = {}

local base64 = require("fzf-lua.lib.base64")
local serpent = require("fzf-lua.lib.serpent")

---@param pid integer
---@param signal integer|string?
---@return boolean
M.process_kill = function(pid, signal)
  if not pid or not tonumber(pid) then return false end
  if type(uv.os_getpriority(pid)) == "number" then
    uv.kill(pid, signal or 9)
    return true
  end
  return false
end

local function coroutine_callback(fn)
  local co = coroutine.running()
  ---@cast co thread
  local callback = function(...)
    if coroutine.status(co) == "suspended" then
      coroutine.resume(co, ...)
    else
      local pid = unpack({ ... }) ---@cast pid integer
      M.process_kill(pid)
    end
  end
  fn(callback)
  return coroutine.yield()
end

local function coroutinify(fn)
  return function(...)
    local args = { ... }
    return coroutine.wrap(function()
      return coroutine_callback(function(cb)
        table.insert(args, cb)
        fn(unpack(args))
      end)
    end)()
  end
end

-- fix environ for uv.spawn
---@param cmd string
---@param opts uv.spawn.options
---@param on_exit fun(code: integer, signal: integer)
---@return uv.uv_process_t handle
---@return integer pid
M.uv_spawn = function(cmd, opts, on_exit)
  opts.env = (function()
    -- uv.spawn will override all env when table provided?
    -- steal from $VIMRUNTIME/lua/vim/_system.lua
    local env = vim.fn.environ() --- @type table<string,string>
    env["NVIM"] = vim.v.servername
    env["NVIM_LISTEN_ADDRESS"] = nil
    env = vim.tbl_extend("keep", opts.env or {}, env or {})
    local renv = {} --- @type string[]
    for k, v in pairs(env) do
      renv[#renv + 1] = string.format("%s=%s", k, tostring(v))
    end
    return renv
  end)() ---@diagnostic disable-next-line: unnecessary-assert, return-type-mismatch, redundant-return-value
  return assert(uv.spawn(cmd, opts, on_exit))
end

-- The FFI table must be obtained via `require("ffi")`: it is cached in
-- `package.loaded`, so all code shares a single CType state. Calling the
-- library constructor directly (`package.preload.ffi()`) re-runs
-- `luaopen_ffi`, which re-initializes the CType state: every previous
-- `cdef` is dropped and already-resolved symbols start resolving to
-- unrelated types (calling them fails with e.g. `'short' is not callable`).
-- All Windows APIs used by this module are declared in a single `cdef`.
local win_ffi = nil ---@type table|false|nil

---@return { ffi: table, k32: table }?
local function win_ffi_init()
  if win_ffi ~= nil then return win_ffi or nil end
  local ok, res = pcall(function()
    local ffi = require("ffi")
    ffi.cdef([[
      void* CreateFileW(const unsigned short*, unsigned long,
        unsigned long, void*, unsigned long, unsigned long, void*);
      int _open_osfhandle(long long, int);
      void* GetStdHandle(unsigned long nStdHandle);
      int GetHandleInformation(void* hObject, unsigned long* lpdwFlags);
      int SetHandleInformation(void* hObject, unsigned long dwMask,
        unsigned long dwFlags);
      typedef struct {
        unsigned long nLength;
        void* lpSecurityDescriptor;
        int bInheritHandle;
      } FzfSA;
    ]])
    return { ffi = ffi, k32 = ffi.load("kernel32") }
  end)
  win_ffi = (ok and res) or false
  return win_ffi or nil
end

-- Reopen the Windows console (`CONIN$`/`CONOUT$`) as inheritable CRT fds.
-- When the shell widgets capture both output streams (e.g. a PSReadLine key
-- handler piping stdout and stderr), spawned children have no console handle
-- left to inherit: nvim's TUI hangs without one and fzf silently ignores
-- `--height` (the light renderer writes the UI to a console stderr and falls
-- back to fullscreen without one). Returns `{ stdin, stdout, stderr }` fds,
-- or nil when the console cannot be reopened (or on other platforms).
M.win_console_stdio = function()
  if not _is_win then return end
  if M._win_console_fds ~= nil then return M._win_console_fds or nil end
  local ok = pcall(function()
    local win = win_ffi_init()
    local ffi = assert(win and win.ffi)
    local function wsz(s)
      local b = ffi.new("unsigned short[?]", #s + 1)
      for i = 1, #s do b[i - 1] = s:byte(i) end
      return b
    end
    local sa = ffi.new("FzfSA")
    sa.nLength = ffi.sizeof(sa)
    sa.bInheritHandle = 1
    -- The handles must allow *write* access, not just read: nvim's TUI
    -- calls `SetConsoleMode` on stdin (needs `GENERIC_WRITE`) and hangs
    -- before rendering anything if that fails.
    local GENERIC_RW, SHARE_RW, OPEN_EXISTING = 0xC0000000, 3, 3
    local hi = ffi.C.CreateFileW(wsz("CONIN$"), GENERIC_RW, SHARE_RW, sa, OPEN_EXISTING, 0, nil)
    local ho = ffi.C.CreateFileW(wsz("CONOUT$"), GENERIC_RW, SHARE_RW, sa, OPEN_EXISTING, 0, nil)
    local vi = tonumber(ffi.cast("intptr_t", hi))
    local vo = tonumber(ffi.cast("intptr_t", ho))
    if vi == -1 or vo == -1 then error("CreateFileW failed") end
    local conin = ffi.C._open_osfhandle(ffi.cast("long long", hi), 0)
    local conout = ffi.C._open_osfhandle(ffi.cast("long long", ho), 0)
    if conin < 0 or conout < 0 then error("_open_osfhandle failed") end
    M._win_console_fds = { conin, conout, conout } ---@type integer[]|false
  end)
  if not ok then M._win_console_fds = false end
  return M._win_console_fds or nil
end

-- Returns the stderr fd to pass to `uv.spawn` so the child sees a console:
-- fd 2 is reused when it already is a tty, otherwise `CONOUT$` is reopened
-- (see `win_console_stdio`); falls back to fd 2 when neither is possible.
-- Always 2 on non-Windows platforms.
M.win_stderr_fd = function()
  if not _is_win then return 2 end
  local ok, tty = pcall(uv.guess_handle, 2)
  if ok and tty == "tty" then return 2 end
  local console = M.win_console_stdio()
  return console and console[3] or 2
end

--- libuv as bundled with Neovim (<= 1.52) spawns children with
--- `CreateProcess(bInheritHandles=TRUE)` and no
--- `PROC_THREAD_ATTRIBUTE_HANDLE_LIST`, so *every* inheritable handle of
--- this process leaks into the child even when it isn't part of `stdio`.
--- When a shell integration captures the picker output (stdout/stderr are
--- pipes), those pipes would end up in the spawned process tree; an nvim
--- `--embed` server left running by `:detach` would then keep the pipes'
--- write end open forever and the shell's pipeline reader would never see
--- EOF (stuck shell/key handler).
---
--- Temporarily clears `HANDLE_FLAG_INHERIT` on the stdio fds (`0`, `1`,
--- `2`) that are not referenced by `stdio`. Returns a function restoring
--- the original flags; call it right after `uv.spawn` returns (the
--- child's handle table is fixed at `CreateProcess` time).
---@param stdio table stdio table as passed to `uv.spawn`
---@return fun()|nil restore
M.win_stdio_no_inherit = function(stdio)
  if not _is_win then return end
  local win = win_ffi_init()
  if not win then return end
  local ffi, k32 = win.ffi, win.k32
  local in_use = {} ---@type table<integer, boolean>
  for _, std in ipairs(stdio) do
    if type(std) == "number" then
      ---@cast std integer
      in_use[std] = true
    end
  end
  local HANDLE_FLAG_INHERIT = 1
  -- STD_INPUT_HANDLE/STD_OUTPUT_HANDLE/STD_ERROR_HANDLE (fds 0/1/2)
  local STD_HANDLES = { 0xFFFFFFF6, 0xFFFFFFF5, 0xFFFFFFF4 }
  local saved = {} ---@type { h: any, flags: integer }[]
  for fd = 0, 2 do
    if not in_use[fd] then
      local h = k32.GetStdHandle(STD_HANDLES[fd + 1])
      local flags = ffi.new("unsigned long[1]")
      if k32.GetHandleInformation(h, flags) ~= 0
          and k32.SetHandleInformation(h, HANDLE_FLAG_INHERIT, 0) ~= 0 then
        saved[#saved + 1] = { h = h, flags = flags[0] }
      end
    end
  end
  if #saved == 0 then return end
  return function()
    for _, s in ipairs(saved) do
      k32.SetHandleInformation(s.h, HANDLE_FLAG_INHERIT, s.flags)
    end
  end
end

---@class fzf-lua.WinSpawnSpec
---@field bin string fzf executable (`fzf`/`sk` or full path)
---@field args string[] raw fzf argv (`uv.spawn` prepends `bin` as argv[0])
---@field item? string producer command (cmd syntax), piped into fzf stdin
---@field outfile string fzf stdout is redirected to this file
---@field env? table<string,any>
---@field cwd? string
---@field stdin? integer fzf stdin fd when there is no `item` (default 0)
---@field stderr? integer fzf stderr fd (default `win_stderr_fd()`)

-- Windows ("one route") fzf spawn for `fzf.raw_fzf`: no shell, no escaping.
-- `uv.spawn` runs fzf with the raw argv (`_cli_segments`), stderr stays on
-- the console/pty (fzf's light renderer requires a console, see
-- `IsLightRendererSupported` in fzf's `src/tui/light_windows.go`), stdout is
-- redirected to `spec.outfile` (replaces the `> outfile` shell redirect) and
-- the optional `spec.item` producer is spawned via `cmd.exe /c` with its
-- stdout pumped into fzf's stdin, every chunk forwarded as-is, immediately.
-- This replaces the caret-escaped cmd.exe launcher, the `(item) | fzf` cmd
-- pipeline and the >8191-char PowerShell fallback. Callers: `scripts/cli.lua`
-- (CLI nvim) and `win_spawn.lua` (mediator for TUI terminal buffers).
---@param spec fzf-lua.WinSpawnSpec
---@param opts { on_exit: fun(rc: integer) } called once fzf and the producer
---  tree exited (the `outfile` is flushed before that)
---@return boolean ok false when fzf failed to spawn (on_exit(1) still called)
M.win_spawn = function(spec, opts)
  assert(_is_win, "win_spawn is Windows only")
  -- pause the producer read when this many bytes are queued for fzf
  local HIGH, LOW = 4 * 1024 * 1024, 1024 * 1024
  local item = spec.item and #spec.item > 0 and spec.item or nil
  local stderr_fd = spec.stderr or M.win_stderr_fd()
  ---@type integer?
  local out_fd = assert(uv.fs_open(spec.outfile, "w", 420))
  local prod_out = item and assert(uv.new_pipe(false)) or nil
  local fzf_in = item and assert(uv.new_pipe(false)) or nil
  local fzf_handle, prod_handle, kill_handle, kill_null
  local prod_pid
  local fzf_done, prod_done, kill_done = false, item == nil, true
  local fzf_rc, finished
  local writes, pending, paused, eof = 0, 0, false, false

  ---@param h uv.uv_pipe_t|uv.uv_process_t|nil
  local function close_handle(h)
    if h and not h:is_closing() then h:close() end
  end

  local function finish(rc)
    if finished then return end
    finished = true
    close_handle(fzf_in)
    close_handle(prod_out)
    close_handle(kill_handle)
    close_handle(kill_null)
    close_handle(fzf_handle)
    close_handle(prod_handle)
    if out_fd then
      uv.fs_close(out_fd)
      out_fd = nil
    end
    opts.on_exit(rc)
  end

  local function maybe_finish()
    if fzf_done and prod_done and kill_done then
      finish(fzf_rc == nil and 1 or fzf_rc)
    end
  end

  -- producer EOF: flush the pending writes, then close our end of fzf's
  -- stdin so fzf sees EOF (`--select-1` and `reload` actions rely on it)
  local function close_write_end()
    if eof and writes == 0 and fzf_in and not fzf_in:is_closing() then
      fzf_in:close()
    end
  end

  -- byte pump: forward each chunk as-is, immediately, no processing
  local function pump(err, data)
    if err or data == nil then
      eof = true
      close_handle(prod_out)
      close_write_end()
      return
    end
    if not fzf_in or fzf_in:is_closing() then return end
    local len = #data
    writes, pending = writes + 1, pending + len
    fzf_in:write(data, function(werr)
      writes, pending = writes - 1, pending - len
      -- after fzf exits the queued writes error (EPIPE/ECANCELED)
      if not werr and fzf_in and not fzf_in:is_closing() then
        if paused and pending < LOW and prod_out and not prod_out:is_closing() then
          paused = false
          prod_out:read_start(pump)
        end
        close_write_end()
      end
    end)
    if not paused and pending > HIGH and prod_out and not prod_out:is_closing() then
      paused = true
      prod_out:read_stop()
    end
  end

  -- fzf first: a spawn failure aborts before the producer is started
  local ok, spawn_err = pcall(function()
    fzf_handle = M.uv_spawn(spec.bin, {
      cwd = spec.cwd,
      args = spec.args,
      stdio = { fzf_in or spec.stdin or 0, out_fd, stderr_fd },
      env = spec.env,
    }, function(rc, _)
      fzf_done, fzf_rc = true, rc
      close_handle(fzf_handle)
      if prod_out and not prod_out:is_closing() then
        prod_out:read_stop()
      end
      -- fzf exited while the producer may still be running (e.g. the user
      -- aborted a `ping`-like producer): luv's `kill` is not a tree kill
      -- on Windows, `taskkill /T /F` reaps the launcher and its children
      if not prod_done and prod_pid then
        kill_done = false
        local kok = pcall(function()
          if not kill_null then kill_null = assert(uv.new_pipe(false)) end
          kill_handle = M.uv_spawn("taskkill.exe", {
            args = { "/PID", tostring(prod_pid), "/T", "/F" },
            stdio = { nil, kill_null, kill_null },
          }, function()
            kill_done = true
            close_handle(kill_handle)
            maybe_finish()
          end)
          close_handle(kill_null)
          kill_null = nil
        end)
        if not kok then kill_done = true end
      end
      maybe_finish()
    end)
  end)
  if not ok or not fzf_handle then
    io.stderr:write(
      ("[fzf-lua] failed to spawn '%s': %s\n"):format(spec.bin, tostring(spawn_err)))
    finish(1)
    return false
  end

  if item then
    local pok = pcall(function()
      prod_handle, prod_pid = M.uv_spawn("cmd.exe", {
        -- pass the producer command verbatim: it is a raw `cmd /c` line,
        -- libuv's quoting would corrupt it (same as the old launcher)
        args = { "/d", "/e:off", "/f:off", "/v:off", "/c", item },
        verbatim = true,
        cwd = spec.cwd,
        env = spec.env,
        stdio = { nil, prod_out, stderr_fd },
      }, function(_, _)
        prod_done = true
        close_handle(prod_handle)
        maybe_finish()
      end)
    end)
    if pok and prod_handle and prod_out then
      prod_out:read_start(pump)
    else
      -- producer failed to spawn (e.g. malformed command): close the write
      -- end so fzf still terminates (empty list, `shell_nop` semantics)
      prod_done, eof = true, true
      close_write_end()
      maybe_finish()
    end
  end
  return true
end


---@class fzf-lua.SpawnOpts
---@field cwd? string
---@field cmd string|table
---@field env? table
---@field cb_finish fun(code: integer, sig: integer, from: string, pid: integer)
---@field cb_write fun(data: string, cb: fun(err: any): nil): nil
---@field cb_write_lines? fun(lines: string[])
---@field cb_err fun(data: string)
---@field cb_pid? fun(pid: integer)
---@field fn_transform? fun()
---@field EOL? string
---@field EOL_data? string
---@field process1? boolean
---@field profiler? boolean
---@field use_queue? boolean

---@param opts fzf-lua.SpawnOpts
---@param fn_transform function?
---@param fn_done function?
---@return uv.uv_process_t proc
---@return integer         pid
M.spawn = function(opts, fn_transform, fn_done)
  local EOL = opts.EOL or "\n"
  local EOL_data = type(opts.cmd) == "string"
      -- fd -0|--print0
      -- rg -0|--null
      -- grep -Z|--null
      -- find . -print0
      and (opts.cmd:match("%s%-0")
        or opts.cmd:match("%s%-?%-print0") -- -print0|--print0
        or opts.cmd:match("%s%-%-null")
        or opts.cmd:match("%s%-Z"))
      and "\0" or "\n"
  local output_pipe = assert(uv.new_pipe(false))
  local error_pipe = assert(uv.new_pipe(false))
  local write_cb_count, read_cb_count = 0, 0
  local prev_line_content ---@type string?
  local handle, pid ---@type uv.uv_process_t, integer
  local co = coroutine.running()
  ---@cast co thread
  local queue = require("fzf-lua.lib.queue").new()
  local work_ctx

  -- Disable queue if running headless due to
  -- "Attempt to yield across a C-call boundary"
  opts.use_queue = not _G._fzf_lua_is_headless and opts.use_queue

  -- cb_write_lines trumps cb_write
  ---@diagnostic disable-next-line: assign-type-mismatch
  if opts.cb_write_lines then opts.cb_write = opts.cb_write_lines end

  local can_finish = function()
    if not output_pipe:is_active() -- EOF signalled or process is aborting
        and read_cb_count == 0     -- no outstanding read_cb data processing
        and write_cb_count == 0    -- no outstanding write callbacks
    then
      return true
    end
  end

  ---@diagnostic disable-next-line: redefined-local
  local finish = function(code, sig, from, pid)
    -- Uncomment to debug pipe closure timing issues (#1521)
    -- output_pipe:close(function() print("closed o") end)
    -- error_pipe:close(function() print("closed e") end)
    if not output_pipe:is_closing() then output_pipe:close() end
    if not error_pipe:is_closing() then error_pipe:close() end
    if opts.cb_finish then
      opts.cb_finish(code, sig, from, pid)
    end
    queue:clear()
    if not handle:is_closing() then
      handle:kill("sigterm")
      vim.defer_fn(function()
        if not handle:is_closing() then
          handle:kill("sigkill")
        end
      end, 200)
    end
    -- NO LONGER USED, was coroutinify callback
    if fn_done then fn_done(pid) end
  end

  -- https://github.com/luvit/luv/blob/master/docs.md
  -- uv.spawn returns tuple: handle, pid
  local shell = _is_win and "cmd.exe" or "sh"
  local args = _is_win and { "/d", "/e:off", "/f:off", "/v:on", "/c" } or { "-c" }
  if type(opts.cmd) == "table" then
    if _is_win then
      vim.list_extend(args, opts.cmd)
    else
      table.insert(args, table.concat(opts.cmd, " "))
    end
  else
    table.insert(args, tostring(opts.cmd))
  end

  handle, pid = M.uv_spawn(shell, {
    args = args,
    stdio = { nil, output_pipe, error_pipe },
    cwd = opts.cwd,
    env = opts.env,
    verbatim = _is_win,
  }, function(code, signal)
    if can_finish() or code ~= 0 then
      -- Do not call `:read_stop` or `:close` here as we may have data
      -- reads outstanding on slower Windows machines (#1521), only call
      -- `finish` if all our `uv.write` calls are completed and the pipe
      -- is no longer active (i.e. no more read cb's expected)
      finish(code, signal, "[on_exit]", pid)
    end
    handle:close()
  end)

  -- save current process pid
  if opts.cb_pid then opts.cb_pid(pid) end

  local function write_cb(data)
    write_cb_count = write_cb_count + 1
    ---@diagnostic disable-next-line: need-check-nil
    opts.cb_write(data, function(err)
      write_cb_count = write_cb_count - 1
      if err then
        -- can fail with premature process kill
        -- assert(not err)
        finish(130, 0, "[write_cb: err]", pid)
      elseif can_finish() then
        -- on_exit callback already called and did not close the
        -- pipe due to write_cb_count>0, since this is the last
        -- call we can close the fzf pipe
        finish(0, 0, "[write_cb: finish]", pid)
      end
    end)
  end

  ---@param data string data stream
  ---@param prev string? rest of line from previous call
  ---@param trans function? line transformation function
  ---@return table, string? line array, partial last line (no EOL)
  local function split_lines(data, prev, trans)
    local ret = {}
    local start_idx = 1
    repeat
      local nl_idx = data:find(EOL_data, start_idx, true)
      if nl_idx then
        local cr = data:byte(nl_idx - 1, nl_idx - 1) == 13 -- \r
        local line = data:sub(start_idx, nl_idx - (cr and 2 or 1))
        if prev then
          line = prev .. line
          prev = nil
        end
        if trans then line = trans(line) end
        if line then table.insert(ret, line) end
        start_idx = nl_idx + 1
      else
        -- assert(start_idx <= #data)
        if prev and #prev > 4096 then
          -- chunk size is 64K, limit previous line length to 4K
          -- max line length is therefor 4K + 64K (leftover + full chunk)
          -- without this we can memory fault on extremely long lines (#185)
          -- or have UI freezes (#211)
          prev = prev:sub(1, 4096)
        end
        prev = (prev or "") .. data:sub(start_idx)
      end
    until not nl_idx or start_idx > #data
    return ret, prev
  end

  --- Called with nil to process the leftover data
  ---@param data string?
  local process_data = function(data)
    if not data and prev_line_content then
      data = prev_line_content .. EOL
      prev_line_content = nil
    end
    if not data then
      -- NOTE: this isn't called when prev_line_content is not nil but that's
      -- not a problem as the write_cb will call finish once the callback is done
      -- since the output_pipe is already in "closing" state
      if can_finish() then
        finish(0, 0, "[EOF]", pid)
      end
      return
    end
    if not fn_transform then
      write_cb(data)
    else
      -- NOTE: cannot use due to "yield across a C-call boundary"
      -- if co and not work_ctx then
      --   work_ctx = uv.new_work(split_lines, function(lines, prev)
      --     coroutine.resume(co, lines, prev)
      --   end)
      -- end
      local nlines, lines = 0, nil
      local t_st = opts.profiler and uv.hrtime()
      if t_st then write_cb(string.format("[DEBUG] start: %.0f (ns)" .. EOL, t_st)) end
      if work_ctx then
        -- should never get here, work_ctx is never initialized
        -- code remains as a solemn reminder to my efforts of making
        -- multiprocess=false a lag free experience
        if prev_line_content then uv.queue_work(work_ctx, data, prev_line_content) end
        lines, prev_line_content = coroutine.yield()
      else
        lines, prev_line_content = split_lines(data, prev_line_content,
          -- NOTE `fn_transform=true` is used to force line split without transformation
          type(fn_transform) == "function" and fn_transform or nil)
      end
      nlines = nlines + #lines
      if #lines > 0 then
        if opts.cb_write_lines then
          write_cb(lines)
        else
          -- Testing shows better performance writing the entire table at once as opposed to
          -- calling 'write_cb' for every line after 'fn_transform', we therefore only use
          -- `process1` when using "mini.icons" as `vim.filetype.match` causes a signigicant
          -- delay and having to wait for all lines to be processed has an apparent lag
          if opts.process1 then
            vim.tbl_map(function(l) write_cb(l .. EOL) end, lines)
          else
            write_cb(table.concat(lines, EOL) .. EOL)
          end
        end
      end
      if t_st then
        local t_e = vim.uv.hrtime()
        write_cb(string.format("[DEBUG] finish:%.0f (ns) %d lines took %.0f (ms)" .. EOL,
          t_e, nlines, (t_e - t_st) / 1e6))
      end
    end
  end

  local read_cb = function(err, data)
    if err then
      finish(130, 0, "[read_cb: err]", pid)
      return
    end
    if not data then
      -- EOF signalled, we can close the pipe
      output_pipe:close()
    end
    if opts.use_queue then
      if data then queue:push(data) end
      -- Either we have outstanding data enqueued or the pipe is closing
      -- due to the above `output_pipe:close`, in both cases we need to
      -- resume the dequeue loop
      coroutine.resume(co)
    else
      read_cb_count = read_cb_count + 1
      local process = function()
        read_cb_count = read_cb_count - 1
        process_data(data)
      end
      -- Schedule data processing if we're in fast event
      -- avoids "attempt to yield across C-call boundary" by using vim.schedule
      if vim.in_fast_event() then vim.schedule(process) else process() end
    end
  end

  local err_cb = function(err, data)
    if err then
      finish(130, 0, "[err_cb]", pid)
    end
    if not data then
      return
    end
    if opts.cb_err then
      opts.cb_err(data)
    else
      write_cb(data)
    end
  end

  if not handle then
    -- uv.spawn failed, error will be in 'pid'
    -- call once to output the error message
    -- and second time to signal EOF (data=nil)
    err_cb(nil, pid .. EOL)
    err_cb(pid, nil)
  else
    output_pipe:read_start(read_cb)
    error_pipe:read_start(err_cb)
  end

  if opts.use_queue then
    while not (output_pipe:is_closing() and queue:empty()) do
      if queue:empty() then
        coroutine.yield()
      else
        process_data(queue:pop())
      end
    end
    -- process the leftover line from `processs_data`
    -- will call `finish` immediately if there's no last line
    -- otherwise, finish is called in the write callback
    process_data(nil)
  end

  return handle, pid
end

-- Coroutine version of spawn so we can use queue
M.async_spawn = coroutinify(M.spawn)

---@param obj table
---@param b64? boolean
---@return string, boolean -- boolean used for ./scripts/headless_fd.sh
M.serialize = function(obj, b64)
  local str = serpent.line(obj, { name = "_", comment = false, sortkeys = false })
  str = b64 ~= false and base64.encode(str) or str
  return "return [==[" .. str .. "]==]", (b64 ~= false and true or false)
end

---@param str string
---@param b64? boolean
---@return table
M.deserialize = function(str, b64)
  local res = assert(loadstring(str))()
  if type(res) == "table" then return res --[[@as table]] end -- ./scripts/headless_fd.sh
  res = b64 ~= false and base64.decode(res) or res
  -- safe=false enable call function
  local _, obj = serpent.load(res, { safe = false })
  assert(type(obj) == "table")
  return obj
end

---@param fn_str any
---@return function?
M.load_fn = function(fn_str)
  if type(fn_str) ~= "string" then return end
  local fn_loaded = nil
  local fn = loadstring(fn_str)
  if fn then fn_loaded = fn() end
  if type(fn_loaded) ~= "function" then
    fn_loaded = nil
  end
  return fn_loaded
end

local posix_exec = function(cmd)
  if type(cmd) ~= "string" or _is_win or not pcall(require, "ffi") then return end
  require("ffi").cdef([[int execl(const char *, const char *, ...);]])
  require("ffi").C.execl("/bin/sh", "sh", "-c", cmd, nil)
end

---@param opts fzf-lua.SpawnStdioOpts
---@return uv.uv_process_t?, integer?
M.spawn_stdio = function(opts)
  -- stdin/stdout are already buffered, not stderr. This means
  -- that every character is flushed immediately which caused
  -- rendering issues on Mac (#316, #287) and Linux (#414)
  -- switch 'stderr' stream to 'line' buffering
  -- https://www.lua.org/manual/5.2/manual.html#pdf-file%3asetvbuf
  io.stderr:setvbuf "line"

  -- redirect 'stderr' to 'stdout' on Macs by default
  -- only takes effect if 'opts.stderr' was not set
  if opts.stderr_to_stdout == nil and
      uv.os_uname().sysname == "Darwin" then
    opts.stderr_to_stdout = true
  end

  -- setup global vars
  for k, v in pairs(opts.g or {}) do _G[k] = v end

  ---@diagnostic disable-next-line: undefined-field
  local EOL = _G._EOL or opts.multiline and "\0" or "\n"

  -- Requiring make_entry will create the pseudo `_G.FzfLua` global
  -- Must be called after global vars are created or devicons will
  -- err with "fzf-lua fatal: '_G._fzf_lua_server', '_G._devicons_path' both nil"
  pcall(require, "fzf-lua.make_entry")

  -- still need load_fn from str val? now deserialize do all the thing automatically
  -- or because we want to debugprint them, so we still make a string?
  local fn_transform = M.load_fn(opts.fn_transform) or opts.fn_transform
  local fn_preprocess = M.load_fn(opts.fn_preprocess) or opts.fn_preprocess
  local fn_postprocess = M.load_fn(opts.fn_postprocess) or opts.fn_postprocess

  local argv = function(i)
    local idx = tonumber(i) or #_G.arg
    local arg = _G.arg[idx]
    if opts.debug == "v" or opts.debug == 2 then
      io.stdout:write(("[DEBUG] raw_argv(%d) = %s" .. EOL):format(idx, arg))
    end
    -- TODO: maybe not needed anymore? since we're not using v:argv
    if FzfLua.utils.__IS_WINDOWS then
      arg = M.unescape_fzf(arg, FzfLua.utils.has(opts, "fzf", { 0, 52 }) and 0.52 or 0)
    end
    if opts.debug == "v" or opts.debug == 2 then
      io.stdout:write(("[DEBUG] esc_argv(%d) = %s" .. EOL):format(idx, M.shellescape(arg)))
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

  -- run the preprocessing fn
  ---@diagnostic disable-next-line: call-non-callable
  if fn_preprocess then fn_preprocess(opts) end

  ---@type fzf-lua.content|fzf-lua.shell.data2?
  local content = opts.contents
  if type(content) == "string" and content:match("%-%-color[=%s]+never") then
    -- perf: skip stripping ansi coloring in `make_file.entry`
    opts.no_ansi_colors = true
  end

  if opts.debug == "v" or opts.debug == 2 then
    for k, v in vim.spairs(opts) do
      io.stdout:write(string.format("[DEBUG] %s=%s" .. EOL, k, vim.inspect(v)))
    end
  elseif opts.debug then
    io.stdout:write("[DEBUG] [mt] " .. tostring(content) .. EOL)
  end

  local stderr, stdout = nil, nil

  local function stderr_write(msg)
    -- prioritize writing errors to stderr
    if stderr then
      stderr:write(msg)
    else
      io.stderr:write(msg)
    end
  end

  -- Exit the fzf-lua spawn process; `vim.cmd.cquit` is typed `never` in
  -- emmylua's stubs which makes `exit` itself uncallable from a `local
  -- function` declaration, so wrap it as an annotated module-level alias.
  ---@type fun(exit_code?: integer, msg?: string)
  local exit = function(exit_code, msg)
    if msg then stderr_write(msg) end
    vim.cmd.cquit({ count = exit_code })
  end

  local function pipe_open(pipename)
    if not pipename then return end
    local fd = assert(uv.fs_open(pipename, "w", -1))
    if type(fd) ~= "number" then
      exit(1, ("error opening '%s': %s" .. EOL):format(pipename, fd))
    end
    local pipe = assert(uv.new_pipe(false))
    pipe:open(fd)
    return pipe
  end

  local function pipe_close(pipe)
    if pipe and not pipe:is_closing() then
      pipe:close()
    end
  end

  local function pipe_write(pipe, data, cb)
    if not pipe or pipe:is_closing() then return end
    pipe:write(data,
      function(err)
        -- if the user cancels the call prematurely with
        -- <C-c>, err will be either EPIPE or ECANCELED
        -- don't really need to do anything since the
        -- processes will be killed anyways with os.exit()
        if err then
          stderr_write(("pipe:write error: %s" .. EOL):format(err))
        end
        if cb then cb(err) end
      end)
  end

  if type(opts.stderr) == "string" then
    stderr = pipe_open(opts.stderr)
  end
  if type(opts.stdout) == "string" then
    stdout = pipe_open(opts.stdout)
  end

  local on_finish = function(code)
    pipe_close(stdout)
    pipe_close(stderr)
    if vim.in_fast_event() then
      vim.schedule(function()
        ---@diagnostic disable-next-line: call-non-callable
        if fn_postprocess then fn_postprocess(opts) end
        ---@diagnostic disable-next-line: call-non-callable
        exit(code)
      end)
    else
      ---@diagnostic disable-next-line: call-non-callable
      if fn_postprocess then fn_postprocess(opts) end
      exit(code)
    end
  end

  local on_write = function(data, cb)
    if stdout then
      pipe_write(stdout, data, cb)
    else
      -- on success: rc=true, err=nil
      -- on failure: rc=nil, err="Broken pipe"
      -- cb with an err ends the process
      local rc, err = io.stdout:write(data)
      if not rc then
        stderr_write(("io.stdout:write error: %s" .. EOL):format(err))
        cb(err or true)
      else
        cb(nil)
      end
    end
  end

  local on_err = function(data)
    if stderr then
      pipe_write(stderr, data)
    elseif opts.stderr ~= false then
      if opts.stderr_to_stdout then
        io.stdout:write(data)
      else
        io.stderr:write(data)
      end
    end
  end

  local args = function()
    local items = vim.deepcopy(_G.arg)
    items[0] = nil
    table.remove(items, 1)
    return items
  end

  local cmd ---@type string
  if type(content) == "string" then
    cmd = content
  else
    local f = fn_transform or function(x) return x end
    ---@diagnostic disable-next-line: call-non-callable, missing-parameter
    local w = function(s) if s then io.stdout:write(f(s) .. EOL) else on_finish(0) end end
    ---@diagnostic disable-next-line: call-non-callable, missing-parameter, param-type-mismatch
    local wn = function(s) if s then return io.stdout:write(f(s)) else on_finish(0) end end
    if opts.is_live then ---@cast content fzf-lua.shell.data2
      ---@diagnostic disable-next-line: param-type-mismatch, assign-type-mismatch
      local res = content(args(), opts)
      if not res then return on_finish(0), nil end
      ---@cast res fzf-lua.shell.data2
      content = res
    end
    if type(content) == "function" then content(w, wn) end
    if type(content) == "table" then for _, v in ipairs(content) do w(v) end end
    -- Table/function content was already written to stdout above, the only
    -- content type that requires spawning a child process is a string command.
    -- Without this guard, when `fn_postprocess` is set, `on_finish` defers
    -- `os.exit` via `vim.schedule` and the code falls through to `M.spawn`
    -- which would attempt to execute the table content as a shell command,
    -- resulting in errors like "sh: 1: 1:: not found" appearing as fzf items.
    if type(content) ~= "string" then return on_finish(0), nil end ---@cast content string
    cmd = content
    if opts.debug then
      io.stdout:write(("[DEBUG] [mt] %s" .. EOL):format(content))
    end
  end

  if not fn_transform and not fn_postprocess then posix_exec(content) end

  return M.spawn({
      cwd = opts.cwd,
      cmd = cmd,
      cb_finish = on_finish,
      cb_write = on_write,
      cb_err = on_err,
      process1 = opts.process1,
      profiler = opts.profiler,
      EOL = EOL,
    },
    fn_transform and function(x)
      ---@diagnostic disable-next-line: call-non-callable
      return fn_transform(x, opts)
    end)
end


M.is_escaped = function(s, is_win)
  local m
  -- test spec override
  if is_win == nil then is_win = _is_win end
  if is_win then
    m = s:match([[^".*"$]]) or s:match([[^%^".*%^"$]])
  else
    m = s:match([[^'.*'$]]) or s:match([[^".*"$]])
  end
  return m ~= nil
end

-- our own version of vim.fn.shellescape compatible with fish shells
--   * don't double-escape '\' (#340)
--   * if possible, replace surrounding single quote with double
-- from ':help shellescape':
--    If 'shell' contains "fish" in the tail, the "\" character will
--    be escaped because in fish it is used as an escape character
--    inside single quotes.
--
-- for windows, we assume we want to keep all quotes as literals
-- to avoid the quotes being stripped when run from fzf actions
-- we therefore have to escape the quotes with backslashes and
-- for nested quotes we double the backslashes due to windows
-- quirks, further reading:
-- https://stackoverflow.com/questions/6714165/powershell-stripping-double-quotes-from-command-line-arguments
-- https://learn.microsoft.com/en-us/archive/blogs/twistylittlepassagesallalike/everyone-quotes-command-line-arguments-the-wrong-way
--
-- this function is a better fit for utils but we're
-- trying to avoid having any 'require' in this file
---@param s string
---@param win_style integer|string|boolean? force Windows escaping on posix:
---  1 = classic CommandLineToArgvW backslash escape, 2 = caret escape with
---  delayed expansion double-escape, `true`/nil (on Windows) = caret escape
---@return string
M.shellescape = function(s, win_style)
  if _is_win or win_style then
    if tonumber(win_style) == 1 then
      --
      -- "classic" CommandLineToArgvW backslash escape
      --
      s = s:gsub([[\-"]], function(x)
        -- Quotes found in string. From the above stackoverflow link:
        --
        -- (2n) + 1 backslashes followed by a quotation mark again produce n backslashes
        -- followed by a quotation mark literal ("). This does not toggle the "in quotes"
        -- mode.
        --
        -- to produce (2n)+1 backslashes we use the following `string.rep` calc:
        -- (#x-1) * 2 + 1 - (#x-1) == #x
        -- which translates to prepending the string with number of escape chars
        -- (\) equal to its own length, this in turn is an **always odd** number
        --
        -- "     ->  \"          (0->1)
        -- \"    ->  \\\"        (1->3)
        -- \\"   ->  \\\\\"      (2->5)
        -- \\\"  ->  \\\\\\\"    (3->7)
        -- \\\\" ->  \\\\\\\\\"  (4->9)
        --
        x = string.rep([[\]], #x) .. x
        return x
      end)
      s = s:gsub([[\+$]], function(x)
        -- String ends with backslashes. From the above stackoverflow link:
        --
        -- 2n backslashes followed by a quotation mark again produce n backslashes
        -- followed by a begin/end quote. This does not become part of the parsed
        -- argument but toggles the "in quotes" mode.
        --
        --   c:\foo\  -> "c:\foo\"    // WRONG
        --   c:\foo\  -> "c:\foo\\"   // RIGHT
        --   c:\foo\\ -> "c:\foo\\"   // WRONG
        --   c:\foo\\ -> "c:\foo\\\\" // RIGHT
        --
        -- To produce equal number of backslashes without converting the ending quote
        -- to a quote literal, double the backslashes (2n), **always even** number
        x = string.rep([[\]], #x * 2)
        return x
      end)
      return [["]] .. s .. [["]]
    else
      --
      -- CMD.exe caret+backslash escape, after lot of trial and error
      -- this seems to be the winning logic, a combination of v1 above
      -- and caret escaping special chars
      --
      -- The logic is as follows
      --   (1) all escaped quotes end up the same \^"
      --   (1) if quote was prepended with backslash or backslash+caret
      --       the resulting number of backslashes will be 2n + 1
      --   (2) if caret exists between the backslash/quote combo, move it
      --       before the backslash(s)
      --   (4) all cmd special chars are escaped with ^
      --
      --   NOTE: explore "tests/libuv_spec.lua" to see examples of quoted
      --      combinations and their expecetd results
      --
      local escape_inner = function(inner)
        inner = inner:gsub([[\-%^?"]], function(x)
          -- although we currently only transfer 1 caret, the below
          -- can handle any number of carets with the regex [[\-%^-"]]
          local carets = x:match("%^+") or ""
          x = carets .. string.rep([[\]], #x - #(carets)) .. x:gsub("%^+", "")
          return x
        end)
        -- escape all windows metacharacters but quotes
        -- ( ) % ! ^ < > & | ; "
        -- TODO: should % be escaped with ^ or %?
        inner = inner:gsub('[%(%)%%!%^<>&|;%s"]', function(x)
          return "^" .. x
        end)
        -- escape backslashes at the end of the string
        inner = inner:gsub([[\+$]], function(x)
          x = string.rep([[\]], #x * 2)
          return x
        end)
        return inner
      end
      s = escape_inner(s)
      if s:match("!") and tonumber(win_style) == 2 then
        --
        -- https://ss64.com/nt/syntax-esc.html
        -- This changes slightly if you are running with DelayedExpansion of variables:
        -- if any part of the command line includes an '!' then CMD will escape a second
        -- time, so ^^^^ will become ^
        --
        -- NOTE: we only do this on demand (currently only used in "libuv_spec.lua")
        --
        s = escape_inner(s)
      end
      s = [[^"]] .. s .. [[^"]]
      return s
    end
  end
  local shell = vim.o.shell
  if not shell or not shell:match("fish$") then
    return vim.fn.shellescape(s)
  else
    local ret = nil
    vim.o.shell = "sh"
    if s and not s:match([["]]) and not s:match([[\]]) then
      -- if the original string does not contain double quotes,
      -- replace surrounding single quote with double quotes,
      -- temporarily replace all single quotes with double
      -- quotes and restore after the call to shellescape.
      -- NOTE: we use '({s:gsub(...)})[1]' to extract the
      -- modified string without the multival # of changes,
      -- otherwise the number will be sent to shellescape
      -- as {special}, triggering an escape for ! % and #
      ret = vim.fn.shellescape(({ s:gsub([[']], [["]]) })[1])
      ret = [["]] .. ret:gsub([["]], [[']]):sub(2, #ret - 1) .. [["]]
    else
      ret = vim.fn.shellescape(s)
    end
    vim.o.shell = shell
    return ret
  end
end

-- Parse a `cmd.exe` command line fragment into argv values, exactly as
-- `cmd.exe` + the Win32 argv parser (Go runtime; fzf is a Go binary) would
-- deliver them. User provided argument strings (`fzf_args`, `fzf_cli_args`,
-- etc.) are written for the platform shell: on Windows they are cmd.exe
-- fragments, typically pre-escaped with `shellescape` (caret style). The
-- Windows direct spawn route (`libuv.win_spawn`) passes the raw argv to
-- `uv.spawn` with no shell, so this reverses the parsing passes:
--   1. `%NAME%` expansion (cmd.exe semantics; differs from batch scripts):
--      a defined name (case-insensitive) expands to its value, which is
--      not rescanned; an undefined name is left as text and the scan
--      resumes one char later, so a later `%` may still pair (`%%TEMP%%`
--      -> `%TEMP%`). A `shellescape`-escaped value carries a caret inside
--      the scanned name (`^%NAME^%`), never matches and survives for the
--      caret pass below. Not modelled: `%VAR:~x,y%` substitutions and
--      cmd's pseudo vars (`%CD%` etc.); verified against `cmd.exe`
--   2. cmd.exe caret consumption: `^X` -> `X` (and thus `^^` -> `^`); a
--      caret is only special outside of double quotes, inside quotes it is
--      literal and an unescaped `"` toggles the quoted state (this is what
--      makes the `^"...^"` shellescape form safe: the escaped surrounding
--      quotes are emitted literally and never enter the quoted state, so
--      the inner caret escapes still apply)
--   3. Win32 argv parsing as implemented by the Go runtime
--      (`os/exec_windows.go`; fzf is a Go binary): quotes toggle and are
--      dropped, a doubled `""` inside a quoted section is one literal quote
--      ("Prior to 2008" rule; the pair is consumed and the quote state
--      toggles once), backslash runs before quotes collapse (`2n` backslashes
--      followed by a quote -> `n` backslashes + toggle quote mode, `2n+1` ->
--      `n` backslashes + literal quote), unquoted whitespace splits args
---@param s string cmd.exe command line fragment
---@param env table<string,string>? variable environment (defaults to
---  `vim.fn.environ()`, the environment `cmd.exe` would be spawned with)
---@return string[] argv
M.cmd_argv = function(s, env)
  if not s or s == "" then return {} end
  -- (1) expand defined `%NAME%` variables (`cmd.exe` performs this before
  -- everything else; env lookups are case-insensitive on Windows)
  env = env or vim.fn.environ()
  local lookup = function(name)
    if name == "" then return nil end
    if env[name] ~= nil then return env[name] end
    name = name:lower()
    for k, v in pairs(env) do
      if k:lower() == name then return v end
    end
    return nil
  end
  do
    local out, i, slen = {}, 1, #s
    while i <= slen do
      if s:sub(i, i) == "%" then
        local j = s:find("%", i + 1, true)
        local val = j and lookup(s:sub(i + 1, j - 1)) or nil
        if j and val then
          out[#out + 1] = val
          i = j + 1
        elseif j then
          -- undefined: leave this `%` for the next scan step (the closing
          -- `%` can pair with a later one, as `cmd.exe` does with `%%X%%`)
          out[#out + 1] = "%"
          i = i + 1
        else
          out[#out + 1] = s:sub(i)
          i = slen + 1
        end
      else
        out[#out + 1] = s:sub(i, i)
        i = i + 1
      end
    end
    s = table.concat(out)
  end
  -- (2) consume cmd.exe caret escapes; a caret is only special outside of
  -- double quotes. An unescaped `"` toggles the quoted state, while a caret
  -- escaped `^"` is emitted literally and does not toggle it (the emitted
  -- quote is re-interpreted by the argv pass below)
  local parts = {}
  local i, len = 1, #s
  local quoted = false
  while i <= len do
    local c = s:sub(i, i)
    if c == "^" and not quoted then
      if i == len then break end -- dangling caret is dropped by cmd.exe
      parts[#parts + 1] = s:sub(i + 1, i + 1)
      i = i + 2
    else
      if c == [["]] then quoted = not quoted end
      parts[#parts + 1] = c
      i = i + 1
    end
  end
  s = table.concat(parts)
  -- (3) parse the unescaped command line into argv values
  local argv = {}
  local j = 1
  len = #s
  while j <= len do
    local sp = s:sub(j, j)
    if sp == " " or sp == "\t" then
      j = j + 1
    else
      local buf, in_quotes = {}, false
      while j <= len do
        local c = s:sub(j, j)
        if c == "\\" then
          local k = j
          while k <= len and s:sub(k, k) == "\\" do k = k + 1 end
          local nback = k - j
          if k <= len and s:sub(k, k) == '"' then
            buf[#buf + 1] = string.rep("\\", math.floor(nback / 2))
            if nback % 2 == 1 then
              buf[#buf + 1] = '"'
              j = k + 1
            else
              -- even run: emit backslashes, let the quote branch below apply
              -- the doubling rule / toggle for the quote itself
              j = k
            end
          else
            buf[#buf + 1] = string.rep("\\", nback)
            j = k
          end
        elseif c == '"' then
          -- Go runtime `os/exec_windows.go`: a `""` inside a quoted section
          -- is one literal quote ("Prior to 2008" rule); the pair is consumed
          -- and the quote state toggles once (matches `fzf.exe` via `cmd.exe`)
          if in_quotes and s:sub(j + 1, j + 1) == '"' then
            buf[#buf + 1] = '"'
            j = j + 2
          else
            j = j + 1
          end
          in_quotes = not in_quotes
        elseif not in_quotes and (c == " " or c == "\t") then
          break
        else
          buf[#buf + 1] = c
          j = j + 1
        end
      end
      argv[#argv + 1] = table.concat(buf)
    end
  end
  return argv
end

---@class fzf-lua.CliSegment
---@field text string    -- raw (unescaped) text
---@field escape boolean -- true = escape this text for the target shell

-- One argv element is a list of segments (usually 1; 2 for a fused "flag=value"
-- or "--bind=<value>" string where the flag prefix is literal and the value is
-- escaped). This lets a single final pass escape only the value segments,
-- per target shell, without double-escaping literal flag text.
---@alias fzf-lua.CliElement fzf-lua.CliSegment[]

-- Escape a list of CLI elements for the given shell, re-fusing each element's
-- segments into a single string. Both shells reuse `shellescape` (`cmd` uses
-- the caret/win_style variant). Literal segments (`escape=false`) are emitted
-- verbatim.
---@param elements fzf-lua.CliElement[]
---@param shell "posix"|"cmd"
---@param win_style integer|string|boolean? forwarded to shellescape for "cmd"
---@return string[]
M.escape_cli = function(elements, shell, win_style)
  local escapefn = function(s)
    return M.shellescape(s, shell == "cmd" and win_style or nil)
  end
  local argv = {}
  for _, elem in ipairs(elements) do
    local buf = {}
    for _, seg in ipairs(elem) do
      table.insert(buf, seg.escape and escapefn(seg.text) or seg.text)
    end
    table.insert(argv, table.concat(buf))
  end
  return argv
end

-- Marker for `_fzf_cli_args` entries that carry a raw (unescaped) value
-- alongside the escaped string form. `build_fzf_cli` consumes these to emit
-- BOTH the legacy escaped string (for cmd/posix, byte-identical) and a raw
-- CliElement segment list -- `fzf.raw_fzf` rebuilds the raw argv from the
-- segments for the Windows direct spawn (`libuv.win_spawn`, no shell and no
-- escaping; shares `fzf-tmux` and the CLI launcher equally). `prefix` is the
-- literal, never-escaped flag text (e.g. "--bind=" or "--interactive --cmd ").
---@param prefix string literal flag prefix (e.g. "--bind=")
---@param value string raw (unescaped) value
---@return table marker
M.cli_raw_arg = function(prefix, value)
  return { __raw_cli = true, prefix = prefix, value = value }
end

-- Windows fzf oddities, fzf's {q} will send escaped blackslahes,
-- but only when the backslash prefixes another character which
-- isn't a backslash, test with:
-- fzf --disabled --height 30% --preview-window up --preview "echo {q}"
M.unescape_fzf = function(s, fzf_version, is_win)
  if is_win == nil then is_win = _is_win end
  if not is_win then return s end
  if tonumber(fzf_version) and tonumber(fzf_version) >= 0.52 then return s end
  local ret = s:gsub("\\+[^\\]", function(x)
    local bslash_num = #x:match([[\+]])
    return string.rep([[\]],
      bslash_num == 1 and bslash_num or math.floor(bslash_num / 2)) .. x:sub(-1)
  end)
  return ret
end

-- with live_grep, we use a modified "reload" command as our
-- FZF_DEFAULT_COMMAND and due to the above oddity with fzf
-- doing weird extra escaping with {q},  we use this to simulate
-- {q} being sent via the reload action as the initial command
-- TODO: better solution for these stupid hacks (upstream issues?)
M.escape_fzf = function(s, fzf_version, is_win)
  if is_win == nil then is_win = _is_win end
  if not is_win then return s end
  if tonumber(fzf_version) and tonumber(fzf_version) >= 0.52 then return s end
  local ret = s:gsub("\\+[^\\]", function(x)
    local bslash_num = #x:match([[\+]])
    return string.rep([[\]], bslash_num * 2) .. x:sub(-1)
  end)
  return ret
end

-- `vim.fn.escape`
-- (1) On *NIX: double the backslashes as they will be reduced by expand
-- (2) ... other issues we will surely find with special chars
M.expand = function(s)
  if not _is_win then
    s = s:gsub([[\]], [[\\]])
  end
  return vim.fn.expand(s)
end

return M
