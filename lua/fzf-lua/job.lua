---@diagnostic disable-next-line: deprecated
local uv = vim.uv or vim.loop

local sysname = uv.os_uname().sysname
local _is_win = sysname:match("Windows") and true or false
local strbuf = (jit and vim.F.nil_wrap(require)("vim._core.stringbuffer") or
  require("fzf-lua.lib.stringbuffer"))

local M = {}

-- fix environ for uv.spawn
---@param cmd string
---@param opts uv.spawn.options | { env: table }
---@param on_exit? fun(code: integer, signal: integer)
---@return uv.uv_process_t handle
---@return integer pid
---@return uv.error_name? err_name
M.spawn = function(cmd, opts, on_exit)
  opts.env = (function()
    -- uv.spawn will override all env when table provided?
    -- steal from $VIMRUNTIME/lua/vim/_system.lua
    local env = vim.fn.environ() --- @type table<string,string>
    env["NVIM"] = vim.v.servername
    env["NVIM_LISTEN_ADDRESS"] = nil
    env = vim.tbl_extend("keep", opts.env or {}, env or {})
    local renv = {} --- @type string[]
    for k, v in pairs(env) do
      renv[#renv + 1] = string.format("%s=%s", k, tostring(v))
    end
    return renv
  end)()
  ---@diagnostic disable-next-line: param-type-mismatch, return-type-mismatch
  return assert(uv.spawn(cmd, opts, on_exit))
end

---@class fzf-lua.SpawnOpts
---@field opts? table TODO: maybe we can already serialize all data
---@field args? table
---@field cwd? string
---@field content string|table|function
---@field env? table
--- TODO: remove
---@field cb_finish? fun(code: integer, sig: integer, from: string, pid: integer)
---@field cb_write? fun(data: string, cb: fun(err: any): nil): nil
---@field output_pipe uv.uv_pipe_t|fzf-lua.Pipe
---@field cb_err? fun(data: string)
---@field EOL? string EOL write to output
---@field EOL_data? string EOL from proc output
---@field process1? boolean
---@field profiler? boolean

---@param cmd string|string[]
---@return string shell, string[] args, string EOL_data
local parse_cmd = function(cmd)
  local EOL_data = type(cmd) == "string"
      -- fd -0|--print0
      -- rg -0|--null
      -- grep -Z|--null
      -- find . -print0
      and (cmd:match("%s%-0")
        or cmd:match("%s%-?%-print0") -- -print0|--print0
        or cmd:match("%s%-%-null")
        or cmd:match("%s%-Z"))
      and "\0" or "\n"

  local shell = _is_win and "cmd.exe" or "sh"
  local args = _is_win and { "/d", "/e:off", "/f:off", "/v:on", "/c" } or { "-c" }
  if type(cmd) == "table" then
    if _is_win then
      vim.list_extend(args, cmd)
    else
      table.insert(args, table.concat(cmd, " "))
    end
  else
    table.insert(args, tostring(cmd))
  end

  return shell, args, EOL_data
end

---@class fzf-lua.Stream
---@field cb_finish? fun(code: integer, sig: integer, from: string, pid: integer)
---@field cb_write fun(data: string, cb: fun(err: any): nil): nil
---@field cb_err fun(data: string)
---@field output_pipe uv.uv_pipe_t|fzf-lua.Pipe
---@field EOL string

---@class fzf-lua.ProcStream: fzf-lua.Stream
---@field EOL_data string
---@field stdout uv.uv_pipe_t
---@field stderr uv.uv_pipe_t
---@field write_cb_count integer
---@field proc uv.uv_process_t
---@field pid integer
---@field sb string.buffer
---@field uuid integer|string Unique ID for the worker pool
---@field optstr string Serialized options for the worker
---@field work uv.luv_work_ctx_t
---@field co thread Coroutine for data chunking
---TODO: remove
local ProcStream = {}
ProcStream.__index = ProcStream

---@param data string a chunk of lines (end with EOL) to transform
---@return boolean, string
local transform_chunk = function(data, optstr, id)
  ---@diagnostic disable-next-line: return-type-mismatch
  return select(2, pcall(function()
    -- io.stderr:write("[DEBUG] worker init")
    if not _G.uuid then
      local __FILE__ = assert(debug.getinfo(1, "S")).source:gsub("^@", "")
      local lua = vim.fs.dirname(vim.fs.dirname(__FILE__))
      package.path = ("%s/?.lua;"):format(lua) .. package.path
      package.path = ("%s/?/init.lua;"):format(lua) .. package.path
      vim.fn = {}
      -- TODO: serialize a necessary helper module to access vim state
      vim.fn.has = function(feature)
        if feature:match("nvim%-0.12") then return 1 end
        if feature:match("nvim%-0.11") then return 1 end
        if feature:match("nvim%-0.10") then return 1 end
        if feature:match("nvim%-0.9") then return 1 end
        return 0
      end
      require("fzf-lua.make_entry")
      local devicons = vim.fs.normalize("~/lazy/nvim-web-devicons/lua")
      package.path = ("%s/?.lua;"):format(devicons) .. package.path
      package.path = ("%s/?/init.lua;"):format(devicons) .. package.path
      vim.F = require("vim.F")
      vim.base64 = require("fzf-lua.lib.base64")
      vim.o = {}
      setmetatable(vim.api, { __index = function() return function() end end })
    end
    if id ~= _G.uuid then -- refresh opts
      local opts = FzfLua.libuv.deserialize(optstr, false)
      local load_fn = FzfLua.libuv.load_fn
      local fn_preprocess = load_fn(opts.fn_preprocess) or opts.fn_preprocess
      if fn_preprocess then fn_preprocess(opts) end
      _G.trans = load_fn(opts.fn_transform) or opts.fn_transform
      _G.worker_opts = opts
      _G.uuid = id
    end

    local trans = _G.trans
    local opts = _G.worker_opts
    local ret = {}
    local start_idx = 1
    repeat
      local nl_idx = data:find(_G.EOL_data or "\n", start_idx, true)
      if nl_idx then
        local cr = data:byte(nl_idx - 1, nl_idx - 1) == 13 -- \r
        local line = data:sub(start_idx, nl_idx - (cr and 2 or 1))
        if trans then line = trans(line, opts) end
        if line then ret[#ret + 1] = line end
        start_idx = nl_idx + 1
      end
    until not nl_idx or start_idx > #data
    ret[#ret + 1] = ""
    return table.concat(ret, _G.EOL or "\n")
  end))
end

function ProcStream:can_finish()
  return not self.stdout:is_active() -- EOF signalled or process is aborting
      and self.write_cb_count == 0   -- no outstanding write callbacks
      and self.sb:__len() == 0
end

---@param handle uv.uv_handle_t
local safe_close = function(handle)
  if not handle:is_closing() then handle:close() end
end

---@param proc uv.uv_process_t
local gentle_kill = function(proc)
  if proc:is_closing() then return end
  proc:kill("sigterm")
  vim.defer_fn(function()
    if not proc:is_closing() then
      proc:kill("sigkill")
    end
  end, 200)
end

---@param code integer
---@param sig integer
---@param from string
---@param pid integer
function ProcStream:finish(code, sig, from, pid)
  local _ = code, sig, from, pid
  -- Uncomment to debug pipe closure timing issues (#1521)
  -- stdout:close(function() print("closed o") end)
  -- stderr:close(function() print("closed e") end)
  -- TODO: self.strbuf?
  safe_close(self.stdout)
  safe_close(self.stderr)
  safe_close(self.output_pipe)
  gentle_kill(self.proc)
  if self.cb_finish then self.cb_finish(code, sig, from, pid) end
end

---@param data string
function ProcStream:queue(data)
  self.write_cb_count = self.write_cb_count + 1
  self.work:queue(data, self.optstr, self.uuid)
end

---@param data? uv.threadargs
function ProcStream:write(data)
  self.write_cb_count = self.write_cb_count + 1
  self:on_work_done(data)
end

---@param data? uv.threadargs
function ProcStream:write_nl(data)
  if data == nil then return self:write(nil) end
  return self:write(tostring(data) .. self.EOL)
end

---@param data? uv.threadargs
function ProcStream:on_work_done(data)
  ---@diagnostic disable-next-line: param-type-mismatch
  -- write_cb_count = write_cb_count + 1
  self.output_pipe:write(data, function(err)
    self.write_cb_count = self.write_cb_count - 1
    if err then
      -- can fail with premature process kill
      -- assert(not err)
      self:finish(130, 0, "[write_cb: err]", self.pid)
    elseif self:can_finish() then
      -- on_exit callback already called and did not close the
      -- pipe due to write_cb_count>0, since this is the last
      -- call we can close the fzf pipe
      self:finish(0, 0, "[write_cb: finish]", self.pid)
    end
  end)
end

-- chunk lines by EOL, and dispatch to worker
function ProcStream:chunk_loop()
  local stop = 0
  local EOL = self.EOL_data:byte()
  local sb = self.sb
  while true do
    local len = sb:__len()
    local ref = sb:ref()
    if self.stdout:is_closing() then
      if len == 0 then return end
      if ref[len - 1] ~= EOL then sb:put(EOL) end -- make Session.transform happy
      return self:queue(sb:get())
    end
    local eol = len
    for i = len - 1, stop, -1 do
      if ref[i] == EOL then
        eol = i
        break
      end
    end
    if eol == len then
      stop = len -- no EOL found, wait for more data
      coroutine.yield()
    else
      self:queue(sb:get(eol + 1))
      stop = sb:__len()
    end
  end
  if self:can_finish() then self:finish(0, 0, "[EOF]", self.pid) end
end

---@param err? string
---@param data? string
function ProcStream:on_read(err, data)
  if err then
    return self:finish(130, 0, "[on_read: err]", self.pid)
  elseif data then
    self.sb:put(data)
  else -- EOF signalled, we can close the pipe
    self.stdout:close()
  end
  if self.sb:__len() > 100000 or self.stdout:is_closing() then
    assert(coroutine.resume(self.co))
  end
end

---@param err? string
---@param data? string
function ProcStream:on_err(err, data)
  if err then self:finish(130, 0, "[on_err]", self.pid) end
  if not data then return end
  self.cb_err(data)
end

---@param cmd string|string[]
---@param opts fzf-lua.SpawnOpts
---@return fzf-lua.ProcStream?
ProcStream.new = function(cmd, opts)
  local self = setmetatable({}, ProcStream)
  self.EOL = opts.EOL or "\n"
  local shell, args, EOL_data = parse_cmd(cmd)
  self.EOL_data = EOL_data
  self.stdout = assert(uv.new_pipe(false))
  self.stderr = assert(uv.new_pipe(false))
  self.write_cb_count = 0
  -- TODO: puc lua won't work here
  ---@type string.buffer
  self.sb = strbuf.new()

  self.uuid = uv.hrtime() -- distinguish two call when use worker pool
  local worker_opts = opts.opts or {}
  self.optstr = require("fzf-lua.libuv").serialize(worker_opts, false)
  assert(not not worker_opts.fn_transform ==
    not not require("fzf-lua.libuv").deserialize(self.optstr, false).fn_transform)
  self.work = uv.new_work(transform_chunk, function(data) self:on_work_done(data) end)
  self.co = coroutine.create(function() self:chunk_loop() end)
  self.output_pipe = opts.output_pipe
  self.cb_write = opts.cb_write
  self.cb_err = opts.cb_err or function(data) self:write(data) end
  self.cb_finish = opts.cb_finish

  self.proc, self.pid = M.spawn(shell, {
    args = args,
    stdio = { nil, self.stdout, self.stderr },
    cwd = opts.cwd,
    env = opts.env,
    verbatim = _is_win,
  }, function(code, signal)
    if self:can_finish() or code ~= 0 then
      -- Do not call `:read_stop` or `:close` here as we may have data
      -- reads outstanding on slower Windows machines (#1521), only call
      -- `finish` if all our `uv.write` calls are completed and the pipe
      -- is no longer active (i.e. no more read cb's expected)
      self:finish(code, signal, "[on_exit]", self.pid)
    end
    safe_close(self.proc)
  end)

  if not self.proc then
    -- uv.spawn failed, error will be in 'pid'
    -- call once to output the error message
    -- and second time to signal EOF (data=nil)
    -- more debug info here
    local cmdstr = (type(cmd) == "string" and cmd or table.concat(cmd, " "))
    self:on_err(nil, "Failed to spawn cmd: " .. cmdstr)
    self:on_err(nil, "Error: " .. tostring(self.pid))
    self:on_err(tostring(self.pid), nil)
    return
  end

  self.stdout:read_start(function(err, data) self:on_read(err, data) end)
  self.stderr:read_start(function(err, data) self:on_err(err, data) end)

  return self
end

---@class fzf-lua.LuaStream: fzf-lua.Stream
---@field content table|function
---@field args table
---@field EOL_data string
---@field stdout uv.uv_pipe_t
---@field stderr uv.uv_pipe_t
---@field write_cb_count integer
---@field opts fzf-lua.SpawnOpts
local LuaStream = {}
LuaStream.__index = LuaStream

---TODO: also use transform/worker for this path
---@param content table|function
---@param opts fzf-lua.SpawnOpts
LuaStream.new = function(content, opts)
  local self = setmetatable({}, LuaStream)
  self.content = content
  self.pid = -1 -- Fake PID for Lua sessions
  self.write_cb_count = 0
  self.finished = false
  self.output_pipe = opts.output_pipe
  self.cb_finish = opts.cb_finish
  self.EOL = opts.EOL or "\n"
  self.args = opts.args or {}
  self.cb_err = opts.cb_err or function(data)
    self.write_cb_count = self.write_cb_count + 1
    self:write(data)
  end
  self.cb_finish = opts.cb_finish
  vim.schedule(function() self:run() end)
  return self
end

function LuaStream:can_finish()
  return not self.output_pipe:is_active() and self.finished and self.write_cb_count == 0
end

function LuaStream:finish()
  safe_close(self.output_pipe)
  if self.cb_finish then self.cb_finish(0, 0, "[finish]", self.pid) end
end

function LuaStream:write(data, cb)
  if data == nil then
    self.finished = true
    if cb then cb(nil) end
    self:finish()
    return
  end

  self.write_cb_count = self.write_cb_count + 1
  self.output_pipe:write(tostring(data), function(err)
    self.write_cb_count = self.write_cb_count - 1
    if cb then cb(err) end
    if err or self:can_finish() then self:finish() end
  end)
end

function LuaStream:write_nl(data, cb)
  if data == nil then return self:write(nil, cb) end
  return self:write(tostring(data) .. self.EOL, cb)
end

function LuaStream:run()
  local contents = self.content

  -- Wrap execution in xpcall for robust error handling
  local ok, err = xpcall(function()
    if type(contents) == "table" then
      vim.tbl_map(function(x) self:write_nl(x) end, contents)
      return self:write(nil) -- Signal EOF
    end
    if type(contents) == "function" then
      contents(function(...) self:write_nl(...) end,
        function(...) self:write(...) end,
        vim.F.unpack_len(self.args or {}))
    end
  end, debug.traceback)

  if not ok then
    if self.cb_err then self.cb_err(err) end
    self.finished = true
    self:finish()
  end
end

---@param opts fzf-lua.SpawnOpts
---@return fzf-lua.Stream?
M.transform = function(opts)
  if type(opts.content) == "string" then return ProcStream.new(opts.content, opts) end
  return LuaStream.new(opts.content, opts)
end

return M
