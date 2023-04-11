local uv = vim.loop

local M = {}

-- path to current file
local __FILE__ = debug.getinfo(1, "S").source:gsub("^@", "")

-- if loading this file as standalone ('--headless --clean')
-- add the current folder to package.path so we can 'require'
-- NOTE: loading this file before fzf-lua can cause unintended
-- effects (as 'vim.g.fzf_lua_directory=nil'). Run an additional
-- check if we are running headless with 'vim.api.nvim_list_uis'
if not vim.g.fzf_lua_directory and #vim.api.nvim_list_uis() == 0 then
  -- prepend this folder first, so our modules always get first
  -- priority over some unknown random module with the same name
  package.path = (";%s/?.lua;"):format(vim.fn.fnamemodify(__FILE__, ":h"))
      .. package.path

  -- override require to remove the 'fzf-lua.' part
  -- since all files are going to be loaded locally
  local _require = require
  require = function(s) return _require(s:gsub("^fzf%-lua%.", "")) end

  -- due to 'os.exit' neovim doesn't delete the temporary
  -- directory, save it so we can delete prior to exit (#329)
  -- NOTE: opted to delete the temp dir at the start due to:
  --   (1) spawn_stdio doesn't need a temp directory
  --   (2) avoid dangling temp dirs on process kill (i.e. live_grep)
  local tmpdir = vim.fn.fnamemodify(vim.fn.tempname(), ":h")
  if tmpdir and #tmpdir > 0 then
    vim.fn.delete(tmpdir, "rf")
    -- io.stdout:write("[DEBUG]: "..tmpdir.."\n")
  end
  -- neovim might also automatically start the RPC server which will
  -- generate a named pipe temp file, e.g. `/run/user/1000/nvim.14249.0`
  -- we don't need the server in the headless "child" process, stopping
  -- the server also deletes the temp file
  if vim.v.servername and #vim.v.servername > 0 then
    pcall(vim.fn.serverstop, vim.v.servername)
  end
end

-- save to upvalue for performance reasons
local string_byte = string.byte
local string_sub = string.sub

local function find_last_newline(str)
  for i = #str, 1, -1 do
    if string_byte(str, i) == 10 then
      return i
    end
  end
end

local function find_next_newline(str, start_idx)
  for i = start_idx or 1, #str do
    if string_byte(str, i) == 10 then
      return i
    end
  end
end

local function process_kill(pid, signal)
  if not pid or not tonumber(pid) then return false end
  if type(uv.os_getpriority(pid)) == "number" then
    uv.kill(pid, signal or 9)
    return true
  end
  return false
end

M.process_kill = process_kill

local function coroutine_callback(fn)
  local co = coroutine.running()
  local callback = function(...)
    if coroutine.status(co) == "suspended" then
      coroutine.resume(co, ...)
    else
      local pid = unpack({ ... })
      process_kill(pid)
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

M.spawn = function(opts, fn_transform, fn_done)
  local output_pipe = uv.new_pipe(false)
  local error_pipe = uv.new_pipe(false)
  local write_cb_count = 0
  local prev_line_content = nil

  if opts.fn_transform then fn_transform = opts.fn_transform end

  local finish = function(code, sig, from, pid)
    output_pipe:shutdown()
    error_pipe:shutdown()
    if opts.cb_finish then
      opts.cb_finish(code, sig, from, pid)
    end
    -- coroutinify callback
    if fn_done then
      fn_done(pid)
    end
  end

  -- https://github.com/luvit/luv/blob/master/docs.md
  -- uv.spawn returns tuple: handle, pid
  local handle, pid = uv.spawn("sh", {
    args = { "-c", opts.cmd },
    stdio = { nil, output_pipe, error_pipe },
    cwd = opts.cwd
  }, function(code, signal)
    output_pipe:read_stop()
    error_pipe:read_stop()
    output_pipe:close()
    error_pipe:close()
    if write_cb_count == 0 then
      -- only close if all our uv.write
      -- calls are completed
      finish(code, signal, 1)
    end
  end)

  -- save current process pid
  if opts.cb_pid then opts.cb_pid(pid) end

  local function write_cb(data)
    write_cb_count = write_cb_count + 1
    opts.cb_write(data, function(err)
      write_cb_count = write_cb_count - 1
      if err then
        -- can fail with premature process kill
        -- assert(not err)
        finish(130, 0, 2, pid)
      elseif write_cb_count == 0 and uv.is_closing(output_pipe) then
        -- spawn callback already called and did not close the pipe
        -- due to write_cb_count>0, since this is the last call
        -- we can close the fzf pipe
        finish(0, 0, 3, pid)
      end
    end)
  end

  -- This is the old function used, worked very well
  -- but couldn't handle 'fn_transform' nil retval
  -- which we need for 'file_ignore_patterns'
  --[[ local function process_lines(data)
    -- assert(#data<=66560) -- 65K
    write_cb(data:gsub("[^\n]+",
      function(x)
        return fn_transform(x)
      end))
  end ]]
  local function process_lines(data)
    local lines = {}
    local start_idx = 1
    repeat
      local nl_idx = find_next_newline(data, start_idx)
      local line = data:sub(start_idx, nl_idx - 1)
      -- We used to limit lines fed into fzf to 1K for perf reasons
      -- but it turned out to have some negative consequnces (#580)
      -- if #line > 1024 then
      -- line = line:sub(1, 1024)
      -- io.stderr:write(string.format("[Fzf-lua] long line detected (%db), "
      --   .. "consider adding '--max-columns=512' to ripgrep options: %s\n",
      --   #line, line:sub(1,256)))
      -- end
      line = fn_transform(line)
      if line then table.insert(lines, line) end
      start_idx = nl_idx + 1
    until start_idx >= #data
    -- testing shows better performance writing the entire
    -- table at once as opposed to calling 'write_cb' for
    -- every line after 'fn_transform'
    if #lines > 0 then
      write_cb(table.concat(lines, "\n") .. "\n")
    end
  end

  local read_cb = function(err, data)
    if err then
      assert(not err)
      finish(130, 0, 4, pid)
    end
    if not data then
      return
    end

    if prev_line_content then
      if #prev_line_content > 4096 then
        -- chunk size is 64K, limit previous line length to 4K
        -- max line length is therefor 4K + 64K (leftover + full chunk)
        -- without this we can memory fault on extremely long lines (#185)
        -- or have UI freezes (#211)
        prev_line_content = prev_line_content:sub(1, 4096)
      end
      data = prev_line_content .. data
      prev_line_content = nil
    end

    if not fn_transform then
      write_cb(data)
    elseif string_byte(data, #data) == 10 then
      process_lines(data)
    else
      local nl_index = find_last_newline(data)
      if not nl_index then
        prev_line_content = data
      else
        prev_line_content = string_sub(data, nl_index + 1)
        local stripped_with_newline = string_sub(data, 1, nl_index)
        process_lines(stripped_with_newline)
      end
    end
  end

  local err_cb = function(err, data)
    if err then
      finish(130, 0, 9, pid)
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
    err_cb(nil, pid .. "\n")
    err_cb(pid, nil)
  else
    output_pipe:read_start(read_cb)
    error_pipe:read_start(err_cb)
  end
end

M.async_spawn = coroutinify(M.spawn)


M.spawn_nvim_fzf_cmd = function(opts, fn_transform, fn_preprocess)
  assert(not fn_transform or type(fn_transform) == "function")

  if fn_preprocess and type(fn_preprocess) == "function" then
    -- run the preprocessing fn
    fn_preprocess(opts)
  end

  return function(_, fzf_cb, _)
    local function on_finish(_, _)
      fzf_cb(nil)
    end

    local function on_write(data, cb)
      -- passthrough the data exactly as received from the pipe
      -- using the 2nd 'fzf_cb' arg instructs raw_fzf to not add "\n"
      --
      -- below not relevant anymore, will delete comment in future.
      -- If 'fn_transform' was specified, the last char must be EOL
      -- otherwise something went terribly wrong.
      -- Without 'fn_transform', EOL isn't guaranteed at the end
      -- assert(not fn_transform or string_byte(data, #data) == 10)
      fzf_cb(data, cb)
    end

    return M.spawn({
      cwd = opts.cwd,
      cmd = opts.cmd,
      cb_finish = on_finish,
      cb_write = on_write,
      cb_pid = opts.cb_pid,
    }, fn_transform)
  end
end

M.spawn_stdio = function(opts, fn_transform, fn_preprocess)
  local function load_fn(fn_str)
    if type(fn_str) ~= "string" then return end
    local fn_loaded = nil
    local fn = loadstring(fn_str) or load(fn_str)
    if fn then fn_loaded = fn() end
    if type(fn_loaded) ~= "function" then
      fn_loaded = nil
    end
    return fn_loaded
  end

  -- stdin/stdout are already buffered, not stderr. This means
  -- that every character is flushed immedietely which caused
  -- rendering issues on Mac (#316, #287) and Linux (#414)
  -- switch 'stderr' stream to 'line' buffering
  -- https://www.lua.org/manual/5.2/manual.html#pdf-file%3asetvbuf
  io.stderr:setvbuf "line"

  -- redirect 'stderr' to 'stdout' on Macs by default
  -- only takes effect if 'opts.stderr' was not set
  if opts.stderr_to_stdout == nil and
      vim.loop.os_uname().sysname == "Darwin" then
    opts.stderr_to_stdout = true
  end

  fn_transform = load_fn(fn_transform)
  fn_preprocess = load_fn(fn_preprocess)

  -- run the preprocessing fn
  if fn_preprocess then fn_preprocess(opts) end


  if opts.debug then
    io.stdout:write("[DEBUG]: " .. opts.cmd .. "\n")
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

  local function exit(exit_code, msg)
    if msg then stderr_write(msg) end
    os.exit(exit_code)
  end

  local function pipe_open(pipename)
    if not pipename then return end
    local fd = uv.fs_open(pipename, "w", -1)
    if type(fd) ~= "number" then
      exit(1, ("error opening '%s': %s\n"):format(pipename, fd))
    end
    local pipe = uv.new_pipe(false)
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
        -- processs will be killed anyways with os.exit()
        if err then
          stderr_write(("pipe:write error: %s\n"):format(err))
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

  local on_finish = opts.on_finish or
      function(code)
        pipe_close(stdout)
        pipe_close(stderr)
        exit(code)
      end

  local on_write = opts.on_write or
      function(data, cb)
        if stdout then
          pipe_write(stdout, data, cb)
        else
          -- on success: rc=true, err=nil
          -- on failure: rc=nil, err="Broken pipe"
          -- cb with an err ends the process
          local rc, err = io.stdout:write(data)
          if not rc then
            stderr_write(("io.stdout:write error: %s\n"):format(err))
            cb(err or true)
          else
            cb(nil)
          end
        end
      end

  local on_err = opts.on_err or
      function(data)
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

  return M.spawn({
      cwd = opts.cwd,
      cmd = opts.cmd,
      cb_finish = on_finish,
      cb_write = on_write,
      cb_err = on_err,
    },
    fn_transform and function(x)
      return fn_transform(x, opts)
    end)
end

-- our own version of vim.fn.shellescape compatibile with fish shells
--   * don't double-escape '\' (#340)
--   * if possible, replace surrounding single quote with double
-- from ':help shellescape':
--    If 'shell' contains "fish" in the tail, the "\" character will
--    be escaped because in fish it is used as an escape character
--    inside single quotes.
-- this function is a better fit for utils but we're
-- trying to avoid having any 'require' in this file
M.shellescape = function(s)
  local shell = vim.o.shell
  if not shell or not shell:match("fish$") then
    return vim.fn.shellescape(s)
  else
    local ret = nil
    vim.o.shell = "sh"
    if not s:match([["]]) and not s:match([[\]]) then
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

M.wrap_spawn_stdio = function(opts, fn_transform, fn_preprocess)
  assert(opts and type(opts) == "string")
  assert(not fn_transform or type(fn_transform) == "string")
  local nvim_bin = os.getenv("FZF_LUA_NVIM_BIN") or vim.v.progpath
  local call_args = opts
  for _, fn in ipairs({ fn_transform, fn_preprocess }) do
    if type(fn) == "string" then
      call_args = ("%s,[[%s]]"):format(call_args, fn)
    end
  end
  local cmd_str = ("%s -n --headless --clean --cmd %s"):format(
    vim.fn.shellescape(nvim_bin),
    M.shellescape(("lua loadfile([[%s]])().spawn_stdio(%s)")
      :format(__FILE__, call_args)))
  return cmd_str
end

return M
