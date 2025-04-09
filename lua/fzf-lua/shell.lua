-- modified version of:
-- https://github.com/vijaymarupudi/nvim-fzf/blob/master/lua/fzf/actions.lua
local uv = vim.uv or vim.loop
local utils = require "fzf-lua.utils"
local path = require "fzf-lua.path"
local libuv = require "fzf-lua.libuv"

local M = {}

-- Circular buffer used to store registered function IDs
-- set max length to 10, ATM most actions used by a single
-- provider are 2 (`live_grep` with `multiprocess=false`)
-- and 4 (`git_status` with preview and 3 reload binds)
-- we can always increase if we need more
local _MAX_LEN = 50
local _index = 0
local _registry = {}
local _protected = {}

function M.register_func(fn)
  repeat
    _index = _index % _MAX_LEN + 1
  until not _protected[_index]
  _registry[_index] = fn
  return _index
end

function M.get_func(id)
  return _registry[id]
end

function M.set_protected(id)
  _protected[id] = true
  assert(_MAX_LEN > utils.tbl_count(_protected))
end

function M.clear_protected()
  _protected = {}
end

-- creates a new address to listen to messages from actions. This is important
-- if the user is using a custom fixed $NVIM_LISTEN_ADDRESS. Different neovim
-- instances will then use the same path as the address and it causes a mess,
-- i.e. actions stop working on the old instance. So we create our own (random
-- path) RPC server for this instance if it hasn't been started already.
-- NOT USED ANYMORE, we use `vim.g.fzf_lua_server` instead
-- local action_server_address = nil

function M.raw_async_action(fn, fzf_field_expression, debug)
  if not fzf_field_expression then
    fzf_field_expression = "{+}"
  end

  local receiving_function = function(pipe_path, ...)
    local pipe = uv.new_pipe(false)
    local args = { ... }
    -- unescape double backslashes on windows
    if utils.__IS_WINDOWS and type(args[1]) == "table" then
      args[1] = vim.tbl_map(function(x)
        return libuv.unescape_fzf(x, vim.g.fzf_lua_fzf_version)
      end, args[1])
    end
    -- save selected item in main module's __INFO
    -- use loadstring to avoid circular require
    pcall(function()
      local module = loadstring("return require'fzf-lua'")()
      if module then
        module.__INFO = vim.tbl_deep_extend("force",
          module.__INFO or {}, { selected = args[1][1] })
      end
    end)
    uv.pipe_connect(pipe, pipe_path, function(err)
      if err then
        error(string.format("pipe_connect(%s) failed with error: %s", pipe_path, err))
      else
        vim.schedule(function()
          fn(pipe, unpack(args))
        end)
      end
    end)
  end

  local id = M.register_func(receiving_function)

  -- this is for windows WSL and AppImage users, their nvim path isn't just
  -- 'nvim', it can be something else
  local nvim_bin = os.getenv("FZF_LUA_NVIM_BIN") or vim.v.progpath

  -- all args after `-l` will be in `_G.args`
  local action_cmd = ("%s -u NONE -l %s %s %s %s"):format(
    libuv.shellescape(path.normalize(nvim_bin)),
    libuv.shellescape(path.normalize(path.join { vim.g.fzf_lua_directory, "shell_helper.lua" })),
    id,
    debug,
    fzf_field_expression)

  return action_cmd, id
end

function M.raw_action(fn, fzf_field_expression, debug)
  local receiving_function = function(pipe, ...)
    local ok, ret = pcall(fn, ...)

    local on_complete = function(_)
      -- We are NOT asserting, in case fzf closes
      -- the pipe before we can send the preview
      -- assert(not err)
      uv.close(pipe)
    end

    -- pipe must be closed, otherwise terminal will freeze
    if not ok then
      utils.err(ret)
      on_complete()
    end

    if type(ret) == "string" then
      uv.write(pipe, ret, on_complete)
    elseif type(ret) == nil then
      on_complete()
    elseif type(ret) == "table" then
      if not utils.tbl_isempty(ret) then
        uv.write(pipe, vim.tbl_map(function(x) return x .. "\n" end, ret), on_complete)
      else
        on_complete()
      end
    else
      uv.write(pipe, tostring(ret) .. "\n", on_complete)
    end
  end

  return M.raw_async_action(receiving_function, fzf_field_expression, debug)
end

function M.action(fn, fzf_field_expression, debug)
  local action_string, id = M.raw_action(fn, fzf_field_expression, debug)
  return libuv.shellescape(action_string), id
end

M.preview_action_cmd = function(fn, fzf_field_expression, debug)
  local action_string, id = M.raw_preview_action_cmd(fn, fzf_field_expression, debug)
  return libuv.shellescape(action_string), id
end

M.raw_preview_action_cmd = function(fn, fzf_field_expression, debug)
  return M.raw_async_action(function(pipe, ...)
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

    libuv.process_kill(M.__pid_preview)
    M.__pid_preview = nil

    local opts = fn(...)
    if type(opts) == "string" then
      --backward compat
      opts = { cmd = opts }
    end

    return libuv.spawn(vim.tbl_extend("force", opts, {
      cb_finish = on_finish,
      cb_write = on_write,
      cb_pid = function(pid) M.__pid_preview = pid end,
    }))
  end, fzf_field_expression, debug)
end

M.reload_action_cmd = function(opts, fzf_field_expression)
  if opts.fn_preprocess and type(opts.fn_preprocess) == "function" then
    -- run the preprocessing fn
    opts = vim.tbl_deep_extend("keep", opts, opts.fn_preprocess(opts))
  end

  return M.raw_async_action(function(pipe, args)
    -- get the type of contents from the caller
    local reload_contents = opts.__fn_reload(args[1])
    local write_cb_count = 0
    local pipe_want_close = false
    local EOL = opts.multiline and "\0" or "\n"

    -- local on_finish = function(code, sig, from, pid)
    -- print("finish", pipe, pipe_want_close, code, sig, from, pid)
    local on_finish = function(_, _, _, _)
      if not pipe then return end
      pipe_want_close = true
      if write_cb_count == 0 then
        -- only close if all our uv.write calls are completed
        uv.close(pipe)
        pipe = nil
      end
    end

    local on_write = function(data, cb, co)
      -- pipe can be nil when using a shell command with spawn
      -- and typing quickly, the process will terminate
      assert(not co or (co and pipe and not uv.is_closing(pipe)))
      if not pipe then return end
      if not data then
        on_finish(nil, nil, 5)
        if cb then cb(nil) end
      else
        write_cb_count = write_cb_count + 1
        uv.write(pipe, tostring(data), function(err)
          write_cb_count = write_cb_count - 1
          if co then coroutine.resume(co) end
          if cb then cb(err) end
          if err then
            -- force close on error
            write_cb_count = 0
            on_finish(nil, nil, 2)
          end
          if write_cb_count == 0 and pipe_want_close then
            on_finish(nil, nil, 3)
          end
        end)
        -- yield returns when uv.write completes
        -- or when a new coroutine calls resume(1)
        if co and coroutine.yield() == 1 then
          -- we have a new routine in opts.__co, this
          -- routine is no longer relevant so kill it
          write_cb_count = 0
          on_finish(nil, nil, 4)
        end
      end
    end

    if type(reload_contents) == "string" then
      -- string will be used as a shell command.
      -- terminate previously running commands
      libuv.process_kill(M.__pid_reload)
      M.__pid_reload = nil

      -- spawn/async_spawn already async, no need to send opts.__co
      -- also, we can't call coroutine.yield inside a libuv callback
      -- due to: "attempt to yield across C-call boundary"
      libuv.async_spawn({
        cwd = opts.cwd,
        cmd = reload_contents,
        cb_finish = on_finish,
        cb_write = on_write,
        cb_pid = function(pid) M.__pid_reload = pid end,
        EOL = EOL,
        -- must send false, 'coroutinify' adds callback as last argument
        -- which will conflict with the 'fn_transform' argument
      }, opts.__fn_transform or false)
    else
      -- table or function runs in a coroutine
      -- which isn't required for 'libuv.spawn'
      coroutine.wrap(function()
        if opts.__co then
          local costatus = coroutine.status(opts.__co)
          if costatus ~= "dead" then
            -- the previous routine is either 'running' or 'suspended'
            -- return 1 from yield to signal abort to 'on_write'
            coroutine.resume(opts.__co, 1)
          end
          assert(coroutine.status(opts.__co) == "dead")
        end
        -- reset var to current running routine
        opts.__co = coroutine.running()

        -- callback with newline
        local on_write_nl = function(data, cb)
          data = data and tostring(data) .. EOL or nil
          return on_write(data, cb)
        end

        -- callback with newline and coroutine
        local on_write_nl_co = function(data, cb)
          data = data and tostring(data) .. EOL or nil
          return on_write(data, cb, opts.__co)
        end

        -- callback with coroutine (no NL)
        local on_write_co = function(data, cb)
          return on_write(data, cb, opts.__co)
        end


        if type(reload_contents) == "table" then
          for _, l in ipairs(reload_contents) do
            on_write_nl_co(l)
          end
          on_finish()
        elseif type(reload_contents) == "function" then
          -- by default we use the async callbacks
          if opts.func_async_callback ~= false then
            reload_contents(on_write_nl_co, on_write_co)
          else
            reload_contents(on_write_nl, on_write)
          end
        else
        end
      end)()
    end
  end, fzf_field_expression, opts.debug)
end

return M
