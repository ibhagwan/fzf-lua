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
    -- sort output and remove cwd in prompt as will be different on CI
    child.lua([[FzfLua.files({
      previewer = false,
      cwd_prompt = false,
      cmd = "rg --files --sort=path",
    })]])
    eq(child.lua_get([[_G._fzf_lua_on_create]]), true)
    child.wait_until(function()
      return child.lua_get([[_G._fzf_load_called]]) == true
    end)
    -- Ignore paths on Windows as separator is "\"
    local ignore_lines = {}
    if helpers.IS_WIN() then
      for i = 12, 21 do table.insert(ignore_lines, i) end
    end
    -- NOTE: we compare screen lines without "attrs", this way
    -- we can test on stable, nightly and windows
    -- child.expect_screenshot({ ignore_lines = ignore_lines })
    child.expect_screen_lines({ ignore_lines = ignore_lines })
    child.type_keys(key)
    child.wait_until(function()
      return child.lua_get([[_G._fzf_lua_on_create]]) == vim.NIL
    end)
  end,
})

T["files()"]["defaults with icons"] = function()
  helpers.SKIP_IF_WIN()
  helpers.SKIP_IF_NOT_STABLE()
  -- sort output and remove cwd in prompt as will be different on CI
  child.lua([[FzfLua.files({ cwd_prompt = false, cmd = "rg --files --sort=path" })]])
  eq(child.lua_get([[_G._fzf_lua_on_create]]), true)
  child.wait_until(function()
    return child.lua_get([[_G._fzf_load_called]]) == true
  end)
  -- Ignore path "autoload/fzf_lua.vim" on Windows as separator is "\"
  local ignore_lines = helpers.IS_WIN() and { 12 } or {}
  child.expect_screenshot({ ignore_lines = ignore_lines })
  child.type_keys("<c-c>")
  child.wait_until(function()
    return child.lua_get([[_G._fzf_lua_on_create]]) == vim.NIL
  end)
end

return T
