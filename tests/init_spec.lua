---@diagnostic disable: unused-local, unused-function
local MiniTest = require("mini.test")
local helpers = dofile("tests/helpers.lua")
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

local T = new_set({
  hooks = {
    pre_case = function()
      child.init()
      child.setup({})

      -- Make all showed messages full width
      child.o.cmdheight = 10
    end,
    post_once = child.stop,
  },
  -- n_retry = helpers.get_n_retry(2),
})

T["setup()"] = new_set()

T["setup()"]["setup global vars"] = function()
  -- Global vars
  eq(child.lua_get([[type(_G.FzfLua)]]), "table")
  eq(child.lua_get([[type(vim.g.fzf_lua_server)]]), "string")
  eq(child.lua_get([[type(vim.g.fzf_lua_directory)]]), "string")

  -- FzfLua command from "plugin/fzf-lua.lua"
  eq(child.fn.exists(":FzfLua") ~= 0, true)

  -- "autoload/fzf_lua.vim"
  eq(child.fn.exists("*fzf_lua#getbufinfo") ~= 0, true)
end

T["setup()"]["setup highlight groups"] = function()
  -- Highlight groups
  child.cmd("hi! clear")
  expect.match(child.cmd_capture("hi FzfLuaHeaderBind"), "xxx cleared")

  -- Default bg is dark
  child.setup()
  expect.match(child.cmd_capture("hi FzfLuaNormal"), "links to Normal")
  expect.match(child.cmd_capture("hi FzfLuaHeaderBind"), "guifg=BlanchedAlmond")

  child.o.bg = "light"
  child.cmd("hi! clear")
  child.setup()
  expect.match(child.cmd_capture("hi FzfLuaHeaderBind"), "guifg=MediumSpringGreen")
end

return T
