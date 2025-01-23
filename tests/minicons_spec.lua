---@diagnostic disable: unused-local, unused-function
local MiniTest = require("mini.test")
local helpers = dofile("tests/helpers.lua")
local assert = helpers.assert
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

-- Setup mini.icons locally
local _mini_path = vim.fs.joinpath(vim.fn.stdpath("data"), "lazy", "mini.nvim")
if not vim.uv.fs_stat(_mini_path) then
  _mini_path = vim.fs.joinpath("deps", "mini.nvim")
end

local MiniIcons = require("mini.icons")
MiniIcons.setup()

local T = new_set({
  hooks = {
    pre_case = function()
      child.init()
      child.setup({})
      child.lua([[M = { devicons = require("fzf-lua.devicons") }]])

      -- Make all showed messages full width
      child.o.cmdheight = 10
      child.o.termguicolors = true
      child.o.background = "dark"
    end,
    post_case = function()
      child.unload()
    end,
    post_once = child.stop,
  },
  -- n_retry = helpers.get_n_retry(2),
})

local function mini_are_same(category, name, expected)
  assert.are.same(child.lua_get([[{ M.devicons.get_devicon(...) }]], { name }), expected)
end

local function validate_mini(headless_child)
  local utils = require("fzf-lua").utils
  local nvchild = headless_child or child
  local state = nvchild.lua_get([[M.devicons.state()]])
  local icons = state.icons
  if not headless_child then
    assert.are.equal(utils.tbl_count(icons.by_filename), utils.tbl_count(MiniIcons.list("file")))
    assert.are.equal(utils.tbl_count(icons.by_ext) + utils.tbl_count(icons.by_ext_2part),
      -- +4 extensions that are causing issues in `vim.filetype.match`
      -- https://github.com/ibhagwan/fzf-lua/issues/1358#issuecomment-2254215160
      utils.tbl_count(MiniIcons.list("extension")) + 4)
  end
  assert.is.True(utils.tbl_count(icons.ext_has_2part) == 0)
  assert.is.True(utils.tbl_count(icons.by_ext_2part) == 0)
  mini_are_same("file", "foo", { "󰈔", "" })
  mini_are_same("directory", "foo/", { "󰉋", "#8cf8f7" })
  mini_are_same("file", "foo.lua", { "󰢱", "#8cf8f7" })
  mini_are_same("file", "foo.yml", { "", "#e0e2ea" })
  mini_are_same("file", "foo.yaml", { "", "#e0e2ea" })
  mini_are_same("file", "foo.toml", { "", "#fce094" })
  mini_are_same("file", "foo.txt", { "󰦪", "#fce094" })
  mini_are_same("file", "foo.text", { "󰦪", "#fce094" })
  mini_are_same("file", "Makefile", { "󱁤", "" })
  mini_are_same("file", "makefile", { "󱁤", "" })
  mini_are_same("file", "LICENSE", { "", "#a6dbff" })
  mini_are_same("file", "license", { "󰈔", "" })
  mini_are_same("file", "foo.md", { "󰍔", "" })
  mini_are_same("file", "README.md", { "", "#fce094" })
end

T["setup()"] = new_set()

T["setup()"]["verify lazy load"] = function()
  eq(type(MiniIcons), "table")
  -- Shouldn't be loaded after setup
  eq(child.lua_get("type(M.devicons)"), "table")
  eq(child.lua_get("_G.MiniIcons"), vim.NIL)
end

T["setup()"]["auto-detect"] = function()
  child.lua([[
    require("mini.icons").setup({})
    M.devicons.load()
  ]])
  eq(child.lua_get([[type(_G.MiniIcons)]]), "table")
  eq(child.lua_get([[M.devicons.plugin_name()]]), "mini")
  validate_mini()
end

T["setup()"]["hlgroup modifications"] = function()
  child.lua([[
    require("mini.icons").setup({})
    vim.api.nvim_set_hl(0, "MiniIconsGrey", { default = false, link = "Directory" })
    M.devicons.load({ mode = "gui" })
  ]])
  local hexcol = child.lua_get([[FzfLua.utils.hexcol_from_hl("Directory", "fg", "gui")]])
  mini_are_same("file", "foo", { "󰈔", hexcol })
  mini_are_same("file", "Makefile", { "󱁤", hexcol })
  mini_are_same("file", "makefile", { "󱁤", hexcol })
  mini_are_same("file", "license", { "󰈔", hexcol })
  mini_are_same("file", "foo.md", { "󰍔", hexcol })
  -- vim.api.nvim_set_hl(0, "MiniIconsGrey", { default = false })
end

T["setup()"]["devicons mock"] = function()
  child.lua([[
    require("mini.icons").mock_nvim_web_devicons()
    M.devicons.load({ mode = "gui" })
  ]])
  eq(child.lua_get([[M.devicons.__DEVICONS:is_mock()]]), true)
  eq(child.lua_get([[M.devicons.plugin_name()]]), "mini")
  validate_mini()
end

T["setup()"]["headless RPC, vim.g.fzf_lua_server"] = function()
  child.lua("vim.opt.runtimepath:append(...)", { _mini_path })
  child.lua([[
    require("mini.icons").setup({})
    M.devicons.load()
  ]])
  eq(child.lua_get([[M.devicons.plugin_name()]]), "mini")
  validate_mini()
  local fzf_lua_server = child.lua_get("vim.g.fzf_lua_server")
  eq(#fzf_lua_server > 0, true)
  local headless_child = helpers.new_child_neovim()
  headless_child.init()
  headless_child.lua(string.format([==[
    _G._fzf_lua_is_headless = true
    _G._devicons_path = nil
    _G._fzf_lua_server = [[%s]]
    M = { devicons = require("fzf-lua.devicons") }
    M.devicons.load({ plugin = "srv", srv_plugin = "mini" })
  ]==], fzf_lua_server))
  eq(headless_child.lua_get([[_G._fzf_lua_server]]), fzf_lua_server)
  eq(headless_child.lua_get([[M.devicons.plugin_name()]]), "srv")
  eq(child.lua_get([[M.devicons.state()]]), headless_child.lua_get([[M.devicons.state()]]))
  validate_mini(headless_child)
  headless_child.stop()
end

return T
