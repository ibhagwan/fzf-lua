local uv = vim.uv or vim.loop
local utils = require "fzf-lua.utils"
local path = require "fzf-lua.path"
local libuv = require "fzf-lua.libuv"
local base64 = require "fzf-lua.lib.base64"
local serpent = require "fzf-lua.lib.serpent"

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

---@param fn function
---@param fzf_field_index string
---@param debug boolean|integer
---@return string, integer
function M.pipe_wrap_fn(fn, fzf_field_index, debug)
  fzf_field_index = fzf_field_index or "{+}"

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
    libuv.shellescape(path.normalize(path.join { vim.g.fzf_lua_directory, "rpc.lua" })),
    id,
    tostring(debug),
    fzf_field_index)

  return action_cmd, id
end

---@param opts table
---@return string?
M.stringify_mt = function(cmd, opts)
  assert(type(opts) == "table", "opts must be supplied")
  assert(cmd or opts and opts.cmd, "cmd must be supplied")
  opts.cmd = cmd or opts and opts.cmd
  ---@param o table<string, unknown>
  ---@return table
  local filter_opts = function(o)
    local names = {
      "debug",
      "profiler",
      "process1",
      "silent",
      "argv_expr",
      "cmd",
      "cwd",
      "stdout",
      "stderr",
      "stderr_to_stdout",
      "formatter",
      "multiline",
      "git_dir",
      "git_worktree",
      "git_icons",
      "file_icons",
      "color_icons",
      "path_shorten",
      "strip_cwd_prefix",
      "exec_empty_query",
      "file_ignore_patterns",
      "rg_glob",
      "_base64",
      utils.__IS_WINDOWS and "__FZF_VERSION" or nil,
    }
    -- caller requested rg with glob support
    if o.rg_glob then
      table.insert(names, "glob_flag")
      table.insert(names, "glob_separator")
    end
    local t = {}
    for _, name in ipairs(names) do
      if o[name] ~= nil then
        t[name] = o[name]
      end
    end
    t.g = {}
    for k, v in pairs({
      ["_fzf_lua_server"] = vim.g.fzf_lua_server,
      -- [NOTE] No longer needed, we use RPC for icons
      -- ["_devicons_path"] = devicons.plugin_path(),
      -- ["_devicons_setup"] = config._devicons_setup,
      ["_EOL"] = opts.multiline and "\0" or "\n",
      ["_debug"] = opts.debug,
    }) do
      t.g[k] = v
    end
    return t
  end

  ---@param obj table|string
  ---@return string
  local serialize = function(obj)
    local str = type(obj) == "table"
        and serpent.line(obj, { comment = false, sortkeys = false })
        or tostring(obj)
    if opts._base64 ~= false then
      -- by default, base64 encode all arguments
      return "[==[" .. base64.encode(str) .. "]==]"
    else
      -- if not encoding, don't string wrap the table
      return type(obj) == "table" and str
          or "[==[" .. str .. "]==]"
    end
  end

  -- `multiprocess=1` is "optional" if no opt which requires processing
  -- is present we return the command as is to be piped to fzf "natively"
  if opts.multiprocess == 1
      and not opts.fn_transform
      and not opts.fn_preprocess
      and not opts.fn_postprocess
  then
    -- command does not require any processing, we also reset `argv_expr`
    -- to keep `setup_fzf_interactive_flags::no_query_condi` in the command
    opts.argv_expr = nil
    return opts.cmd
  elseif opts.multiprocess then
    for _, k in ipairs({ "fn_transform", "fn_preprocess", "fn_postprocess" }) do
      local v = opts[k]
      if type(v) == "function" and utils.__HAS_NVIM_010 then
        -- Attempt to convert function to its bytecode representation
        -- NOTE: limited to neovim >= 0.10 due to vim.base64
        v = string.format(
          [[return loadstring(vim.base64.decode("%s"))]],
          vim.base64.encode(string.dump(v, true)))
        -- Test the function once with nil value (imprefect?)
        -- to see if there's an issue with upvalue refs
        local f = loadstring(v)()
        local ok, err = pcall(f)
        assert(ok or not err:match("attempt to index upvalue"),
          string.format("multiprocess '%s' cannot have upvalue referecnces", k))
        opts[k] = v
      end
      assert(not v or type(v) == "string", "multiprocess requires lua string callbacks")
    end
    if opts.argv_expr then
      -- Since the `rg` command will be wrapped inside the shell escaped
      -- '--headless .. --cmd', we won't be able to search single quotes
      -- as it will break the escape sequence. So we use a nifty trick:
      --   * replace the placeholder with {argv1}
      --   * re-add the placeholder at the end of the command
      --   * preprocess then replace it with vim.fn.argv(1)
      -- NOTE: since we cannot guarantee the positional index
      -- of arguments (#291), we use the last argument instead
      opts.cmd = opts.cmd:gsub(FzfLua.core.fzf_query_placeholder, "{argvz}")
    end
    local spawn_cmd = libuv.wrap_spawn_stdio(
      serialize(filter_opts(opts)),
      serialize(opts.fn_transform or "nil"),
      serialize(opts.fn_preprocess or "nil"),
      serialize(opts.fn_postprocess or "nil")
    )
    if opts.argv_expr then
      -- prefix the query with `--` so we can support `--fixed-strings` (#781)
      spawn_cmd = string.format("%s -- %s", spawn_cmd, FzfLua.core.fzf_query_placeholder)
    end
    return spawn_cmd
  end
end

---@param contents table|function|string
---@param opts {}
---Fzf field index expression, e.g. "{+}" (selected), "{q}" (query)
---@param fzf_field_index string?
---@return string, integer?
M.stringify = function(contents, opts, fzf_field_index)
  assert(contents, "must supply contents")

  -- TODO: should we let this assert?
  -- are there any conditions in which stringify is called subsequently?
  if opts.__stringified then return contents end

  -- Mark opts as already "stringified"
  assert(not opts.__stringified, "twice stringified")
  opts.__stringified = true

  -- No need to register function id (2nd `nil` in tuple), the wrapped multiprocess
  -- command is independent, most of it's options are serialized as strings and the
  -- rest are read from the main instance config over RPC
  if opts.multiprocess and type(contents) == "string" then
    local cmd = M.stringify_mt(contents, opts)
    if cmd then return cmd, nil end
  end

  ---@param fn_str string
  ---@return function?
  local function load_fn(fn_str)
    if type(fn_str) ~= "string" then return end
    local fn_loaded = nil
    local fn = loadstring(fn_str)
    if fn then fn_loaded = fn() end
    if type(fn_loaded) ~= "function" then
      fn_loaded = nil
    end
    return fn_loaded
  end

  -- Convert string callbacks to callback functions
  for _, k in ipairs({ "fn_transform", "fn_preprocess", "fn_postprocess" }) do
    local v = opts[k]
    opts[k] = load_fn(opts[k]) or v
  end

  if type(opts.fn_reload) == "string" then
    fzf_field_index = fzf_field_index or "{q}"
    local cmd = opts.fn_reload --[[@as string]]
    contents = function(args)
      local query = libuv.shellescape(args[1] or "")
      if cmd:match(FzfLua.core.fzf_query_placeholder) then
        return cmd:gsub(FzfLua.core.fzf_query_placeholder, query)
      else
        return string.format("%s %s", cmd, query)
      end
    end
  end

  assert(not opts.fn_reload or type(contents) == "function", "fn_reload must be of type function")

  local cmd, id = M.pipe_wrap_fn(function(pipe, ...)
    local args = { ... }
    -- Contents could be dependent or args, e.g. live_grep which
    -- generates a different command based on the typed query
    -- redefine local contents to prevent override on function call
    ---@diagnostic disable-next-line: redefined-local
    local contents, env = (function()
      local ret = (opts.fn_reload or opts.__stringify_cmd)
          and contents(unpack(args))
          or contents
      if opts.__stringify_cmd and type(ret) == "table" then
        return ret.cmd, (ret.env or opts.env)
      else
        return ret, opts.env
      end
    end)()
    local write_cb_count = 0
    local pipe_want_close = false
    local EOL = opts.multiline and "\0" or "\n"
    local fn_transform = opts.fn_transform
    local fn_preprocess = opts.fn_preprocess
    local fn_postprocess = opts.fn_postprocess

    -- Run the preprocess function
    if type(fn_preprocess) == "function" then fn_preprocess(opts) end

    -- local on_finish = function(code, sig, from, pid)
    -- print("finish", pipe, pipe_want_close, code, sig, from, pid)
    local on_finish = function(_, _, _, _)
      if not pipe then return end
      pipe_want_close = true
      if write_cb_count == 0 then
        -- only close if all our uv.write calls are completed
        uv.close(pipe)
        pipe = nil
        -- Run the postprocess function
        if type(fn_postprocess) == "function" then fn_postprocess(opts) end
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

    if type(contents) == "string" then
      -- Terminate previously running command
      if opts.PidObject then
        libuv.process_kill(opts.PidObject:get())
        opts.PidObject:set(nil)
      end

      if opts.debug then
        on_write("[DEBUG] [st] " .. contents .. EOL)
      end

      libuv.async_spawn({
        cwd = opts.cwd,
        cmd = contents,
        env = env,
        cb_finish = on_finish,
        cb_write = on_write,
        cb_pid = function(pid) if opts.PidObject then opts.PidObject:set(pid) end end,
        process1 = opts.process1,
        profiler = opts.profiler,
        EOL = EOL,
        -- must send false, 'coroutinify' adds callback as last argument
        -- which will conflict with the 'fn_transform' argument
        -- convert `fn_transform(x)` to `fn_transform(x, opts)`
      }, fn_transform and function(x) return fn_transform(x, opts) end or false)
    else
      local fn_load = function()
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
        opts.__co = opts.__coroutinify and coroutine.running()

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


        if type(contents) == "table" then
          for _, l in ipairs(contents) do
            on_write_nl_co(l)
          end
          on_finish()
        elseif type(contents) == "function" then
          -- by default we use sync callbacks
          if opts.__coroutinify then
            contents(on_write_nl_co, on_write_co, unpack(args))
          else
            contents(on_write_nl, on_write, unpack(args))
          end
        else
        end
      end
      if opts.__coroutinify then
        fn_load = coroutine.wrap(fn_load)
      end
      fn_load()
    end
  end, fzf_field_index or "", opts.debug)

  M.set_protected(id)
  return cmd, id
end

M.stringify_cmd = function(fn, opts, fzf_field_index)
  assert(type(fn) == "function", "fn must be of type function")
  return M.stringify(fn, {
    __stringify_cmd = true,
    PidObject = utils.pid_object("__stringify_cmd_pid", opts),
    debug = opts.debug,
  }, fzf_field_index)
end

M.stringify_data = function(fn, opts, fzf_field_index)
  assert(type(fn) == "function", "fn must be of type function")
  return M.stringify(function(cb, _, ...)
    local ret = fn(...)
    if type(ret) == "table" then
      if not utils.tbl_isempty(ret) then
        vim.tbl_map(function(x) cb(x) end, ret)
      end
    else
      cb(tostring(ret))
    end
    cb(nil)
  end, { debug = opts.debug }, fzf_field_index)
end

return M
