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
    local screen_opts = { ignore_lines = { 28 }, normalize_paths = helpers.IS_WIN() }
    -- NOTE: we compare screen lines without "attrs"
    -- so we can test on stable, nightly and windows
    -- child.expect_screenshot(screen_opts)
    child.expect_screen_lines(screen_opts)
    child.type_keys(key)
    child.wait_until(function()
      return child.lua_get([[_G._fzf_lua_on_create]]) == vim.NIL
    end)
  end,
})

T["files()"]["previewer"] = new_set({ parametrize = { { "ci" }, { "builtin" } } }, {
  function(previewer)
    child.lua(([[FzfLua.files({
      previewer = %s,
      cwd_prompt = false,
      cmd = "rg --files --sort=path",
      winopts = { preview = { scrollbar = false } },
    })]]):format(previewer == "builtin"
      and [["builtin"]]
      or [[require("fzf-lua.test.previewer")]]
    ))
    eq(child.lua_get([[_G._fzf_lua_on_create]]), true)
    child.wait_until(function()
      return child.lua_get([[_G._fzf_load_called]]) == true
    end)
    -- Ignore last "-- TERMINAL --" line and paths on Windows (separator is "\")
    local screen_opts = { ignore_lines = { 28 }, normalize_paths = helpers.IS_WIN() }
    child.wait_until(function()
      return child.lua_get([[FzfLua.utils.fzf_winobj()._previewer.last_entry]]) == "LICENSE"
    end)
    child.expect_screen_lines(screen_opts)
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
    local screen_opts = { ignore_lines = { 28 }, normalize_paths = helpers.IS_WIN() }
    if attrs then
      child.expect_screenshot(screen_opts)
    else
      child.expect_screen_lines(screen_opts)
    end
    child.type_keys("<c-c>")
    child.wait_until(function()
      return child.lua_get([[_G._fzf_lua_on_create]]) == vim.NIL
    end)
  end,
})

return T
