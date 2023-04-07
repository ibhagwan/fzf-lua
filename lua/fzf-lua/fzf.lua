-- slimmed down version of nvim-fzf's 'raw_fzf', changes include:
-- DOES NOT SUPPORT WINDOWS
-- does not close the pipe before all writes are complete
-- option to not add '\n' on content function callbacks
-- https://github.com/vijaymarupudi/nvim-fzf/blob/master/lua/fzf.lua
local uv = vim.loop

local M = {}

-- workaround to a potential 'tempname' bug? (#222)
-- neovim doesn't guarantee the existence of the
-- parent temp dir potentially failing `mkfifo`
-- https://github.com/neovim/neovim/issues/1432
-- https://github.com/neovim/neovim/pull/11284
local function tempname()
  local tmpname = vim.fn.tempname()
  local parent = vim.fn.fnamemodify(tmpname, ":h")
  -- parent must exist for `mkfifo` to succeed
  -- if the neovim temp dir was deleted or the
  -- tempname already exists, we use 'os.tmpname'
  if not uv.fs_stat(parent) or uv.fs_stat(tmpname) then
    tmpname = os.tmpname()
    -- 'os.tmpname' touches the file which
    -- will also fail `mkfifo`, delete it
    vim.fn.delete(tmpname)
  end
  return tmpname
end

-- contents can be either a table with tostring()able items, or a function that
-- can be called repeatedly for values. The latter can use coroutines for async
-- behavior.
function M.raw_fzf(contents, fzf_cli_args, opts)
  if not coroutine.running() then
    error("[Fzf-lua] function must be called inside a coroutine.")
  end

  if not opts then opts = {} end
  local cwd = opts.fzf_cwd or opts.cwd
  local cmd = opts.fzf_bin or "fzf"
  local fifotmpname = tempname()
  local outputtmpname = tempname()

  -- we use a temporary env $FZF_DEFAULT_COMMAND instead of piping
  -- the command to fzf, this way fzf kills the command when it exits.
  -- This is especially important with our shell helper as io.write fails
  -- to select when the pipe is broken (EPIPE) so the neovim headless
  -- instance never terminates which hangs fzf on exit
  local FZF_DEFAULT_COMMAND = nil

  if fzf_cli_args then cmd = cmd .. " " .. fzf_cli_args end
  if opts.fzf_cli_args then cmd = cmd .. " " .. opts.fzf_cli_args end

  if contents then
    if type(contents) == "string" and #contents > 0 then
      if opts.silent_fail ~= false then
        contents = ("%s || true"):format(contents)
      end
      FZF_DEFAULT_COMMAND = contents
    else
      -- Note: for some unknown reason, even though 'termopen' cmd is wrapped with
      -- `sh -c`, on rare occasions (or unique systems?) when using `fish` shell,
      -- commands that use the input redirection will hang indefintely (#633)
      -- Using `cat` instead to read from the FIFO named pipe seems to solve it,
      -- this is also better as it lets fzf handle spawning and terminating the
      -- command which is consistent with the behavior above (with string cmds)
      -- TODO: why does {FZF|SKIM}_DEFAULT_COMMAND cause delay in opening skim?
      -- use input redirection with skim to prevent interface opening delay
      if opts.fzf_bin and opts.fzf_bin:match("sk$") then
        cmd = ("%s < %s"):format(cmd, vim.fn.shellescape(fifotmpname))
      else
        FZF_DEFAULT_COMMAND = string.format("cat %s", vim.fn.shellescape(fifotmpname))
      end
    end
  end

  cmd = ("%s > %s"):format(cmd, vim.fn.shellescape(outputtmpname))

  local fd, output_pipe = nil, nil
  local finish_called = false
  local write_cb_count = 0

  -- Create the output pipe
  -- We use tbl for perf reasons, from ':help system':
  --  If {cmd} is a List it runs directly (no 'shell')
  --  If {cmd} is a String it runs in the 'shell'
  vim.fn.system({ "mkfifo", fifotmpname })

  local function finish(_)
    -- mark finish once called
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

  -- nvim-fzf compatibility, builds the user callback functions
  -- 1st argument: callback function that adds newline to each write
  -- 2nd argument: callback function that writes the data as is
  -- 3rd argument: direct access to the pipe object
  local function usr_write_cb(nl)
    local function end_of_data(usrdata, cb)
      if usrdata == nil then
        if cb then cb(nil) end
        finish(5)
        return true
      end
      return false
    end

    if nl then
      return function(usrdata, cb)
        if not end_of_data(usrdata, cb) then
          write_cb(tostring(usrdata) .. "\n", cb)
        end
      end
    else
      return function(usrdata, cb)
        if not end_of_data(usrdata, cb) then
          write_cb(usrdata, cb)
        end
      end
    end
  end

  -- I'm not sure why this happens (probably a neovim bug) but when pressing
  -- <C-c> in quick successsion immediately after opening the window neovim
  -- hangs the CPU at 100% at the last `coroutine.yield` before returning from
  -- this function. At this point it seems that the fzf subprocess was started
  -- and killed but `on_exit` is never called. In order to avoid calling `yield`
  -- I tried checking the job/coroutine status in different ways:
  --   * coroutine.status(co): always returns 'running'
  --   * vim.fn.job_pid: always returns the corrent pid (even if it doesn't
  --     exist anymore)
  --   * vim.fn.jobwait({job_pid}, 0): always returns '-1' (even when looping
  --     with 'vim.defer_fn(fn, 100)')
  --   * uv.os_priority(job_pid): always returns '0'
  -- `sudo strace -s 99 -ffp <pid> when neovim is stuck:
  --   [pid 27433] <... epoll_wait resumed>[{events=EPOLLIN, data={u32=18, u64=18}}], 1024, -1) = 1
  --   [pid 27432] <... write resumed>)        = 8
  --   [pid 27433] read(18, "\1\0\0\0\0\0\0\0", 1024) = 8
  --   [pid 27432] epoll_wait(9,  <unfinished ...>
  --   [pid 27433] epoll_wait(15,  <unfinished ...>
  --   [pid 27432] <... epoll_wait resumed>[], 1024, 0) = 0
  --   [pid 27432] epoll_wait(9, [], 1024, 0)  = 0
  --   [pid 27432] epoll_wait(9, [], 1024, 0)  = 0
  --   [pid 27432] epoll_wait(9, [], 1024, 0)  = 0
  --   [pid 27432] write(32, "\3", 1)          = 1
  --   [pid 27432] write(18, "\1\0\0\0\0\0\0\0", 8 <unfinished ...>
  --   [pid 27433] <... epoll_wait resumed>[{events=EPOLLIN, data={u32=18, u64=18}}], 1024, -1) = 1
  --   [pid 27432] <... write resumed>)        = 8
  --   [pid 27433] read(18, "\1\0\0\0\0\0\0\0", 1024) = 8
  --   [pid 27432] epoll_wait(9,  <unfinished ...>
  --   [pid 27433] epoll_wait(15,  <unfinished ...>
  --   [pid 27432] <... epoll_wait resumed>[], 1024, 0) = 0
  --   [pid 27432] epoll_wait(9, [], 1024, 0)  = 0
  --   [pid 27432] epoll_wait(9, [], 1024, 0)  = 0
  --   [pid 27432] epoll_wait(9, [], 1024, 0)  = 0
  --   [pid 27432] write(32, "\3", 1)          = 1
  --   [pid 27432] write(18, "\1\0\0\0\0\0\0\0", 8 <unfinished ...>
  --
  -- As a workaround we map buffer <C-c> to <Esc> for the fzf buffer
  -- `vim.keymap.set` to avoid breaking compatibility with older neovim versions
  --
  -- Removed as an experiment since the removal of the `save_query` code
  -- that was running on WinLeave which seems to make the `<C-c>` issue
  -- better or even non-existent? RESTORED AGAIN
  --
  if vim.keymap then
    vim.keymap.set("t", "<C-c>", "<Esc>", { buffer = 0 })
  else
    vim.api.nvim_buf_set_keymap(0, "t", "<C-c>", "<Esc>", { noremap = true })
  end

  local co = coroutine.running()
  local jobstart = opts.is_fzf_tmux and vim.fn.jobstart or vim.fn.termopen
  jobstart({ "sh", "-c", cmd }, {
    cwd = cwd,
    pty = true,
    env = {
      ["SHELL"] = "sh",
      ["FZF_DEFAULT_COMMAND"] = FZF_DEFAULT_COMMAND,
      ["SKIM_DEFAULT_COMMAND"] = FZF_DEFAULT_COMMAND,
    },
    on_exit = function(_, rc, _)
      local output = {}
      local f = io.open(outputtmpname)
      if f then
        for v in f:lines() do
          table.insert(output, v)
        end
        f:close()
      end
      finish(1)
      vim.fn.delete(fifotmpname)
      vim.fn.delete(outputtmpname)
      if #output == 0 then output = nil end
      coroutine.resume(co, output, rc)
    end
  })

  -- fzf-tmux spawns outside neovim, don't set filetype/insert mode
  if not opts.is_fzf_tmux then
    vim.cmd [[set ft=fzf]]

    -- terminal behavior seems to have changed after the introduction
    -- of 'nt' mode (terminal-normal mode) which is included in 0.6
    -- https://github.com/neovim/neovim/pull/15878
    -- Preferably I'd like to check if the vim patch is included using
    --   vim.fn.has('patch-8.2.3461')
    -- but this doesn't work for vim patches > 8.1 as explained in:
    -- https://github.com/neovim/neovim/issues/9635
    -- However, since this patch was included in 0.6 we can test
    -- for neovim version 0.6
    -- Beats me why 'nvim_get_mode().mode' still returns 'nt' even
    -- after we're clearly in insert mode or why `:startinsert`
    -- won't change the mode from 'nt' to 't' so we use feedkeys()
    -- instead.
    -- This "retires" 'actions.ensure_insert_mode' and solves the
    -- issue of calling an fzf-lua mapping from insert mode (#429)

    if vim.fn.has("nvim-0.6") == 1 then
      vim.cmd([[noautocmd lua vim.api.nvim_feedkeys(]]
        .. [[vim.api.nvim_replace_termcodes("<Esc>i", true, false, true)]]
        .. [[, 'n', true)]])
    else
      vim.cmd [[startinsert]]
    end
  end

  if not contents or type(contents) == "string" then
    goto wait_for_fzf
  end

  -- have to open this after there is a reader (termopen)
  -- otherwise this will block
  fd = uv.fs_open(fifotmpname, "w", -1)
  output_pipe = uv.new_pipe(false)
  output_pipe:open(fd)
  -- print(output_pipe:getpeername())

  -- this part runs in the background. When the user has selected, it will
  -- error out, but that doesn't matter so we just break out of the loop.
  if contents then
    if type(contents) == "table" then
      if not vim.tbl_isempty(contents) then
        write_cb(vim.tbl_map(function(x) return x .. "\n" end, contents))
      end
      finish(4)
    else
      contents(usr_write_cb(true), usr_write_cb(false), output_pipe)
    end
  end

  ::wait_for_fzf::
  return coroutine.yield()
end

return M
