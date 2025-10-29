local helpers = require("fzf-lua.test.helpers")
local assert = helpers.assert
local eq = assert.are.same

local fzf = require("fzf-lua")
local utils = fzf.utils

describe("Testing utils module", function()
  it("separator", function()
    utils.__IS_WINDOWS = false
    eq(utils._if_win_normalize_vars("--w=$COLUMNS"), "--w=$COLUMNS")

    utils.__IS_WINDOWS = true
    eq(utils._if_win_normalize_vars("--w=$COLUMNS", 1), "--w=%COLUMNS%")
    eq(utils._if_win_normalize_vars("--w=%COLUMNS%", 1), "--w=%COLUMNS%")
    eq(utils._if_win_normalize_vars("-w=$C -l=$L", 1), "-w=%C% -l=%L%")
    eq(utils._if_win_normalize_vars("--w=$COLUMNS", 2), "--w=!COLUMNS!")
    eq(utils._if_win_normalize_vars("--w=%COLUMNS%", 2), "--w=!COLUMNS!")
    eq(utils._if_win_normalize_vars("-w=$C -l=$L", 2), "-w=!C! -l=!L!")
    utils.__IS_WINDOWS = nil
  end)

  it("version formatter", function()
    eq(utils.ver2str(), nil)
    eq(utils.ver2str(""), nil)
    eq(utils.ver2str({}), nil)
    eq(utils.ver2str({ 0 }), "0.0.0")
    eq(utils.ver2str({ 1 }), "1.0.0")
    eq(utils.ver2str({ 1, 2 }), "1.2.0")
    eq(utils.ver2str({ 0, 1, 2 }), "0.1.2")
    eq(utils.ver2str({ 1, 2, 3 }), "1.2.3")
  end)

  it("version parser", function()
    eq(utils.parse_verstr(), nil)      -- Invalid
    eq(utils.parse_verstr(""), nil)    -- Invalid
    eq(utils.parse_verstr("0"), nil)   -- Invalid
    eq(utils.parse_verstr("all"), nil) -- Invalid
    eq(utils.parse_verstr("HEAD"), { 100, 0, 0 })
    eq(utils.parse_verstr("0.5"), { 0, 5, 0 })
    eq(utils.parse_verstr("0.5.0"), { 0, 5, 0 })
    eq(utils.parse_verstr("0.56"), { 0, 56, 0 })
    eq(utils.parse_verstr("0.56.3"), { 0, 56, 3 })
    eq(utils.parse_verstr("01.56.03"), { 1, 56, 3 })
    eq(utils.parse_verstr("10.56.30"), { 10, 56, 30 })
  end)

  it("has", function()
    eq(utils.has({}), false)
    eq(utils.has({}, "fzf"), false)
    eq(utils.has({ __SK_VERSION = {} }, "sk"), true)
    eq(utils.has({ __FZF_VERSION = {} }, "fzf"), true)
    eq(utils.has({ __FZF_VERSION = {} }, "sk"), false)
    eq(utils.has({ __SK_VERSION = {} }, "fzf"), false)
    eq(utils.has({ __SK_VERSION = { 0, 5, 0 } }, "sk", ""), false)
    eq(utils.has({ __SK_VERSION = { 0, 5, 0 } }, "sk", "0"), false)
    eq(utils.has({ __SK_VERSION = { 0, 5, 0 } }, "sk", "0.1"), true)
    eq(utils.has({ __SK_VERSION = { 0, 5, 0 } }, "sk", "0.4.9"), true)
    eq(utils.has({ __SK_VERSION = { 0, 15, 5 } }, "sk", "0.15"), true)
    eq(utils.has({ __SK_VERSION = { 0, 15, 5 } }, "sk", "0.15.0"), true)
    eq(utils.has({ __SK_VERSION = { 0, 15, 5 } }, "sk", "0.15.5"), true)
    eq(utils.has({ __SK_VERSION = { 0, 15, 5 } }, "sk", "0.15.6"), false)
    eq(utils.has({ __SK_VERSION = { 0, 5, 0 } }, "sk", "0.16"), false)
    eq(utils.has({ __SK_VERSION = { 0, 5, 0 } }, "sk", { 0, 5, 0 }), true)
    eq(utils.has({ __SK_VERSION = { 0, 5, 0 } }, "sk", { 0, 6, 0 }), false)
    eq(utils.has({ __SK_VERSION = { 0, 5, 0 } }, "sk", { 0, 5 }), true)
    eq(utils.has({ __SK_VERSION = { 0, 5, 0 } }, "sk", { 0, 6 }), false)
    eq(utils.has({ __SK_VERSION = { 0, 5, 0 } }, "sk", { 0 }), true)
    eq(utils.has({ __SK_VERSION = { 0, 5, 0 } }, "sk", { 0 }), true)
    eq(utils.has({ __SK_VERSION = { 0, 5, 0 } }, "sk", { 1 }), false)
    eq(utils.has({ __SK_VERSION = { 0, 5, 0 } }, "fzf", "0.5"), false)
    eq(utils.has({ __FZF_VERSION = { 1, 5, 0 } }, "fzf", "1.4"), true)
    eq(utils.has({ __FZF_VERSION = { 1, 5, 0 } }, "fzf", "1.5.0"), true)
    eq(utils.has({ __FZF_VERSION = { 0, 0, 5 } }, "fzf", "0.0.4"), true)
    eq(utils.has({ __FZF_VERSION = { 0, 0, 5 } }, "fzf", "0.0.5"), true)
    eq(utils.has({ __FZF_VERSION = { 0, 0, 5 } }, "fzf", "0.0.6"), false)
    eq(utils.has({ __FZF_VERSION = { 0, 5, 5 } }, "fzf", "0.5.4"), true)
    eq(utils.has({ __FZF_VERSION = { 0, 5, 5 } }, "fzf", "0.0.5"), true)
    eq(utils.has({ __FZF_VERSION = { 0, 5, 5 } }, "fzf", "0.5.6"), false)
    eq(utils.has({ __FZF_VERSION = { 2, 5, 5 } }, "fzf", "2.5.4"), true)
    eq(utils.has({ __FZF_VERSION = { 2, 5, 5 } }, "fzf", "2.5.5"), true)
    eq(utils.has({ __FZF_VERSION = { 2, 5, 5 } }, "fzf", "2.5.6"), false)
  end)

  it("setmetatable with gc", function()
    local gc_called = nil
    local _obj = utils.setmetatable({}, { __gc = function() gc_called = true end })
    eq(gc_called, nil)
    ---@diagnostic disable-next-line: assign-type-mismatch
    _obj = nil
    collectgarbage("collect")
    eq(gc_called, true)
  end)

  it("wo", function()
    utils.wo.nonexist = "this is nop"
    eq(nil, utils.wo.nonexist)
    vim.wo[0][0].nu = true -- setlocal
    vim.wo[0].rnu = true   -- setglobal
    eq(vim.wo[0][0].nu, vim.wo.nu)
    eq(vim.wo[0][0].rnu, vim.wo.rnu)
    vim.cmd.new()
    eq(vim.wo[0][0].nu, vim.wo.nu)
    eq(vim.wo[0][0].rnu, vim.wo.rnu)
  end)

  it("strsplit", function()
    eq(utils.strsplit("abc", "%s+"), { "abc" })
    eq(utils.strsplit("", "%s+"), { "" })
    eq(utils.strsplit("foo bar baz", "%s+"), { "foo", "bar", "baz" })
    eq(utils.strsplit("foo   bar    baz", "%s+"), { "foo", "bar", "baz" })
    eq(utils.strsplit("foo\tbar\nbaz", "%s+"), { "foo", "bar", "baz" })
    eq(utils.strsplit("  foo bar  ", "%s+"), { "", "foo", "bar", "" })
    eq(utils.strsplit("foo,,bar,,baz", ",+"), { "foo", "bar", "baz" })
    eq(utils.strsplit("a,b,c", ","), { "a", "b", "c" })
    eq(utils.strsplit(",,,", ",+"), { "", "" })
    eq(utils.strsplit(",foo,bar,", ","), { "", "foo", "bar", "" })
    eq(utils.strsplit("foobar", ","), { "foobar" })
  end)
end)
