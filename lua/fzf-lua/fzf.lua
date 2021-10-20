-- slimmed down version of nvim-fzf's 'raw_fzf', changes include:
-- DOES NOT SUPPORT WINDOWS
-- does not close the pipe before all writes are complete
-- option to not add '\n' on content function callbacks
-- https://github.com/vijaymarupudi/nvim-fzf/blob/master/lua/fzf.lua
local uv = vim.loop

local M = {}

local function get_lines_from_file(file)
  local t = {}
  for v in file:lines() do
    table.insert(t, v)
  end
  return t
end

-- contents can be either a table with tostring()able items, or a function that
-- can be called repeatedly for values. the latter can use coroutines for async
-- behavior.
function M.raw_fzf(contents, fzf_cli_args, opts)
  if not coroutine.running() then
    error("please run function in a coroutine")
  end

  if not opts then opts = {} end
  local cwd = opts.fzf_cwd or opts.cwd
  local cmd = opts.fzf_binary or opts.fzf_bin or 'fzf'
  local fifotmpname = vim.fn.tempname()
  local outputtmpname = vim.fn.tempname()

  if fzf_cli_args then cmd = cmd .. " " .. fzf_cli_args end
  if opts.fzf_cli_args then cmd = cmd .. " " .. opts.fzf_cli_args end

  if contents then
    if type(contents) == "string" and #contents>0 then
      cmd = ("%s | %s"):format(contents, cmd)
    else
      cmd = ("%s < %s"):format(cmd, vim.fn.shellescape(fifotmpname))
    end
  end

  cmd = ("%s > %s"):format(cmd, vim.fn.shellescape(outputtmpname))

  local fd, output_pipe = nil, nil
  local finish_called = false
  local write_cb_count = 0

  -- Create the output pipe
  vim.fn.system(("mkfifo %s"):format(vim.fn.shellescape(fifotmpname)))

  local function finish(_)
    -- mark finish if once called
    finish_called = true
    -- close pipe if there are no outstanding writes
    if output_pipe and write_cb_count == 0 then
      output_pipe:close()
      output_pipe = nil
    end
  end

  local function write_cb(data, cb)
    if not output_pipe then return end
    write_cb_count = write_cb_count + 1
    output_pipe:write(data, function(err)
      -- decrement write call count
      write_cb_count = write_cb_count - 1
      -- this will call the user's cb
      if cb then cb(err) end
      if err then
        -- can fail with premature process kill
        finish(2)
      elseif finish_called and write_cb_count == 0 then
        -- 'termopen.on_exit' already called and did not close the
        -- pipe due to write_cb_count>0, since this is the last call
        -- we can close the fzf pipe
        finish(3)
      end
    end)
  end

  local co = coroutine.running()
  vim.fn.termopen(cmd, {
    cwd = cwd,
    on_exit = function(_, rc, _)
      local f = io.open(outputtmpname)
      local output = get_lines_from_file(f)
      f:close()
      finish(1)
      vim.fn.delete(fifotmpname)
      vim.fn.delete(outputtmpname)
      if #output == 0 then output = nil end
      coroutine.resume(co, output, rc)
    end
  })
  vim.cmd[[set ft=fzf]]
  vim.cmd[[startinsert]]

  if not contents or type(contents) == "string" then
    goto wait_for_fzf
  end

  -- have to open this after there is a reader (termopen)
  -- otherwise this will block
  fd = uv.fs_open(fifotmpname, "w", -1)
  output_pipe = uv.new_pipe(false)
  output_pipe:open(fd)
  -- print(uv.pipe_getpeername(output_pipe))

  -- this part runs in the background, when the user has selected, it will
  -- error out, but that doesn't matter so we just break out of the loop.
  if contents then
    if type(contents) == "table" then
      if not vim.tbl_isempty(contents) then
        write_cb(vim.tbl_map(function(x) return x.."\n" end, contents))
      end
      finish(4)
    else
      contents(function(usrdata, cb, no_nl)
        if usrdata == nil then
          if cb then cb(nil) end
          finish(5)
          return
        end
        if no_nl then
          write_cb(usrdata, cb)
        else
          write_cb(tostring(usrdata).."\n", cb)
        end
      end, output_pipe)
    end
  end

  ::wait_for_fzf::

  return coroutine.yield()
end

return M
