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
    int execl(const char *, const char *, ...);
    int close(int fd);
    int openpty(int *amaster, int *aslave, char *name, void *termp, const struct winsize *winp);
  ]]
end)

local function quit() vim.cmd.quit() end

local function parse_entries(s, o)
  return vim.tbl_map(function(e)
    e = FzfLua.path.entry_to_file(e --[[@as string]], o)
    e.path = FzfLua.path.relative_to(assert(e.path), vim.uv.cwd())
    return e
  end, s)
end

local function posix_exec(cmd, ...)
  local _is_win = fn.has("win32") == 1 or fn.has("win64") == 1
  if type(cmd) ~= "string" or _is_win or not ffi then return end
  local args = { ... }
  -- NOTE: must add NULL to mark end of the vararg
  table.insert(args, string.byte("\0"))
  ffi.C.execl(cmd, cmd, unpack(args))
  -- if `execl` succeeds we should never get here
  assert(false, string.format([[execl("%s",...) failed with error %d]], cmd, ffi.errno()))
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

_G.fzf_pty_spawn = function(cmd, opts)
  local function openpty(rows, cols)
    ---@diagnostic disable: assign-type-mismatch
    -- Lua doesn't have out-args so we create short arrays of numbers.
    local amaster = ffi.new("int[1]") ---@type [integer]
    local aslave = ffi.new("int[1]") ---@type [integer]
    ---@type { ws_row: integer, ws_col: integer }
    local winp = ffi.new("struct winsize")
    winp.ws_row = rows
    winp.ws_col = cols
    ffi.C.openpty(amaster, aslave, nil, nil, winp)
    -- And later extract the single value that was placed in the array.
    return amaster[0], aslave[0]
  end
  ---@type integer, integer
  local master, slave = openpty(opts.height, opts.width) -- workaround with resizing
  local pipe
  opts.env = opts.env or {}
  opts.env.NVIM = ""
  local handle, pid = FzfLua.libuv.uv_spawn(
    cmd[1],
    ---@diagnostic disable-next-line: missing-fields
    {
      args = vim.list_slice(cmd, 2),
      cwd = opts.cwd,
      stdio = { slave, slave, slave },
      env = opts.env,
    },
    function(_)
    end
  )

  pipe = assert(vim.uv.new_pipe(false))
  pipe:open(master)
  ffi.C.close(slave)

  local closing = false
  local kill = FzfLua.libuv.process_kill
  pipe:read_start(function(_)
    if closing then return end
    closing = true
    opts.on_stdout()
    vim.defer_fn(function()
      ffi.C.close(master)
      local pids = api.nvim_get_proc_children(pid)
      table.insert(pids, 1, pid)
      if not handle:is_closing() then
        vim.tbl_map(function(p) kill(p, uv.constants.SIGTERM) end, pids)
        vim.defer_fn(
          function() vim.tbl_map(function(p) kill(p, uv.constants.SIGKILL) end, pids) end, 100)
      end
    end, 20)
    pipe:read_stop()
  end)
  return pid
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
          posix_exec(fn.exepath("nvim"), entries[1].path,
            entries[1].line and ("+" .. entries[1].line) or nil,
            entries[1].col and ("+norm! %s|"):format(entries[1].col) or nil)
        elseif ffi and #entries > 1 then
          local file = fn.tempname()
          fn.writefile(vim.tbl_map(function(e) -- Format: {filename}:{lnum}:{col}: {text}
            local text = e.stripped:match(":%d+:%d?%d?%d?%d?:?(.*)$") or ""
            return ("%s:%d:%d: %s"):format(e.path, e.line or 1, e.col or 1, text)
          end, entries), file)
          posix_exec(fn.exepath("nvim"), "-q", file)
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
    actions = {
      ["enter"] = function(s)
        assert(s[1])
        local remote = s[1]:match("%((.-)%)")
        posix_exec(fn.exepath("nvim"), "--remote-ui", "--server", remote)
      end
    }
  }
}
