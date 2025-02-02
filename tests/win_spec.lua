---@diagnostic disable: unused-local, unused-function
local MiniTest = require("mini.test")
local helpers = require("fzf-lua.test.helpers")
local child = helpers.new_child_neovim()
local expect, eq = helpers.expect, helpers.expect.equality
local new_set = MiniTest.new_set

-- Helpers with child processes
--stylua: ignore start
---@format disable-next
local reload = function(config) child.unload(); child.setup(config) end
local set_cursor = function(...) return child.set_cursor(...) end
local get_cursor = function(...) return child.get_cursor(...) end
local set_lines = function(...) return child.set_lines(...) end
local get_lines = function(...) return child.get_lines(...) end
local type_keys = function(...) return child.type_keys(...) end
local sleep = function(ms) helpers.sleep(ms, child) end
--stylua: ignore end

local T = helpers.new_set_with_child(child)

T["win"] = new_set()

T["win"]["hide"] = new_set()

T["win"]["hide"]["ensure gc called after win hidden (#1782)"] = function()
  helpers.SKIP_IF_WIN()
  child.lua([[
    _G._gc_called = nil
    local utils = FzfLua.utils
    utils.setmetatable__gc = function(t, mt)
      local prox = newproxy(true)
      getmetatable(prox).__gc = function()
        _G._gc_called = true
        mt.__gc(t)
      end
      t[prox] = true
      return setmetatable(t, mt)
    end
  ]])
  eq(child.lua_get([[_G._fzf_load_called]]), vim.NIL)
  child.wait_until(function()
    child.lua(
      [[FzfLua.files{ previewer = 'builtin', winopts = { preview = { hidden = false  } } }]])
    child.wait_until(function()
      return child.lua_get([[_G._fzf_load_called]]) == true
    end, 5000)
    child.lua([[_G._fzf_load_called = nil]])
    child.lua([[FzfLua.win.hide()]])
    child.wait_until(function()
      return child.lua_get([[_G._fzf_lua_on_create]]) == vim.NIL
    end, 5000)
    child.lua([[collectgarbage('collect')]])
    return child.lua_get([[_G._gc_called]]) == true
  end, 100000)
end

T["win"]["hide"]["buffer deleted after win hidden (#1783)"] = function()
  eq(child.lua_get([[_G._fzf_lua_on_create]]), vim.NIL)
  child.lua([[FzfLua.files()]])
  child.wait_until(function()
    return child.lua_get([[_G._fzf_lua_on_create]]) == true
  end)
  child.lua([[FzfLua.win.hide()]])
  child.wait_until(function()
    return child.lua_get([[_G._fzf_lua_on_create]]) == vim.NIL
  end)
  child.lua([[
    vim.cmd("%bd!")
    FzfLua.files()
  ]])
  child.wait_until(function()
    return child.lua_get([[_G._fzf_lua_on_create]]) == true
  end)
end

return T
