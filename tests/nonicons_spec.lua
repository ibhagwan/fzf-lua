---@diagnostic disable: unused-local, unused-function
local MiniTest = require("mini.test")
local helpers = require("fzf-lua.test.helpers")
local assert = helpers.assert
local child = helpers.new_child_neovim()
local eq = helpers.expect.equality
local new_set = MiniTest.new_set
local exec_lua = child.lua

---@diagnostic disable-next-line: param-type-mismatch
local _nonicons_path = vim.fs.joinpath(vim.fn.stdpath("data"), "lazy", "nonicons.nvim")
if not vim.uv.fs_stat(_nonicons_path) then
  local site = vim.fs.joinpath(vim.fn.stdpath("data"), "site")
  for _, p in ipairs(vim.fn.globpath(site, "pack/*/opt/nonicons.nvim", false, true)) do
    if vim.uv.fs_stat(p) then
      _nonicons_path = vim.fn.resolve(p)
      break
    end
  end
end
if not vim.uv.fs_stat(_nonicons_path) then
  _nonicons_path = vim.fs.abspath(vim.fs.joinpath("deps", "nonicons.nvim"))
end

vim.opt.runtimepath:append(_nonicons_path)

local mapping = require("nonicons.mapping")
local resolve = require("nonicons.resolve")
local colors = require("nonicons.colors")

local function icon_char(name)
  return vim.fn.nr2char(mapping[name])
end

local function icon_color_gui(name)
  local c = colors[name]
  return c and c[1] or nil
end

local function icon_color_cterm(name)
  local c = colors[name]
  return c and tostring(c[2]) or nil
end

local function nonicons_are_same(name, expected)
  assert.are.same(child.lua_get([[{ M.devicons.get_devicon(...) }]], { name }), expected)
end

local function validate_nonicons(headless_child)
  local utils = require("fzf-lua").utils
  local nvchild = headless_child or child
  local state = nvchild.lua_get([[M.devicons.state()]])
  local icons = state.icons
  assert.is.True(utils.tbl_count(icons.by_filename) > 0)
  assert.is.True(utils.tbl_count(icons.by_ext) > 0)
  assert.are.equal(icons.by_filetype, nil)
  local ext_count = 0
  local ext_2part_count = 0
  for ext, _ in pairs(resolve.ext_map) do
    if ext:match(".+%.") then
      ext_2part_count = ext_2part_count + 1
    else
      ext_count = ext_count + 1
    end
  end
  assert.are.equal(utils.tbl_count(icons.by_ext), ext_count)
  assert.are.equal(utils.tbl_count(icons.by_ext_2part), ext_2part_count)
  assert.are.equal(utils.tbl_count(icons.by_filename), utils.tbl_count(resolve.filename_map))
end

local T = helpers.new_set_with_child(child, {
  hooks = {
    pre_case = function()
      child.o.termguicolors = true
      child.o.background = "dark"
      exec_lua([[M = { devicons = require("fzf-lua.devicons") }]])
    end,
  },
})

T["setup"] = new_set()

T["setup"]["explicit load"] = function()
  exec_lua("vim.opt.runtimepath:append(...)", { _nonicons_path })
  exec_lua([[M.devicons.load({ plugin = "nonicons" })]])
  eq(child.lua_get([[M.devicons.plugin_name()]]), "nonicons")
  validate_nonicons()
end

T["setup"]["icon lookups"] = function()
  exec_lua("vim.opt.runtimepath:append(...)", { _nonicons_path })
  exec_lua([[M.devicons.load({ plugin = "nonicons" })]])
  nonicons_are_same("foo.lua", { icon_char("lua"), icon_color_gui("lua") })
  nonicons_are_same("foo.py", { icon_char("python"), icon_color_gui("python") })
  nonicons_are_same("foo.rs", { icon_char("rust"), icon_color_gui("rust") })
  nonicons_are_same("foo.go", { icon_char("go"), icon_color_gui("go") })
  nonicons_are_same("foo.js", { icon_char("javascript"), icon_color_gui("javascript") })
  nonicons_are_same("foo.ts", { icon_char("typescript"), icon_color_gui("typescript") })
  nonicons_are_same(".gitignore", { icon_char("git-branch"), icon_color_gui("git-branch") })
  nonicons_are_same("dockerfile", { icon_char("docker"), icon_color_gui("docker") })
  nonicons_are_same("foo/", { icon_char("file-directory"), nil })
  nonicons_are_same("foo", { icon_char("file"), icon_color_gui("file") })
  nonicons_are_same("foo.unknown", { icon_char("file"), icon_color_gui("file") })
end

T["setup"]["2-part extensions"] = function()
  exec_lua("vim.opt.runtimepath:append(...)", { _nonicons_path })
  exec_lua([[M.devicons.load({ plugin = "nonicons" })]])
  nonicons_are_same("foo.d.ts", { icon_char("typescript"), icon_color_gui("typescript") })
  nonicons_are_same("foo.blade.php", { icon_char("php"), icon_color_gui("php") })
end

T["setup"]["headless RPC, vim.g.fzf_lua_server"] = function()
  exec_lua("vim.opt.runtimepath:append(...)", { _nonicons_path })
  exec_lua([[M.devicons.load({ plugin = "nonicons" })]])
  eq(child.lua_get([[M.devicons.plugin_name()]]), "nonicons")
  local fzf_lua_server = child.lua_get("vim.g.fzf_lua_server")
  eq(#fzf_lua_server > 0, true)
  local headless_child = helpers.new_child_neovim()
  headless_child.init()
  ---@diagnostic disable-next-line: preferred-local-alias
  headless_child.lua(string.format([==[
    _G._fzf_lua_is_headless = true
    _G._devicons_path = nil
    _G._fzf_lua_server = [[%s]]
    M = { devicons = require("fzf-lua.devicons") }
    M.devicons.load({ plugin = "srv", srv_plugin = "nonicons" })
  ]==], fzf_lua_server))
  eq(headless_child.lua_get([[_G._fzf_lua_server]]), fzf_lua_server)
  eq(headless_child.lua_get([[M.devicons.plugin_name()]]), "srv")
  eq(child.lua_get([[M.devicons.state()]]), headless_child.lua_get([[M.devicons.state()]]))
  validate_nonicons(headless_child)
  headless_child.stop()
end

T["setup"]["notermguicolors"] = function()
  exec_lua("vim.opt.runtimepath:append(...)", { _nonicons_path })
  child.o.termguicolors = false
  exec_lua([[M.devicons.load({ plugin = "nonicons" })]])
  nonicons_are_same("foo.lua", { icon_char("lua"), icon_color_cterm("lua") })
  nonicons_are_same("foo.py", { icon_char("python"), icon_color_cterm("python") })
  nonicons_are_same("foo", { icon_char("file"), icon_color_cterm("file") })
  nonicons_are_same("foo/", { icon_char("file-directory"), nil })
end

return T
