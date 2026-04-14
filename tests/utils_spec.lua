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
    -- store mini.test float so we can return to it when
    -- testing in main instance
    local win = vim.api.nvim_get_current_win()
    vim.cmd.new()
    utils.wo.nonexist = "this is nop"
    eq(nil, utils.wo.nonexist)

    vim.wo[0][0].nu = true -- setlocal
    vim.wo[0].rnu = true   -- setglobal
    eq(vim.wo[0][0].nu, vim.wo.nu)
    eq(vim.wo[0][0].rnu, vim.wo.rnu)
    vim.api.nvim_buf_delete(0, { force = true })
    vim.cmd.new()
    eq(vim.wo[0][0].nu, vim.wo.nu)
    eq(vim.wo[0][0].rnu, vim.wo.rnu)
    vim.api.nvim_buf_delete(0, { force = true })

    -- same behavior
    utils.wo[0][0].nu = true -- setlocal
    utils.wo[0].rnu = true   -- setglobal
    eq(utils.wo[0][0].nu, utils.wo.nu)
    eq(utils.wo[0][0].rnu, utils.wo.rnu)
    vim.cmd.new()
    eq(utils.wo[0][0].nu, utils.wo.nu)
    eq(utils.wo[0][0].rnu, utils.wo.rnu)
    vim.api.nvim_buf_delete(0, { force = true })
    vim.api.nvim_set_current_win(win)
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

  it("regex_strip_anchors", function()
    -- nil input
    eq({ utils.regex_strip_anchors(nil) }, { [2] = 0, [3] = 0 })
    -- empty string
    eq({ utils.regex_strip_anchors("") }, { "", 0, 0 })
    -- no anchors
    eq({ utils.regex_strip_anchors("foobar") }, { "foobar", 0, 0 })
    -- only start anchor
    eq({ utils.regex_strip_anchors("^foobar") }, { "foobar", 1, 0 })
    -- only end anchor
    eq({ utils.regex_strip_anchors("foobar$") }, { "foobar", 0, 1 })
    -- both anchors
    eq({ utils.regex_strip_anchors("^foobar$") }, { "foobar", 1, 1 })
    -- anchors in middle (should not be stripped)
    eq({ utils.regex_strip_anchors("foo^bar$baz") }, { "foo^bar$baz", 0, 0 })
    -- only anchors
    eq({ utils.regex_strip_anchors("^") }, { "", 1, 0 })
    eq({ utils.regex_strip_anchors("$") }, { "", 0, 1 })
    eq({ utils.regex_strip_anchors("^$") }, { "", 1, 1 })
    -- single character with anchors
    eq({ utils.regex_strip_anchors("^x$") }, { "x", 1, 1 })
    -- should not strip escaped $ (prepended by odd number of backslashes)
    eq({ utils.regex_strip_anchors([[x\$]]) }, { [[x\$]], 0, 0 })
    eq({ utils.regex_strip_anchors([[x\\$]]) }, { [[x\\]], 0, 1 })
    eq({ utils.regex_strip_anchors([[x\\\$]]) }, { [[x\\\$]], 0, 0 })
  end)

  it("ctag_match", function()
    -- no slashes
    eq(utils.ctag_match("foobar"), nil)
    -- single slash (needs at least 2 slashes)
    eq(utils.ctag_match("foo/bar"), nil)
    -- anchored slahes
    eq({ utils.ctag_match("/foo/") }, { 1, 5 })
    -- two slashes (finds the two rightmost unescaped slashes)
    eq({ utils.ctag_match("/foo/bar/baz") }, { 5, 9 })
    -- escaped slash only (should ignore escaped ones)
    eq(utils.ctag_match([[/foo\/bar]]), nil)
    eq(utils.ctag_match([[/foo\\\/bar]]), nil)
    -- escaped slash backslash before slash
    eq({ utils.ctag_match([[/foo\\/bar]]) }, { 1, 7 })
    eq({ utils.ctag_match([[/foo\\\\/bar]]) }, { 1, 9 })
    -- mixed escaped and unescaped
    eq({ utils.ctag_match([[foo/bar\/baz/qux]]) }, { 4, 13 })
    -- reverse search from end
    eq({ utils.ctag_match("/a/b/c/d") }, { 5, 7 })
  end)

  it("ctag_escape", function()
    -- empty string
    eq(utils.ctag_escape(""), "")
    -- no special characters
    eq(utils.ctag_escape("foobar"), "foobar")
    -- escaped backslash (\\ becomes \, then rg_escape doubles it back)
    eq(utils.ctag_escape("foo\\bar"), "foo\\\\bar")
    -- unescape escaped slash (\/ becomes /)
    eq(utils.ctag_escape("foo\\/bar"), "foo/bar")
    -- regex escape (rg_escape behavior)
    eq(utils.ctag_escape("foo.bar"), "foo\\.bar")
    eq(utils.ctag_escape("foo*bar"), "foo\\*bar")
    -- ^ at start gets unescaped (was escaped by rg_escape)
    eq(utils.ctag_escape("^foobar"), "^foobar")
    -- $ at end gets unescaped (was escaped by rg_escape)
    eq(utils.ctag_escape("foobar$"), "foobar$")
    -- already escaped ^ at start stays escaped (rg_escape adds another backslash)
    eq(utils.ctag_escape("\\^foobar"), "\\\\\\^foobar")
    -- already escaped $ at end stays escaped
    eq(utils.ctag_escape("foobar\\$"), "foobar\\\\$")
    -- ^ in middle stays escaped
    eq(utils.ctag_escape("foo^bar"), "foo\\^bar")
    -- $ in middle stays escaped
    eq(utils.ctag_escape("foo$bar"), "foo\\$bar")
    -- combination of patterns
    eq(utils.ctag_escape("^foo.bar$"), "^foo\\.bar$")
    -- escaped backslash before dot (\. becomes ., then rg_escape escapes both)
    eq(utils.ctag_escape("foo\\.bar"), "foo\\\\\\.bar")
  end)
end)
