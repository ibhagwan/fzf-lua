local shell = require "fzf-lua.shell"
local utils = require "fzf-lua.utils"
local uv = vim.loop

local M = {}

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

local function coroutine_callback(fn)
  local co = coroutine.running()
  local callback = function(...)
    if coroutine.status(co) == 'suspended' then
      coroutine.resume(co, ...)
    else
      local pid = unpack({...})
      utils.process_kill(pid)
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

  local finish = function(sig, pid)
    output_pipe:shutdown()
    error_pipe:shutdown()
    if opts.cb_finish then
      opts.cb_finish(sig, pid)
    end
    -- coroutinify callback
    if fn_done then
      fn_done(pid)
    end
  end

  -- https://github.com/luvit/luv/blob/master/docs.md
  -- uv.spawn returns tuple: handle, pid
  local _, pid = uv.spawn(vim.env.SHELL or "sh", {
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
      finish(1)
    end
  end)

  -- save current process pid
  if opts.cb_pid then opts.cb_pid(pid) end
  if opts.pid_cb then opts.pid_cb(pid) end

  local function write_cb(data)
    write_cb_count = write_cb_count + 1
    opts.cb_write(data, function(err)
      write_cb_count = write_cb_count - 1
      if err then
        -- can fail with premature process kill
        -- assert(not err)
        finish(2, pid)
      elseif write_cb_count == 0 and uv.is_closing(output_pipe) then
        -- spawn callback already called and did not close the pipe
        -- due to write_cb_count>0, since this is the last call
        -- we can close the fzf pipe
        finish(3, pid)
      end
    end)
  end

  local function process_lines(data)
    if opts.data_limit and opts.data_limit > 0 and #data>opts.data_limit then
      vim.defer_fn(function()
        utils.warn(("received large data chunk (%db), consider adding '--max-columns=512' to ripgrep flags\nDATA: '%s'")
          :format(#data, utils.strip_ansi_coloring(data):sub(1,80)))
      end, 0)
    end
    write_cb(data:gsub("[^\n]+",
      function(x)
        return fn_transform(x)
      end))
  end

  --[[ local function process_lines(data)
    if opts.data_limit and opts.data_limit > 0 and #data>opts.data_limit then
      vim.defer_fn(function()
        utils.warn(("received large data chunk (%db, consider adding '--max-columns=512' to ripgrep flags\nDATA: '%s'")
          :format(#data, utils.strip_ansi_coloring(data):sub(1,80)))
      end, 0)
    end
    local start_idx = 1
    repeat
      num_lines = num_lines + 1
      local nl_idx = find_next_newline(data, start_idx)
      local line = data:sub(start_idx, nl_idx)
      if #line > 1024 then
        vim.defer_fn(function()
          utils.warn(("long line %d bytes, '%s'")
            :format(#line, utils.strip_ansi_coloring(line):sub(1,60)))
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
      finish(4, pid)
    end
    if not data then
      return
    end

    if prev_line_content then
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
        -- chunk size is 64K, limit previous line length to 1K
        -- max line length is therefor 1K + 64K (leftover + full chunk)
        -- without this we can memory fault on extremely long lines (#185)
        -- or have UI freezes (#211)
        prev_line_content = data:sub(1, 1024)
      else
        prev_line_content = string_sub(data, nl_index + 1)
        local stripped_with_newline = string_sub(data, 1, nl_index)
        process_lines(stripped_with_newline)
      end
    end

  end

  local err_cb = function(err, data)
    if err then
      assert(not err)
      finish(9, pid)
    end
    if not data then
      return
    end
    write_cb(data)
  end

  output_pipe:read_start(read_cb)
  error_pipe:read_start(err_cb)
end

M.async_spawn = coroutinify(M.spawn)


M.spawn_nvim_fzf_cmd = function(opts, fn_transform)
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


M.spawn_nvim_fzf_action = function(fn, fzf_field_expression)

  return shell.async_action(function(pipe, ...)

    local function on_finish(_, _)
      if pipe and not uv.is_closing(pipe) then
        uv.close(pipe)
        pipe = nil
      end
    end

    local function on_write(data, cb)
      if not pipe then
        cb(true)
      else
        uv.write(pipe, data, cb)
      end
    end

    return M.spawn({
        cmd = fn(...),
        cb_finish = on_finish,
        cb_write = on_write,
      }, false)

  end, fzf_field_expression)
end

M.spawn_reload_cmd_action = function(opts, fzf_field_expression)

  local _pid = nil

  return shell.raw_async_action(function(pipe, args)

    local function on_pid(pid)
      _pid = pid
      if opts.pid_cb then
        opts.pid_cb(pid)
      end
    end

    local function on_finish(_, _)
      if pipe and not uv.is_closing(pipe) then
        uv.close(pipe)
        pipe = nil
      end
    end

    local function on_write(data, cb)
      if not pipe then
        cb(true)
      else
        uv.write(pipe, data, cb)
      end
    end

    -- terminate previously running commands
    utils.process_kill(_pid)

    -- return M.spawn({
    return M.async_spawn({
        cwd = opts.cwd,
        cmd = opts._reload_command(args[1]),
        cb_finish = on_finish,
        cb_write = on_write,
        cb_pid = on_pid,
        data_limit = opts.data_limit,
        -- must send false, 'coroutinify' adds callback as last argument
        -- which will conflict with the 'fn_transform' argument
      }, opts._fn_transform or false)

  end, fzf_field_expression)
end

return M
