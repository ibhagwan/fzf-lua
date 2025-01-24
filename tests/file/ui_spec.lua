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

T["files()"] = new_set()

T["files()"]["start and abort <esc>"] = new_set({
  parametrize = { { "<esc>" }, { "<c-c>" } } }, {
  function(key)
    helpers.SKIP_IF_WIN()
    -- Global vars
    child.lua([[FzfLua.files()]])
    eq(child.lua_get([[_G._fzf_lua_on_create]]), true)
    child.wait_until(function()
      return child.lua_get([[_G._fzf_load_called]]) == true
    end)
    helpers.SKIP_IF_NOT_STABLE()
    -- Ignore the prompt path and info line since the CI machine
    -- path will be different as well as the file count
    child.expect_screenshot({ ignore_lines = { 4 } })
    child.type_keys(key)
    child.wait_until(function()
      return child.lua_get([[_G._fzf_lua_on_create]]) == vim.NIL
    end)
  end,
})

return T
