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

T["files()"]["start and abort"] = new_set({ parametrize = { { "<esc>" }, { "<c-c>" } } }, {
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
    -- Ignore last "-- TERMINAL --" line and paths on Windows (separator is "\")
    local ignore_lines = { 28 }
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

T["files()"]["previewer"] = new_set({ parametrize = { { "ci" }, { "builtin" } } }, {
  function(previewer)
    if previewer == "builtin" then
      -- Windows is too slow to test this without hacks and waits
      helpers.SKIP_IF_WIN()
    end
    if previewer == "ci" then previewer = false end
    child.lua(([[FzfLua.files({
      previewer = %s,
      cwd_prompt = false,
      cmd = "rg --files --sort=path",
    })]]):format(previewer == "builtin"
      and [["builtin"]]
      or [[require("fzf-lua.test.previewer")]]
    ))
    eq(child.lua_get([[_G._fzf_lua_on_create]]), true)
    child.wait_until(function()
      return child.lua_get([[_G._fzf_load_called]]) == true
    end)
    -- Ignore last "-- TERMINAL --" line and paths on Windows (separator is "\")
    local ignore_lines = { 28 }
    if helpers.IS_WIN() then
      table.insert(ignore_lines, 12)
    end
    child.wait_until(function()
      return child.lua_get([[FzfLua.utils.fzf_winobj()._previewer.last_entry]]) == "LICENSE"
    end)
    child.expect_screen_lines({ ignore_lines = ignore_lines })
    child.type_keys("<c-c>")
    child.wait_until(function()
      return child.lua_get([[_G._fzf_lua_on_create]]) == vim.NIL
    end)
  end,
})

T["files()"]["icons"] = new_set({ parametrize = { { "devicons" }, { "mini" } } })

T["files()"]["icons"]["defaults"] = new_set({ parametrize = { { "+attrs" }, { "-attrs" } } }, {
  function(icons, attrs)
    attrs = attrs == "+attrs" and true or false
    if icons == "mini" then
      -- TODO: mini bugged on win returning wrong icon for Makefile / md
      helpers.SKIP_IF_WIN()
    end
    if attrs then
      helpers.SKIP_IF_NOT_STABLE()
      helpers.SKIP_IF_WIN()
    end
    local plugin = icons == "mini" and "mini.nvim" or "nvim-web-devicons"
    local path = vim.fs.joinpath(vim.fn.stdpath("data"), "lazy", plugin)
    if not vim.uv.fs_stat(path) then
      path = vim.fs.joinpath("deps", plugin)
    end
    child.lua("vim.opt.runtimepath:append(...)", { path })
    child.lua(([[require("%s").setup({})]]):format(icons == "mini" and "mini.icons" or plugin))
    -- sort output and remove cwd in prompt as will be different on CI
    child.lua(([[FzfLua.files({
      previewer = false,
      file_icons = "%s",
      cwd_prompt = false,
      cmd = "rg --files --sort=path",
      winopts = { preview = { scrollbar = false } },
    })]]):format(icons))
    eq(child.lua_get([[_G._fzf_lua_on_create]]), true)
    child.wait_until(function()
      return child.lua_get([[_G._fzf_load_called]]) == true
    end)
    local ignore_lines = { 28 }
    if helpers.IS_WIN() then
      for i = 12, 21 do table.insert(ignore_lines, i) end
    end
    if attrs then
      child.expect_screenshot({ ignore_lines = ignore_lines })
    else
      child.expect_screen_lines({ ignore_lines = ignore_lines })
    end
    child.type_keys("<c-c>")
    child.wait_until(function()
      return child.lua_get([[_G._fzf_lua_on_create]]) == vim.NIL
    end)
  end,
})

return T
