---@diagnostic disable: undefined-global
local fzf = require("fzf-lua")
local path = fzf.path
local utils = fzf.utils

describe("Testing MiniIcons", function()
  -- package runtime path
  local mini_path = path.join({ vim.fn.stdpath("data"), "lazy", "mini.nvim" })
  local devicons = require("fzf-lua.devicons")

  vim.opt.termguicolors = true
  vim.cmd("colorscheme default")

  local function load_package()
    vim.g.fzf_lua_is_headless = nil
    _G._devicons_path = nil
    _G._fzf_lua_server = nil
    vim.opt.runtimepath:append(mini_path)
    require("mini.icons").setup({})
    devicons.load({ mode = "gui" })
    assert.are.same(devicons.plugin_name(), "mini")
  end

  local function unload_package()
    devicons.unload()
    package.loaded["mini.icons"] = nil
    vim.opt.runtimepath:remove(mini_path)
  end

  local function mini_get(category, name)
    local icon, hl = MiniIcons.get(category, name)
    local color = utils.hexcol_from_hl(hl, "fg", "gui")
    return icon, color
  end

  local function mini_are_same(category, name, expected)
    assert.are.same({ mini_get(category, name) }, expected)
    assert.are.same({ devicons.get_devicon(name) }, expected)
  end


  local function validate_mini()
    local state = devicons.state()
    local icons = state.icons
    assert.are.equal(utils.tbl_count(icons.by_filename),
      utils.tbl_count(MiniIcons.list("file")))
    assert.are.equal(utils.tbl_count(icons.by_ext) + utils.tbl_count(icons.by_ext_2part),
      -- +4 extensions that are causing issues in `vim.filetype.match`
      -- https://github.com/ibhagwan/fzf-lua/issues/1358#issuecomment-2254215160
      utils.tbl_count(MiniIcons.list("extension")) + 4)
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

  it("main thread (defaults)", function()
    load_package()
    validate_mini()
  end)
  it("main thread (hl changes)", function()
    unload_package()
    load_package()
    vim.api.nvim_set_hl(0, "MiniIconsGrey", { default = false, link = "Directory" })
    devicons.load({ mode = "gui" })
    local hexcol = utils.hexcol_from_hl("Directory", "fg", "gui")
    mini_are_same("file", "foo", { "󰈔", hexcol })
    mini_are_same("file", "Makefile", { "󱁤", hexcol })
    mini_are_same("file", "makefile", { "󱁤", hexcol })
    mini_are_same("file", "license", { "󰈔", hexcol })
    mini_are_same("file", "foo.md", { "󰍔", hexcol })
    vim.api.nvim_set_hl(0, "MiniIconsGrey", { default = false })
  end)
  it("main thread (mock)", function()
    unload_package()
    load_package()
    devicons.unload()
    require("mini.icons").mock_nvim_web_devicons()
    devicons.load({ mode = "gui" })
    assert.is.True(devicons.__DEVICONS:is_mock())
    assert.are.same(devicons.plugin_name(), "mini")
    validate_mini()
  end)
  it("headless: _G.devicons_path", function()
    vim.g.fzf_lua_is_headless = true
    _G._devicons_path = mini_path
    _G._fzf_lua_server = nil
    unload_package()
    devicons.load({ mode = "gui" })
    assert.is.True(devicons.plugin_loaded())
    assert.are.same(devicons.plugin_name(), "mini")
    validate_mini()
  end)
  it(string.format("headless, RPC: '%s'", vim.g.fzf_lua_server), function()
    -- Unload first to remove the extensions/files added by `vim.filetype.match`
    -- Then loade with no args so we load mini, then request to load from server
    unload_package()
    load_package()
    assert.are.same(devicons.plugin_name(), "mini")
    vim.g.fzf_lua_is_headless = true
    _G._devicons_path = nil
    _G._fzf_lua_server = vim.g.fzf_lua_server
    devicons.load({ plugin = "srv", srv_plugin = "mini" })
    assert.are.same(devicons.plugin_name(), "srv")
    validate_mini()
  end)
end)
