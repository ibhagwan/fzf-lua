local fzf = require("fzf-lua")
local path = fzf.path

describe("Testing devicons module", function()
  -- add devicons path from lazy to runtime so our module can load nvim-web-devicons
  local devicons_path = path.join({ vim.fn.stdpath("data"), "lazy", "nvim-web-devicons" })
  vim.opt.runtimepath:append(devicons_path)
  local theme = require("nvim-web-devicons.icons-default")
  local devicons = require("fzf-lua.devicons")
  devicons.load()
  -- remove from runtime so we can test the headless runtime append
  vim.opt.runtimepath:remove(devicons_path)

  it(string.format("load_icons (%s)", vim.g.fzf_lua_server), function()
    _G._devicons_path = nil
    _G._fzf_lua_server = vim.g.fzf_lua_server
    vim.g.fzf_lua_is_headless = true
    devicons.load()
    local state = devicons.STATE
    local icons = devicons.STATE.icons
    assert.are.same(state.default_icon, { icon = "", color = "#6d8086" })
    assert.are.same(state.dir_icon, { icon = "", color = nil })
    assert.is.True(vim.tbl_count(icons.ext_has_2part) > 4)
    assert.is.True(vim.tbl_count(icons.by_ext_2part) > 8)
    assert.are.equal(vim.tbl_count(icons.by_filename), vim.tbl_count(theme.icons_by_filename))
    assert.are.equal(vim.tbl_count(icons.by_ext) + vim.tbl_count(icons.by_ext_2part),
      vim.tbl_count(theme.icons_by_file_extension))
  end)
  it("get_icons (headless: devicons path)", function()
    _G._devicons_path = devicons_path
    _G._fzf_lua_server = nil
    vim.g.fzf_lua_is_headless = true
    devicons.unload()
    devicons.load()
    local state = devicons.STATE
    local icons = devicons.STATE.icons
    assert.are.same(state.default_icon, { icon = "", color = "#6d8086" })
    assert.are.same(state.dir_icon, { icon = "", color = nil })
    assert.is.True(vim.tbl_count(icons.ext_has_2part) > 4)
    assert.is.True(vim.tbl_count(icons.by_ext_2part) > 8)
    assert.are.equal(vim.tbl_count(icons.by_filename), vim.tbl_count(theme.icons_by_filename))
    assert.are.equal(vim.tbl_count(icons.by_ext) + vim.tbl_count(icons.by_ext_2part),
      vim.tbl_count(theme.icons_by_file_extension))
  end)
  it("get_icons (main thread)", function()
    _G._devicons_path = nil
    _G._fzf_lua_server = nil
    vim.g.fzf_lua_is_headless = nil
    devicons.unload()
    devicons.load()
    local state = devicons.STATE
    local icons = devicons.STATE.icons
    assert.are.same(state.default_icon, { icon = "", color = "#6d8086" })
    assert.are.same(state.dir_icon, { icon = "", color = nil })
    assert.is.True(vim.tbl_count(icons.ext_has_2part) > 4)
    assert.is.True(vim.tbl_count(icons.by_ext_2part) > 8)
    assert.are.equal(vim.tbl_count(icons.by_filename), vim.tbl_count(theme.icons_by_filename))
    assert.are.equal(vim.tbl_count(icons.by_ext) + vim.tbl_count(icons.by_ext_2part),
      vim.tbl_count(theme.icons_by_file_extension))
  end)
  it("get_icon (dark)", function()
    vim.o.background = "dark"
    devicons.load()
    assert.are.same({ devicons.get_devicon("") }, { "", "#6d8086" })
    assert.are.same({ devicons.get_devicon(".") }, { "", "#6d8086" })
    assert.are.same({ devicons.get_devicon("f.abc") }, { "", "#6d8086" })
    assert.are.same({ devicons.get_devicon("f.") }, { "", "#6d8086" })
    assert.are.same({ devicons.get_devicon(".f") }, { "", "#6d8086" })
    assert.are.same({ devicons.get_devicon("foo") }, { "", "#6d8086" })
    assert.are.same({ devicons.get_devicon("foo/") }, { "", nil })
    -- by filename
    assert.are.same({ devicons.get_devicon(".editorconfig") }, { "", "#fff2f2" })
    assert.are.same({ devicons.get_devicon("/path/.bashrc") }, { "", "#89e051" })
    -- by 2-part extension
    assert.are.same({ devicons.get_devicon("foo.bar.jsx") }, { "", "#20c2e3" })
    assert.are.same({ devicons.get_devicon("foo.spec.jsx") }, { "", "#20c2e3" })
    assert.are.same({ devicons.get_devicon("foo.config.ru") }, { "", "#701516" })
    -- by 1-part extensions
    assert.are.same({ devicons.get_devicon("foo.lua") }, { "", "#51a0cf" })
    assert.are.same({ devicons.get_devicon("foo.py") }, { "", "#ffbc03" })
    assert.are.same({ devicons.get_devicon("foo.r") }, { "󰟔", "#2266ba" })
    assert.are.same({ devicons.get_devicon("foo.R") }, { "󰟔", "#2266ba" })
  end)
  it("get_icon (light)", function()
    vim.o.background = "light"
    devicons.load()
    assert.are.same({ devicons.get_devicon("") }, { "", "#6d8086" })
    assert.are.same({ devicons.get_devicon(".") }, { "", "#6d8086" })
    assert.are.same({ devicons.get_devicon("f.abc") }, { "", "#6d8086" })
    assert.are.same({ devicons.get_devicon("f.") }, { "", "#6d8086" })
    assert.are.same({ devicons.get_devicon(".f") }, { "", "#6d8086" })
    assert.are.same({ devicons.get_devicon("foo") }, { "", "#6d8086" })
    assert.are.same({ devicons.get_devicon("foo/") }, { "", nil })
    -- by filename
    assert.are.same({ devicons.get_devicon(".editorconfig") }, { "", "#333030" })
    assert.are.same({ devicons.get_devicon("/path/.bashrc") }, { "", "#447028" })
    -- by 2-part extension
    assert.are.same({ devicons.get_devicon("foo.bar.jsx") }, { "", "#158197" })
    assert.are.same({ devicons.get_devicon("foo.spec.jsx") }, { "", "#158197" })
    assert.are.same({ devicons.get_devicon("foo.config.ru") }, { "", "#701516" })
    -- by 1-part extensions
    assert.are.same({ devicons.get_devicon("foo.lua") }, { "", "#366b8a" })
    assert.are.same({ devicons.get_devicon("foo.py") }, { "", "#805e02" })
    assert.are.same({ devicons.get_devicon("foo.r") }, { "󰟔", "#1a4c8c" })
    assert.are.same({ devicons.get_devicon("foo.R") }, { "󰟔", "#1a4c8c" })
  end)
end)
