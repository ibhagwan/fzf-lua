local fzf = require("fzf-lua")
local path = fzf.path
local utils = fzf.utils

describe("Testing NvimWebDevicons", function()
  -- add devicons path from lazy to runtime so our module can load nvim-web-devicons
  local devicons_path = path.join({ vim.fn.stdpath("data"), "lazy", "nvim-web-devicons" })
  local devicons = require("fzf-lua.devicons")

  local function load_package()
    vim.g.fzf_lua_is_headless = nil
    _G._devicons_path = nil
    _G._fzf_lua_server = nil
    vim.opt.runtimepath:append(devicons_path)
    require("nvim-web-devicons").setup({})
    require("nvim-web-devicons").refresh()
    devicons.load()
    assert.are.same(devicons.plugin_name(), "devicons")
  end

  local function unload_package()
    devicons.unload()
    package.loaded["nvim-web-devicons"] = nil
    vim.opt.runtimepath:remove(devicons_path)
  end

  local function devicons_get(name)
    name = path.tail(name) or name
    local icon, hl = require("nvim-web-devicons").get_icon(name, nil, { default = true })
    local color = utils.hexcol_from_hl(hl, "fg")
    return icon, color
  end

  local function devicons_are_same(name, expected)
    assert.are.same({ devicons_get(name) }, expected)
    assert.are.same({ devicons.get_devicon(name) }, expected)
  end

  load_package()

  local theme = {
    icons_by_filename = require("nvim-web-devicons").get_icons_by_filename(),
    icons_by_file_extension = require("nvim-web-devicons").get_icons_by_extension(),
  }

  local function validate_devicons()
    local state = devicons.state()
    local icons = state.icons
    assert.are.same(state.default_icon, { icon = "", color = "#6d8086" })
    assert.are.same(state.dir_icon, { icon = "", color = nil })
    assert.is.True(utils.tbl_count(icons.ext_has_2part) > 4)
    assert.is.True(utils.tbl_count(icons.by_ext_2part) > 8)
    assert.are.equal(utils.tbl_count(icons.by_filename),
      utils.tbl_count(theme.icons_by_filename))
    assert.are.equal(utils.tbl_count(icons.by_ext) + utils.tbl_count(icons.by_ext_2part),
      utils.tbl_count(theme.icons_by_file_extension))
  end

  it("main thread", function()
    load_package()
    validate_devicons()
  end)
  it("headless: _G.devicons_path", function()
    _G._devicons_path = devicons_path
    _G._fzf_lua_server = nil
    vim.g.fzf_lua_is_headless = true
    unload_package()
    devicons.load()
    assert.is.True(devicons.plugin_loaded())
    assert.are.same(devicons.plugin_name(), "devicons")
    validate_devicons()
  end)
  it(string.format("headless RPC: '%s'", vim.g.fzf_lua_server), function()
    unload_package()
    load_package()
    vim.g.fzf_lua_is_headless = true
    _G._devicons_path = nil
    _G._fzf_lua_server = vim.g.fzf_lua_server
    devicons.load({ plugin = "srv", srv_plugin = "devicons" })
    assert.are.same(devicons.plugin_name(), "srv")
    validate_devicons()
  end)
  it("background=dark", function()
    vim.o.background = "dark"
    unload_package()
    load_package()
    assert.are.same({ devicons.get_devicon("foo/") }, { "", nil })
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
  end)
  it("background=light", function()
    vim.o.background = "light"
    -- NOTE: do not unload+load as we want to test bg change with a loaded pkg
    devicons.load()
    assert.are.same({ devicons.get_devicon("foo/") }, { "", nil })
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
  end)
  it("notermguicolors (dark)", function()
    vim.o.background = "dark"
    vim.o.termguicolors = false
    devicons.load()
    assert.are.same({ devicons.get_devicon("foo/") }, { "", nil })
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
  end)
  it("notermguicolors (light)", function()
    vim.o.background = "light"
    vim.o.termguicolors = false
    devicons.load()
    assert.are.same({ devicons.get_devicon("foo/") }, { "", nil })
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
  end)
end)
