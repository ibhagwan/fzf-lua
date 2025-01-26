---@diagnostic disable: unused-local, unused-function
local MiniTest = require("mini.test")
local helpers = require("fzf-lua.test.helpers")
local assert = helpers.assert
local child = helpers.new_child_neovim()
local expect, eq = helpers.expect, helpers.expect.equality
local new_set = MiniTest.new_set

local _devicons_path = vim.fs.joinpath(vim.fn.stdpath("data"), "lazy", "nvim-web-devicons")
if not vim.uv.fs_stat(_devicons_path) then
  _devicons_path = vim.fs.joinpath("deps", "nvim-web-devicons")
end

vim.opt.runtimepath:append(_devicons_path)

local function validate_devicons(headless_child)
  local utils = require("fzf-lua").utils
  local nvchild = headless_child or child
  local state = nvchild.lua_get([[M.devicons.state()]])
  local icons = state.icons
  local theme = {
    icons_by_filename = child.lua_get([[require("nvim-web-devicons").get_icons_by_filename()]]),
    icons_by_file_extension =
        child.lua_get([[require("nvim-web-devicons").get_icons_by_extension()]])
  }
  assert.are.same(state.default_icon, { icon = "", color = "#6d8086" })
  assert.are.same(state.dir_icon, { icon = "", color = nil })
  assert.is.True(utils.tbl_count(icons.ext_has_2part) > 4)
  assert.is.True(utils.tbl_count(icons.by_ext_2part) > 8)
  -- TODO: sometimes fails with:
  --   Failed expectation for equality.
  --   Left:  180
  --   Right: 181
  --   Traceback:
  --     tests\devicons_spec.lua:30
  --     tests\devicons_spec.lua:69
  -- assert.are.equal(utils.tbl_count(icons.by_filename), utils.tbl_count(theme.icons_by_filename))
  assert.are.equal(utils.tbl_count(icons.by_ext) + utils.tbl_count(icons.by_ext_2part),
    utils.tbl_count(theme.icons_by_file_extension))
end

local function devicons_are_same(name, expected)
  local from_child = child.lua_get([[{ M.devicons.get_devicon(...) }]], { name })
  from_child[2] = from_child[2] and from_child[2]:upper() or from_child[2]
  expected[2] = expected[2] and expected[2]:upper() or expected[2]
  assert.are.same(from_child, expected)
end

local T = helpers.new_set_with_child(child, {
  hooks = {
    pre_case = function()
      child.o.termguicolors = true
      child.o.background = "dark"
      child.lua([[M = { devicons = require("fzf-lua.devicons") }]])
    end,
  },
})

T["setup()"] = new_set()

T["setup()"]["verify lazy load"] = function()
  child.lua("vim.opt.runtimepath:append(...)", { _devicons_path })
  -- Shouldn't be loaded after setup
  eq(child.lua_get("type(M.devicons)"), "table")
  eq(child.lua_get("package.loaded['nvim-web-devicons']"), vim.NIL)
  -- eq(child.lua_get([[type(require "nvim-web-devicons")]]), "table")
end

T["setup()"]["auto-detect"] = function()
  child.lua("vim.opt.runtimepath:append(...)", { _devicons_path })
  child.lua([[
    require("nvim-web-devicons").setup({})
    M.devicons.load()
  ]])
  eq(child.lua_get([[M.devicons.plugin_name()]]), "devicons")
  validate_devicons()
end

T["setup()"]["_G.devicons_path"] = function()
  child.lua(string.format([==[
    _G._devicons_path = [[%s]]
    _G._fzf_lua_server = nil
    _G._fzf_lua_is_headless = true
    M.devicons.load()
  ]==], _devicons_path))
  eq(child.lua_get([[M.devicons.plugin_name()]]), "devicons")
  validate_devicons()
end

T["setup()"]["headless RPC, vim.g.fzf_lua_server"] = function()
  child.lua("vim.opt.runtimepath:append(...)", { _devicons_path })
  child.lua([[M.devicons.load()]])
  eq(child.lua_get([[M.devicons.plugin_name()]]), "devicons")
  local fzf_lua_server = child.lua_get("vim.g.fzf_lua_server")
  eq(#fzf_lua_server > 0, true)
  local headless_child = helpers.new_child_neovim()
  headless_child.init()
  headless_child.lua(string.format([==[
    _G._fzf_lua_is_headless = true
    _G._devicons_path = nil
    _G._fzf_lua_server = [[%s]]
    M = { devicons = require("fzf-lua.devicons") }
    M.devicons.load({ plugin = "srv", srv_plugin = "devicons" })
  ]==], fzf_lua_server))
  eq(headless_child.lua_get([[_G._fzf_lua_server]]), fzf_lua_server)
  eq(headless_child.lua_get([[M.devicons.plugin_name()]]), "srv")
  eq(child.lua_get([[M.devicons.state()]]), headless_child.lua_get([[M.devicons.state()]]))
  validate_devicons(headless_child)
  headless_child.stop()
end

T["setup()"]["vim.o.background=dark"] = function()
  child.lua("vim.opt.runtimepath:append(...)", { _devicons_path })
  child.o.background = "dark"
  child.lua([[M.devicons.load()]])
  devicons_are_same("foo/", { "", nil })
  devicons_are_same("", { "", "#6d8086" })
  devicons_are_same(".", { "", "#6d8086" })
  devicons_are_same("f.abc", { "", "#6d8086" })
  devicons_are_same("f.", { "", "#6d8086" })
  devicons_are_same(".f", { "", "#6d8086" })
  devicons_are_same("foo", { "", "#6d8086" })
  -- by filename
  devicons_are_same(".editorconfig", { "", "#fff2f2" })
  devicons_are_same("/path/.bashrc", { "", "#89e051" })
  -- by 2-part extension
  devicons_are_same("foo.bar.jsx", { "", "#20c2e3" })
  devicons_are_same("foo.spec.jsx", { "", "#20c2e3" })
  devicons_are_same("foo.config.ru", { "", "#701516" })
  -- by 1-part extensions
  devicons_are_same("foo.lua", { "", "#51a0cf" })
  devicons_are_same("foo.py", { "", "#ffbc03" })
  devicons_are_same("foo.r", { "󰟔", "#2266ba" })
  devicons_are_same("foo.R", { "󰟔", "#2266ba" })
end

T["setup()"]["vim.o.background=light"] = function()
  child.lua("vim.opt.runtimepath:append(...)", { _devicons_path })
  -- NOTE: test bg change with a loaded pkg
  child.o.background = "dark"
  child.lua([[M.devicons.load()]])
  child.o.background = "light"
  child.lua([[M.devicons.load()]])
  devicons_are_same("foo/", { "", nil })
  devicons_are_same("", { "", "#6d8086" })
  devicons_are_same(".", { "", "#6d8086" })
  devicons_are_same("f.abc", { "", "#6d8086" })
  devicons_are_same("f.", { "", "#6d8086" })
  devicons_are_same(".f", { "", "#6d8086" })
  devicons_are_same("foo", { "", "#6d8086" })
  -- by filename
  devicons_are_same(".editorconfig", { "", "#333030" })
  devicons_are_same("/path/.bashrc", { "", "#447028" })
  -- by 2-part extension
  devicons_are_same("foo.bar.jsx", { "", "#158197" })
  devicons_are_same("foo.spec.jsx", { "", "#158197" })
  devicons_are_same("foo.config.ru", { "", "#701516" })
  -- by 1-part extensions
  devicons_are_same("foo.lua", { "", "#366b8a" })
  devicons_are_same("foo.py", { "", "#805e02" })
  devicons_are_same("foo.r", { "󰟔", "#1a4c8c" })
  devicons_are_same("foo.R", { "󰟔", "#1a4c8c" })
end

T["setup()"]["notermguicolors (dark)"] = function()
  child.lua("vim.opt.runtimepath:append(...)", { _devicons_path })
  child.o.background = "dark"
  child.o.termguicolors = false
  child.lua([[M.devicons.load()]])
  devicons_are_same("foo/", { "", nil })
  devicons_are_same("", { "", "66" })
  devicons_are_same(".", { "", "66" })
  devicons_are_same("f.abc", { "", "66" })
  devicons_are_same("f.", { "", "66" })
  devicons_are_same(".f", { "", "66" })
  devicons_are_same("foo", { "", "66" })
  -- by filename
  devicons_are_same(".editorconfig", { "", "255" })
  devicons_are_same("/path/.bashrc", { "", "113" })
  -- by 2-part extension
  devicons_are_same("foo.bar.jsx", { "", "45" })
  devicons_are_same("foo.spec.jsx", { "", "45" })
  devicons_are_same("foo.config.ru", { "", "52" })
  -- by 1-part extensions
  devicons_are_same("foo.lua", { "", "74" })
  devicons_are_same("foo.py", { "", "214" })
  devicons_are_same("foo.r", { "󰟔", "25" })
  devicons_are_same("foo.R", { "󰟔", "25" })
end
T["setup()"]["notermguicolors (light)"] = function()
  child.lua("vim.opt.runtimepath:append(...)", { _devicons_path })
  child.o.background = "light"
  child.o.termguicolors = false
  child.lua([[M.devicons.load()]])
  devicons_are_same("foo/", { "", nil })
  devicons_are_same("", { "", "66" })
  devicons_are_same(".", { "", "66" })
  devicons_are_same("f.abc", { "", "66" })
  devicons_are_same("f.", { "", "66" })
  devicons_are_same(".f", { "", "66" })
  devicons_are_same("foo", { "", "66" })
  -- by filename
  devicons_are_same(".editorconfig", { "", "236" })
  devicons_are_same("/path/.bashrc", { "", "22" })
  -- by 2-part extension
  devicons_are_same("foo.bar.jsx", { "", "31" })
  devicons_are_same("foo.spec.jsx", { "", "31" })
  devicons_are_same("foo.config.ru", { "", "52" })
  -- by 1-part extensions
  devicons_are_same("foo.lua", { "", "24" })
  devicons_are_same("foo.py", { "", "94" })
  devicons_are_same("foo.r", { "󰟔", "25" })
  devicons_are_same("foo.R", { "󰟔", "25" })
end

return T
