local utils = require "fzf-lua.utils"
local async_action = require("fzf.actions").async_action
local raw_async_action = require("fzf.actions").raw_async_action
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

  if opts.fn_transform then fn_transform = opts.fn_transform end

  local shell = vim.env.SHELL or "sh"

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
  local _, pid = uv.spawn(shell, {
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
      if err then
        -- can fail with premature process kill
        -- assert(not err)
        finish(2, pid)
      end
      write_cb_count = write_cb_count - 1
      if write_cb_count == 0 and uv.is_closing(output_pipe) then
        -- spawn callback already called and did not close the pipe
        -- due to write_cb_count>0, since this is the last call
        -- we can close the fzf pipe
        finish(3, pid)
      end
    end)
  end

  local function process_lines(str)
    write_cb(str:gsub("[^\n]+",
      function(x)
        return fn_transform(x)
      end))
  end

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
  return function(fzf_cb)

    local function on_finish(_, _)
      fzf_cb(nil)
    end

    local function on_write(data, cb)
      -- nvim-fzf adds "\n" at the end
      -- so we have to remove ours
      assert(string_byte(data, #data) == 10)
      fzf_cb(string_sub(data, 1, #data-1), cb)
    end

    if not fn_transform then
      -- must add a dummy function here, without it
      -- spawn() wouldn't parse EOLs and send partial
      -- data via nvim-fzf's fzf_cb() which adds "\n"
      -- each call, resulting in mangled data
      fn_transform = function(x) return x end
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

  return async_action(function(pipe, ...)

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

  return raw_async_action(function(pipe, args)

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
      }, opts._fn_transform)

  end, fzf_field_expression)
end

return M
