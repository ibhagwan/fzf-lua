local shell = require("fzf-lua.shell")
-- local MiniTest = require("mini.test")
local ok = function(f, ...) assert(pcall(f, ...)) end
local err = function(f, ...)
  local _ok, _err = pcall(f, ...)
  assert(not _ok, _err)
end

describe("Testing shell module", function()
  it("check_upvalue", function()
    ok(shell.check_upvalue, function() end, "no upvalue")

    err(shell.check_upvalue, (function()
      local upvalue
      return function() return upvalue.index end
    end)(), "index upvalue")

    err(shell.check_upvalue, (function()
      local upvalue
      return function() return upvalue() end
    end)(), "call upvalue")
  end)
end)
