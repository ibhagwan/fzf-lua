---@diagnostic disable-next-line: deprecated
local api, uv, fn = vim.api, vim.uv or vim.loop, vim.fn
---@module 'ffi'?
local ffi = vim.F.npcall(require, "ffi")

pcall(function()
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
  os.execute(shell_cmd)
  os.exit(0)
end

local function posix_exec(cmd, ...)
  local _is_win = fn.has("win32") == 1 or fn.has("win64") == 1
  if type(cmd) ~= "string" or _is_win or not ffi then return end
  if not isatty(io.stdout) then return fork(cmd, ...) end
  local args = { ... }
  -- NOTE: must add NULL to mark end of the vararg
  table.insert(args, string.byte("\0"))
  ffi.C.execl(cmd, cmd, unpack(args))
  -- if `execl` succeeds we should never get here
  error(string.format([[execl("%s",...) failed with error %d]], cmd, ffi.errno()))
end

_G.fzf_tty_get_width = function()
  if not ffi then return (assert(uv.new_tty(0, false)):get_winsize()) end
  local TIOCGWINSZ = 0x5413
  ---@diagnostic disable-next-line: assign-type-mismatch
  local ws = ffi.new("struct winsize[1]") ---@type [{ ws_row: integer, ws_col: integer }]
  local ret = ffi.C.ioctl(0, TIOCGWINSZ, ws)
  ---@diagnostic disable-next-line: undefined-field
  if ret == 0 then return ws[0].ws_col end
end

-- https://github.com/libuv/libuv/blob/04fc1580d48c1f7aa339b6ccf91f1f815bc08b45/src/unix/core.c#L800
local enable_stdio_inheritance = function()
  local function clear_cloexec(fd)
    local F_SETFD = 2
    local EINTR = 4
    local res
    repeat
      res = ffi.C.fcntl(fd, F_SETFD, 1)
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
        if ffi and #entries == 1 then
          local lnum = entries[1].line > 0 and entries[1].line or nil
          local col = entries[1].col > 0 and entries[1].col or nil
          posix_exec(fn.exepath("nvim"), entries[1].path,
            lnum and ("+" .. entries[1].line) or nil,
            col and ("+norm! %s|"):format(col) or nil)
        elseif ffi and #entries > 1 then
          local qf_items = {}
          for _, e in ipairs(entries) do
            local text = e.stripped:match(":%d+:%d?%d?%d?%d?:?(.*)$") or ""
            table.insert(qf_items, {
              filename = e.path,
              lnum = math.max(1, e.line or 1),
              col = math.max(1, e.col or 1),
              text = text,
            })
          end
          local qf_str = vim.inspect(qf_items):gsub("\n%s*", " ")
          posix_exec(fn.exepath("nvim"), "-c", string.format(
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
        assert(s[1])
        local remote = s[1]:match("%((.-)%)")
        for _, chan in ipairs(api.nvim_list_chans()) do
          if chan.stream ~= "stderr" then
            fn.chanclose(chan.id)
          end
        end
        for _, pid in ipairs(api.nvim_get_proc_children(fn.getpid())) do
          vim.uv.kill(pid, vim.uv.constants.SIGTERM)
        end
        enable_stdio_inheritance()
        posix_exec(fn.exepath("nvim"), "--remote-ui", "--server", remote)
      end
    }
  }
}
