--- credit to https://github.com/neovim/neovim/blob/534544cbf7ac92aef44336cc9da1bfc02a441e6e/test/functional/testnvim/exec_lua.lua

--- @param f function
--- @return table<string,any>
local function get_upvalues(f)
  local i = 1
  local upvalues = {} --- @type table<string,any>
  while true do
    local n, v = debug.getupvalue(f, i)
    if not n then
      break
    end
    upvalues[n] = v
    i = i + 1
  end
  return upvalues
end

--- @param f function
--- @param upvalues table<string,any>
local function set_upvalues(f, upvalues)
  local i = 1
  while true do
    local n = debug.getupvalue(f, i)
    if not n then
      break
    end
    if upvalues[n] then
      debug.setupvalue(f, i, upvalues[n])
    end
    i = i + 1
  end
end

--- @param messages string[]
--- @param ... ...
local function add_print(messages, ...)
  local msg = {} --- @type string[]
  for i = 1, select("#", ...) do
    msg[#msg + 1] = tostring(select(i, ...))
  end
  table.insert(messages, table.concat(msg, "\t"))
end

local invalid_types = {
  ["thread"] = true,
  ["function"] = true,
  ["userdata"] = true,
}

--- @param r any[]
local function check_returns(r)
  for k, v in pairs(r) do
    if invalid_types[type(v)] then
      error(
        string.format(
          "Return index %d with value '%s' of type '%s' cannot be serialized over RPC",
          k,
          tostring(v),
          type(v)
        ),
        2
      )
    end
  end
end

local M = {}

--- This is run in the context of the remote Nvim instance.
--- @param bytecode string
--- @param upvalues table<string,any>
--- @param ... any[]
--- @return any[] result
--- @return table<string,any> upvalues
--- @return string[] messages
function M.handler(bytecode, upvalues, ...)
  local messages = {} --- @type string[]
  local orig_print = _G.print

  function _G.print(...)
    add_print(messages, ...)
    return orig_print(...)
  end

  local f = assert(loadstring(bytecode))

  set_upvalues(f, upvalues)

  -- Run in pcall so we can return any print messages
  local ret = { pcall(f, ...) } --- @type any[]

  _G.print = orig_print

  local new_upvalues = get_upvalues(f)

  -- Check return value types for better error messages
  check_returns(ret)

  return ret, new_upvalues, messages
end

--- @param child MiniTest.child
--- @param lvl integer
--- @param code function
--- @param arg table
function M.run(child, lvl, code, arg)
  local rv = child.lua(
    [[return { require('fzf-lua.test.exec_lua').handler(...) }]],
    { string.dump(code), get_upvalues(code), unpack(arg or {}) })

  --- @type any[], table<string,any>, string[]
  local ret, upvalues, messages = unpack(rv)

  for _, m in ipairs(messages) do
    print(m)
  end

  if not ret[1] then
    error(ret[2], 2)
  end

  -- Update upvalues
  if next(upvalues) then
    local caller = debug.getinfo(lvl)
    local i = 0

    -- On PUC-Lua, if the function is a tail call, then func will be nil.
    -- In this case we need to use the caller.
    while not caller.func do
      i = i + 1
      caller = debug.getinfo(lvl + i)
    end
    set_upvalues(caller.func, upvalues)
  end

  ---@diagnostic disable-next-line: incomplete-signature-doc
  return unpack(ret, 2, table.maxn(ret))
end

local function save_upvalues(v, t)
  if type(v) == "userdata" or type(v) == "thread" then
    error("unsupported upvalue type: " .. type(v))
  elseif type(v) == "function" then
    -- hopefully serpent serialize/deserialize?? don't change the string.dump id
    local bytecode = string.dump(v)
    -- TODO: same body but with different upv, still have the same id...
    -- TODO: support function upv?
    local upvalues = get_upvalues(v)
    if not vim.tbl_isempty(upvalues) then
      -- print("save", vim.fn.sha256(vim.base64.encode(bytecode)), vim.inspect(upvalues))
      t[bytecode] = upvalues
    end
  elseif type(v) == "table" then
    for _, e in pairs(v) do
      save_upvalues(e, t)
    end
  end
end

-- TODO: upvalues
local function load_upvalues(v, t)
  if type(v) == "function" then
    local bytecode = string.dump(v)
    local upvalues = t[bytecode]
    -- this don't seem work for headless wrapper?
    if upvalues then
      -- print("load", vim.fn.sha256(vim.base64.encode(bytecode)), vim.inspect(upvalues))
      return function(...)
        return unpack((M.handler(bytecode, upvalues, ...)))
      end
    end
  end
  if type(v) == "table" then
    for k, e in pairs(v) do
      v[k] = load_upvalues(e, t)
    end
  end
  return v
end

---@param s string
---@return table
M.deserialize = function(s)
  local _, args = require("fzf-lua.lib.serpent").load(s, { safe = false })
  assert(type(args) == "table", "args should be table")
  for i, v in ipairs(args) do
    args[i] = load_upvalues(v, args)
  end
  return args
end

---@param ...any
---@return string
M.serialize = function(...)
  local args = { ... }
  for _, v in ipairs(args) do
    save_upvalues(v, args)
  end
  return require("fzf-lua.lib.serpent").block(args, { comment = false, sortkeys = false })
end

return M
