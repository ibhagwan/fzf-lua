local uv = vim.loop

local M = {}

-- path to current file
local __FILE__ = debug.getinfo(1, 'S').source:gsub("^@", "")

-- if loading this file as standalone ('--headless --clean')
-- add the current folder to package.path so we can 'require'
if not vim.g.fzf_lua_directory then
  -- prepend this folder first so our modules always get first
  -- priority over some unknown random module with the same name
  package.path = (";%s/?.lua;"):format(vim.fn.fnamemodify(__FILE__, ':h'))
    .. package.path

  -- override require to remove the 'fzf-lua.' part
  -- since all files are going to be loaded locally
  local _require = require
  require = function(s) return _require(s:gsub("^fzf%-lua%.", "")) end
end

-- save to upvalue for performance reasons
local string_byte = string.byte
local string_sub = string.sub

local function find_last_newline(str)
  for i=#str,1,-1 do
    if string_byte(str, i) == 10 then
        return i
    end
  end
end

local function find_next_newline(str, start_idx)
  for i=start_idx or 1,#str do
    if string_byte(str, i) == 10 then
        return i
    end
  end
end

local function process_kill(pid, signal)
  if not pid or not tonumber(pid) then return false end
  if type(uv.os_getpriority(pid)) == 'number' then
    uv.kill(pid, signal or 9)
    return true
  end
  return false
end

M.process_kill = process_kill

local function coroutine_callback(fn)
  local co = coroutine.running()
  local callback = function(...)
    if coroutine.status(co) == 'suspended' then
      coroutine.resume(co, ...)
    else
      local pid = unpack({...})
      process_kill(pid)
    end
  end
  fn(callback)
  return coroutine.yield()
end

local function coroutinify(fn)
  return function(...)
    local args = {...}
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
  local num_lines = 0

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
  local handle, pid = uv.spawn(vim.env.SHELL or "sh", {
    args = { "-c", opts.cmd },
    stdio = { nil, output_pipe, error_pipe },
    cwd = opts.cwd
  }, function(code, signal)
    output_pipe:read_stop()
    error_pipe:read_stop()
    output_pipe:close()
    error_pipe :close()
    if write_cb_count==0 then
      -- only close if all our uv.write
      -- calls are completed
      finish(code, signal, 1)
    end
  end)

  -- save current process pid
  if opts.cb_pid then opts.cb_pid(pid) end
  if opts.pid_cb then opts.pid_cb(pid) end
  if opts._pid_cb then opts._pid_cb(pid) end

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

  local function process_lines(data)
    -- assert(#data<=66560) -- 65K
    write_cb(data:gsub("[^\n]+",
      function(x)
        return fn_transform(x)
      end))
  end

  --[[ local function process_lines(data)
    local start_idx = 1
    repeat
      num_lines = num_lines + 1
      local nl_idx = find_next_newline(data, start_idx)
      local line = data:sub(start_idx, nl_idx)
      if #line > 1024 then
        local msg =
          ("long line detected, consider adding '--max-columns=512' to ripgrep options:\n  %s")
            :format(utils.strip_ansi_coloring(line):sub(1,60))
        vim.defer_fn(function()
          utils.warn(msg)
        end, 0)
        line = line:sub(1,512) .. '\n'
      end
      write_cb(fn_transform(line))
      start_idx = nl_idx + 1
    until start_idx >= #data
  end --]]

  local read_cb = function(err, data)

    if err then
      assert(not err)
      finish(130, 0, 4, pid)
    end
    if not data then
      return
    end

    if prev_line_content then
      if #prev_line_content > 1024 then
        -- chunk size is 64K, limit previous line length to 1K
        -- max line length is therefor 1K + 64K (leftover + full chunk)
        -- without this we can memory fault on extremely long lines (#185)
        -- or have UI freezes (#211)
        prev_line_content = prev_line_content:sub(1, 1024)
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
    err_cb(nil, pid.."\n")
    err_cb(pid, nil)
  else
    output_pipe:read_start(read_cb)
    error_pipe:read_start(err_cb)
  end
end

M.async_spawn = coroutinify(M.spawn)


M.spawn_nvim_fzf_cmd = function(opts, fn_transform, fn_preprocess)

  assert(not fn_transform or type(fn_transform) == 'function')

  if fn_preprocess and type(fn_preprocess) == 'function' then
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
      -- below not relevant anymore, will delete comment in future
      -- if 'fn_transform' was specified the last char must be EOL
      -- otherwise something went terribly wrong
      -- without 'fn_transform' EOL isn't guaranteed at the end
      -- assert(not fn_transform or string_byte(data, #data) == 10)
      fzf_cb(data, cb)
    end

    return M.spawn({
        cwd = opts.cwd,
        cmd = opts.cmd,
        cb_finish = on_finish,
        cb_write = on_write,
        cb_pid = opts.pid_cb,
      }, fn_transform)
  end
end

M.spawn_stdio = function(opts, fn_transform, fn_preprocess)

  local function load_fn(fn_str)
    if type(fn_str) ~= 'string' then return end
    local fn_loaded = nil
    local fn = loadstring(fn_str) or load(fn_str)
    if fn then fn_loaded = fn() end
    if type(fn_loaded) ~= 'function' then
      fn_loaded = nil
    end
    return fn_loaded
  end

  fn_transform = load_fn(fn_transform)
  fn_preprocess = load_fn(fn_preprocess)

  -- run the preprocessing fn
  if fn_preprocess then fn_preprocess(opts) end

  local stderr, stdout = nil, nil

  local function exit(exit_code, msg)
    if msg then
      -- prioritize writing errors to stderr
      if stderr then stderr:write(msg)
      else io.stderr:write(msg) end
    end
    os.exit(exit_code)
  end

  local function pipe_open(pipename)
    if not pipename then return end
    local fd = uv.fs_open(pipename, "w", -1)
    if type(fd) ~= 'number' then
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
        -- <C-c> err will be either EPIPE or ECANCELED
        -- don't really need to do anything since the
        -- processs will be killed anyways with os.exit()
        if err then io.stderr:write("pipe:write Error: "..err) end
        if cb then cb(err) end
      end)
  end

  if opts.stderr then
    stderr = pipe_open(opts.stderr)
  end
  if opts.stdout then
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
        io.stdout:write(data)
        cb(nil)
      end
    end

  local on_err = opts.on_err or
    function(data)
      if stderr then
        pipe_write(stderr, data)
      else
        io.stderr:write(data)
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
      return fn_transform(opts, x)
    end)
end

M.wrap_spawn_stdio = function(opts, fn_transform, fn_preprocess)
  assert(opts and type(opts) == 'string')
  assert(not fn_transform or type(fn_transform) == 'string')
  local nvim_bin = vim.v.argv[1]
  local call_args = opts
  for _, fn in ipairs({ fn_transform, fn_preprocess }) do
    if type(fn) == 'string' then
      call_args = ("%s,[[%s]]"):format(call_args, fn)
    end
  end
  local cmd_str = ("%s -n --headless --clean --cmd %s"):format(
    vim.fn.shellescape(nvim_bin),
    vim.fn.shellescape(("lua loadfile([[%s]])().spawn_stdio(%s)")
      :format(__FILE__, call_args)))
  return cmd_str
end

return M
