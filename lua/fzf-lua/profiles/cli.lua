local NVIM_BIN = os.getenv("FZF_LUA_NVIM_BIN") or vim.v.progpath
local NVIM_RUNTIME = os.getenv("FZF_LUA_NVIM_RUNTIME") or os.getenv("VIMRUNTIME")
if NVIM_RUNTIME then vim.env.VIMRUNTIME = NVIM_RUNTIME end

---@diagnostic disable-next-line: deprecated
local api, uv, fn = vim.api, vim.uv or vim.loop, vim.fn
local _is_win = fn.has("win32") == 1 or fn.has("win64") == 1
-- POSIX-only ffi: `ioctl`, `fcntl`, `fork`, `execl`, etc. do not exist on
-- Windows (calling them errors with "cannot resolve symbol"). Keep `ffi`
-- nil on Windows so all helpers below take their portable fallbacks.
local ffi
if not _is_win and package.preload.ffi then
  ffi = package.preload.ffi()
end

---@diagnostic disable-next-line: call-non-callable, need-check-nil
pcall(function()
  ---@diagnostic disable-next-line: call-non-callable, need-check-nil
  ffi.cdef [[
    struct winsize {
      unsigned short ws_row;
      unsigned short ws_col;
      unsigned short ws_xpixel;
      unsigned short ws_ypixel;
    };
    int ioctl(int fd, unsigned long request, ...);
    int fcntl(int fd, int cmd, ...);
    int execl(const char *, const char *, ...);
    int fork(void);
    int isatty(int fd);
    int fileno(void *stream);
    void _exit(int status);
  ]]
end)

local function quit() vim.cmd.quit() end

local function parse_entries(s, o)
  return vim.tbl_map(function(e)
    e = FzfLua.path.entry_to_file(e --[[@as string]], o)
    e.path = FzfLua.path.relative_to(assert(e.path), FzfLua.utils.cwd())
    return e
  end, s)
end

local function isatty(file)
  if not ffi then return false end
  local fd = ffi.C.fileno(file)
  return ffi.C.isatty(fd) ~= 0
end

local function fork(cmd, ...)
  if not ffi then return false end
  local pid = ffi.C.fork()
  if pid < 0 then return end -- fork failed
  if pid > 0 then return end -- parent process, do nothing
  -- pid == 0, child process, build the shell command
  -- tiny delay to let parent (fzf-lua) exit
  -- then exec nvim conneced to /dev/tty
  local shell_cmd = string.format(
    "sleep 0.05; %s %s </dev/tty >/dev/tty 2>/dev/tty", cmd,
    table.concat(vim.tbl_map(function(x) return FzfLua.libuv.shellescape(x) end, { ... }), " ")
  )
  -- Replace the post-fork child with `/bin/sh` immediately: continuing to
  -- run Neovim code (and especially Neovim's teardown via `os.exit()`) on
  -- the libuv state copied by `fork()` is undefined without
  -- `uv_loop_fork()` and can leave a 100%-CPU spinning process behind
  -- (observed on macOS with nvim 0.13-dev, #2823). `os.execute()` uses
  -- `/bin/sh -c` as well, so this is behavior-preserving.
  ---@diagnostic disable-next-line: call-non-callable, need-check-nil
  ffi.C.execl("/bin/sh", "sh", "-c", shell_cmd, nil)
  -- `execl` only returns on failure, exit raw (no atexit handlers/Lua GC)
  ---@diagnostic disable-next-line: call-non-callable, need-check-nil
  ffi.C._exit(127)
end

local function posix_exec(cmd, ...)
  if type(cmd) ~= "string" or _is_win or not ffi then return end
  if not isatty(io.stdout) then return fork(cmd, ...) end
  local args = { ... }
  -- NOTE: must add NULL to mark end of the vararg
  table.insert(args, string.byte("\0"))
  ffi.C.execl(cmd, cmd, unpack(args))
  -- if `execl` succeeds we should never get here
  ---@diagnostic disable-next-line: undefined-field
  error(string.format([[execl("%s",...) failed with error %d]], cmd, ffi.errno()))
end

-- Windows replacement for `posix_exec`: Windows has no `fork`/`execl`, so
-- start the new nvim as a child on the same console (inherited stdio) and
-- wait for it to exit before returning; quitting first would kill the
-- child since Neovim terminates its spawned children on exit. The caller
-- then quits the headless parent (same-window takeover like `execl`).
-- Unlike the `cmd.exe /c` launcher the binary starts directly (no shell),
-- so a plain argv list with libuv's default quoting is correct, even with
-- spaces or quotes in paths. Optional trailing args may be nil (no lnum
-- or col) and are filtered out since `uv.spawn` needs a dense argv.
-- Spawn failures are reported via `utils.warn` and returned as `false`; the
-- wrapper never raises, so callers must check the return and skip their
-- takeover `quit()` when the launch failed, otherwise the picker exits
-- without anything taking the console over.
-- When the parent's stdout is not a console (e.g. PowerShell captures the
-- picker output through a pipe, as the shell widgets do), `{ 0, 1, 2 }`
-- would give the child a stdout it cannot render a TUI on and the CLI
-- would hang waiting for it to exit. stdin/stderr usually remain attached
-- to the console in that case, so inherit stderr for both. When stderr is
-- piped as well (PowerShell's PSReadLine key handler captures both), no
-- console handle is left to inherit at all: reopen `CONIN$`/`CONOUT$` as
-- inheritable CRT fds and pass those to the child.
local function win_stdio()
  local okout, hout = pcall(uv.guess_handle, 1)
  if okout and hout == "tty" then return { 0, 1, 2 } end
  local okerr, herr = pcall(uv.guess_handle, 2)
  if okerr and herr == "tty" then return { 0, 2, 2 } end
  return FzfLua.libuv.win_console_stdio() or { 0, 1, 2 }
end

---@return boolean success
local function win_exec(cmd, ...)
  if type(cmd) ~= "string" or not _is_win then return false end
  local args = vim.tbl_filter(function(a) return a ~= nil end, { ... })
  local done = false
  local stdio = win_stdio()
  -- libuv (<= 1.52) leaks every inheritable handle of this process into the
  -- child (`CreateProcess(bInheritHandles=TRUE)`, no handle list), even the
  -- ones not part of `stdio`. When the shell integration captures the
  -- picker output through pipes, the spawned nvim inherits them and the
  -- `--embed` server left running by a later `:detach` keeps the pipes'
  -- write end open forever, hanging the shell's pipeline reader. Hide the
  -- unused stdio fds for the duration of the spawn.
  local restore = FzfLua.libuv.win_stdio_no_inherit(stdio)
  local ok, err = pcall(FzfLua.libuv.uv_spawn, cmd, {
      args = args,
      stdio = stdio,
    },
    function() done = true end)
  if restore then restore() end
  if not ok then
    -- a non-throwing report: `utils.error` re-raises ERROR notifies when the
    -- CLI runs headless (see `utils.notify`), which would abort the action
    -- instead of letting the caller react to the failed launch
    FzfLua.utils.warn("failed to launch %s: %s", cmd, err)
    return false
  end
  vim.wait(2147483647, function() return done end)
  return true
end

_G.fzf_tty_get_width = function()
  if _is_win or not ffi then
    -- Windows (or no ffi): `ioctl(TIOCGWINSZ)` does not exist. Try libuv
    -- tty first, then $COLUMNS, then `vim.o.columns` (80 in headless).
    -- Return nil only if nothing yields a usable width so callers can
    -- fall back to their default layout.
    local ok, tty = pcall(uv.new_tty, 0, false)
    if ok and tty then
      local ok2, w = pcall(function() return tty:get_winsize() end)
      pcall(function() tty:close() end)
      if ok2 and type(w) == "number" and w > 0 then return w end
    end
    local cols = tonumber(os.getenv("COLUMNS"))
    if cols and cols > 0 then return cols end
    if vim.o.columns and vim.o.columns > 0 then return vim.o.columns end
    return nil
  end
  local TIOCGWINSZ = 0x5413
  ---@diagnostic disable-next-line: assign-type-mismatch
  local ws = ffi.new("struct winsize[1]") ---@type [{ ws_row: integer, ws_col: integer }]
  local ret = ffi.C.ioctl(0, TIOCGWINSZ, ws)
  ---@diagnostic disable-next-line: undefined-field
  if ret == 0 then return ws[0].ws_col end
end

-- https://github.com/libuv/libuv/blob/04fc1580d48c1f7aa339b6ccf91f1f815bc08b45/src/unix/core.c#L800
local enable_stdio_inheritance = function()
  -- No-op on Windows (no `fcntl`/CLOEXEC): `uv.spawn` stdio inheritance
  -- is handled by libuv/Neovim, and `posix_exec` is a no-op on Windows.
  if _is_win or not ffi then return end
  local function clear_cloexec(fd)
    local F_SETFD = 2
    local EINTR = 4
    local res
    repeat
      ---@diagnostic disable-next-line: need-check-nil
      res = ffi.C.fcntl(fd, F_SETFD, 1)
      ---@diagnostic disable-next-line: need-check-nil
    until not (res == -1 and ffi.errno() == EINTR)
    return res ~= -1
  end
  for i = 0, 15 do
    if not clear_cloexec(i) then break end
  end
end

local HAS_TMUX = os.getenv("TMUX")

return {
  -- always use fzf-tmux profile for fzf native border labels
  -- nullify "--tmux" in `fzf_opts` if tmux isn't detected
  { "fzf-tmux" },
  desc = "run in shell cmdline",
  -- NOTE: on Windows pipe items into fzf (`(cmd) | fzf`) instead of
  -- $FZF_DEFAULT_COMMAND: fzf only honors the env when stdin is a tty and
  -- headless-spawned fzf isn't (IsTty()=false), so it ignores the env and
  -- blocks on stdin EOF forever (same reason tests force `pipe_cmd`).
  -- `defaults` (not top-level) is what `normalize_opts` merges per-picker.
  defaults = { pipe_cmd = _is_win or nil },
  fzf_opts = {
    ["--height"] = "50%",
    ["--border"] = HAS_TMUX and "rounded" or "top",
    ["--tmux"] = (function() return not HAS_TMUX and false or nil end)(),
  },
  hls = {
    title = "diffAdd",
    title_flags = "Visual",
    header_bind = "Directory",
    header_text = "WarningMsg",
    live_prompt = "ErrorMsg",
  },
  actions = {
    files = {
      true,
      ["esc"] = quit,
      ["ctrl-c"] = quit,
      ["enter"] = function(s, o)
        local entries = parse_entries(s, o)
        vim.tbl_map(function(e) io.stdout:write(e.path .. "\n") end, entries)
        quit()
      end,
      ["ctrl-q"] = function(s, o)
        local entries = parse_entries(s, o)
        local exec = _is_win and win_exec or posix_exec
        if (_is_win or ffi) and #entries == 1 then
          local lnum = entries[1].line > 0 and entries[1].line or nil
          local col = entries[1].col > 0 and entries[1].col or nil
          exec(NVIM_BIN, entries[1].path,
            lnum and ("+" .. entries[1].line) or nil,
            col and ("+norm! %s|"):format(col) or nil)
        elseif (_is_win or ffi) and #entries > 1 then
          local qf_items = {}
          for _, e in ipairs(entries) do
            local text = e.stripped:match(":%d+:%d?%d?%d?%d?:?(.*)$") or ""
            table.insert(qf_items, {
              filename = e.path,
              lnum = e.line or 0,
              col = e.col or 0,
              valid = 1,
              text = text,
            })
          end
          local qf_str = vim.inspect(qf_items):gsub("\n%s*", " ")
          exec(NVIM_BIN, "-c", string.format(
            "lua vim.o.hidden=false; vim.fn.setqflist(%s); vim.cmd('cfirst | set hidden&')",
            qf_str))
        end
        quit()
      end,
      ["ctrl-x"] = function(_, o)
        FzfLua.builtin(vim.tbl_deep_extend("force", o.__call_opts, {
          actions = {
            enter = function(s)
              if not s[1] then quit() end
              FzfLua[s[1]](o.__call_opts)
            end
          },
        }))
      end
    }
  },
  serverlist = {
    previewer = { _ctor = require("fzf-lua.previewer").fzf.nvim_server },
    actions = {
      ["enter"] = function(s)
        local remote = FzfLua.utils.serverlist_parse_entry(assert(s[1]))
        for _, chan in ipairs(api.nvim_list_chans()) do
          if chan.stream ~= "stderr" then
            fn.chanclose(chan.id)
          end
        end
        for _, pid in ipairs(api.nvim_get_proc_children(fn.getpid())) do
          vim.uv.kill(pid, vim.uv.constants.SIGTERM)
        end
        enable_stdio_inheritance()
        if _is_win then
          -- no `execl` replacement on Windows: `win_exec` returns and the
          -- picker must quit explicitly to hand the console over; a failed
          -- launch (reported by `win_exec`) keeps this picker alive
          if win_exec(NVIM_BIN, "--remote-ui", "--server", remote) then
            quit()
          end
        else
          posix_exec(NVIM_BIN, "--remote-ui", "--server", remote)
        end
      end
    }
  }
}
