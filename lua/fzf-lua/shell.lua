local uv = vim.uv or vim.loop
local utils = require "fzf-lua.utils"
local path = require "fzf-lua.path"
local libuv = require "fzf-lua.libuv"
local base64 = require "fzf-lua.lib.base64"
local serpent = require "fzf-lua.lib.serpent"

---@class fzf-lua.lru
---@field max_size integer
---@field max_id integer
---@field last_id integer
---@field mru integer[]
---@field store any[]
---@field lookup table<integer, integer>
local LRU = {}

function LRU:new(size)
  local obj = {
    max_size = size,
    -- Technically we can drop this var and let the IDs increment indefinitely
    -- but since the IDs are used in the shell command callback it makes it simpler
    -- to debug when it wraps around 1000 back to 1, size should be big enough to
    -- assert when accessing an evicted item and we wrapped around (if we set max
    -- ID to max size we will just rotate slots and return the wrong item)
    max_id = size * 20,
    last_id = 0,
    mru = {},
    store = {},
    lookup = {},
  }
  setmetatable(obj, self)
  self.__index = self
  return obj
end

---@param value any
---@return integer, integer? new element id and evicted id (if any)
function LRU:set(value)
  local store_idx, evicted_id
  local id = self.last_id + 1
  if id > self.max_id then id = 1 end
  if #self.store >= self.max_size then
    -- Evict the least recently used (last in MRU)
    evicted_id = table.remove(self.mru)
    store_idx = self.lookup[evicted_id]
    self.lookup[evicted_id] = nil
  else
    store_idx = #self.store + 1
  end
  -- New ID is inserted at the front of MRU
  table.insert(self.mru, 1, id)
  self.store[store_idx] = value
  self.lookup[id] = store_idx
  self.last_id = id
  return id, evicted_id
end

---@return integer
function LRU:len()
  return #self.store
end

---@param size integer
function LRU:set_size(size)
  assert(size >= self:len(), "new size cannot be smaller than current length")
  self.max_size = size
end

---@param id integer
---@return any
function LRU:get(id)
  local store_idx = self.lookup[id]
  assert(store_idx, string.format("attempt to get nonexistent id %d", id))
  -- Move id to the front of MRU
  for i = 1, #self.mru do
    if self.mru[i] == id then
      table.remove(self.mru, i)
      break
    end
  end
  table.insert(self.mru, 1, id)
  return self.store[store_idx]
end

-- Cache should be able to hold all function callbacks of a single picker
-- max cache size of 100 should be more than enough, we don't want it to be
-- too big as this will prevent clearing of referecnces to "opts" which
-- prevents garabage collection from freeing the resources
-- NOTE: with combine/global the no. of callbacks has increased significantly
-- so monitor the number of callbacks
local function new_cache(size) return LRU:new(size or 100) end
local _cache = new_cache()

local M = {}

-- Export LRU for testing
M.LRU = LRU

-- NOTE: CI ONLY - DO NOT USE
function M.cache_new(size) _cache = new_cache(size) end

function M.cache_set_size(size) _cache:set_size(size) end

function M.register_func(fn)
  return (_cache:set(fn))
end

function M.get_func(id)
  return _cache:get(id)
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
      -- NOTE: we add preprocess in config.normalize_opts but `opts.argv_expr`
      -- isn't yet set at that point
      if opts.fn_preprocess == nil then
        opts.fn_preprocess = [[return require("fzf-lua.make_entry").preprocess]]
      end
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
---@return string?, integer?
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

  if opts.fn_reload and type(contents) == "string" then
    fzf_field_index = fzf_field_index or "{q}"
    local cmd = contents
    contents = function(args)
      local query = libuv.shellescape(args[1] or "")
      return FzfLua.core.expand_query(cmd, query)
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
    local co = coroutine.running()

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

    local on_write = function(data, cb)
      -- pipe can be nil when using a shell command with spawn
      -- and typing quickly, the process will terminate
      if not pipe then return end
      if not data then
        on_finish(nil, nil, 5)
        if cb then cb(nil) end
      else
        write_cb_count = write_cb_count + 1
        if type(data) == "table" then
          -- cb_write_lines was sent instead of cb_lines
          if fn_transform then
            data = vim.tbl_map(function(x) return fn_transform(x, opts) end, data)
          end
          data = table.concat(data, EOL) .. EOL
        end
        uv.write(pipe, tostring(data), function(err)
          write_cb_count = write_cb_count - 1
          if cb then cb(err) end
          if err then
            -- force close on error
            write_cb_count = 0
            on_finish(nil, nil, 2)
          end
          if write_cb_count == 0 and pipe_want_close then
            on_finish(nil, nil, 3)
          end
          -- if opts.throttle then uv.sleep(1000) end
          if opts.throttle then coroutine.resume(co) end
        end)
        -- TODO: why does this freeze fzf's UI?
        -- shouldn't the yield free the UI to update?
        -- if opts.throttle then uv.sleep(1000) end
        if opts.throttle then coroutine.yield() end
      end
    end

    if type(contents) == "string" then
      -- Use queue in libuv.spawn by default
      opts.use_queue = opts.use_queue == nil and true or opts.use_queue

      -- Throttle pipe writes by default
      -- opts.throttle = opts.throttle == nil and true or opts.throttle

      -- Terminate previously running command
      if opts.PidObject then
        libuv.process_kill(opts.PidObject:get())
        opts.PidObject:set(nil)
      end

      if opts.debug then
        -- coroutinify or we err with "yield across a C-call boundary" with throttle
        coroutine.wrap(function() on_write("[DEBUG] [st] " .. contents .. EOL) end)()
      end

      libuv.async_spawn({
        cwd = opts.cwd,
        cmd = contents,
        env = env,
        cb_finish = on_finish,
        cb_write_lines = on_write,
        cb_pid = function(pid) if opts.PidObject then opts.PidObject:set(pid) end end,
        process1 = opts.process1,
        profiler = opts.profiler,
        use_queue = opts.use_queue,
        EOL = EOL,
        -- Must send value, 'coroutinify' adds callback as last argument
        -- which will conflict with the 'fn_transform' argument
        -- send true to force line processing without transformation
      }, true)
    else
      -- callback with newline
      local on_write_nl = function(data, cb)
        data = data and tostring(data) .. EOL or nil
        return on_write(data, cb)
      end

      if type(contents) == "table" then
        vim.tbl_map(function(x) on_write_nl(x) end, contents)
        on_finish()
      elseif type(contents) == "function" then
        contents(on_write_nl, on_write, unpack(args))
      end
    end
  end, fzf_field_index or "", opts.debug)

  return cmd, id
end

---@param fn fun(item: string[], fzf_lines: integer, fzf_columns, integer): string|string[]?
---@param opts table
---@param fzf_field_index string?
---@return string, integer?
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
