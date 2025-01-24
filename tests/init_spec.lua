---@diagnostic disable: unused-local, unused-function
local MiniTest = require("mini.test")
local helpers = require("fzf-lua.test.helpers")
local child = helpers.new_child_neovim()
local expect, eq = helpers.expect, helpers.expect.equality
local new_set = MiniTest.new_set

local T = helpers.new_set_with_child(child, nil, { winopts = { col = 0, row = 1 } })

T["setup()"] = new_set()

T["setup()"]["setup global vars"] = function()
  -- Global vars
  eq(child.lua_get([[type(_G.FzfLua)]]), "table")
  eq(child.lua_get([[type(vim.g.fzf_lua_server)]]), "string")
  eq(child.lua_get([[type(vim.g.fzf_lua_directory)]]), "string")

  -- Test our custom setup call
  eq(child.lua_get([[type(_G.FzfLua.config.globals.winopts.on_create)]]), "function")
  eq(child.lua_get([[type(_G.FzfLua.config.globals.winopts.on_close)]]), "function")
  eq(child.lua_get([[type(_G.FzfLua.config.globals["winopts.on_create"])]]), "function")
  eq(child.lua_get([[type(_G.FzfLua.config.globals["winopts.on_close"])]]), "function")
  eq(child.lua_get([[_G.FzfLua.config.globals.winopts.col]]), 0)
  eq(child.lua_get([[_G.FzfLua.config.globals.winopts.row]]), 1)

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
