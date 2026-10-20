local helpers = require("fzf-lua.test.helpers")
local assert = helpers.assert

local parse = require("fzf-lua.config.parse")
local eq = assert.are.equal
local same = assert.are.same

describe("Testing config parser", function()
  it("parses empty and simple strings", function()
    same(parse.shellparse(""), {})
    same(parse.shellparse("foo"), { "foo" })
    same(parse.shellparse("foo bar"), { "foo", "bar" })
    same(parse.shellparse("foo\tbar\n"), { "foo", "bar" })
  end)

  it("handles single and double quotes", function()
    same(parse.shellparse("--foo='bar baz'"), { "--foo=bar baz" })
    same(parse.shellparse('--foo="bar baz"'), { "--foo=bar baz" })
    same(parse.shellparse([[--foo="bar\"baz"]]), { [[--foo=bar"baz]] })
    same(parse.shellparse([[--foo=\'bar\ baz\']]), { [[--foo='bar baz']] })
  end)

  it("handles spaces in quotes and variables", function()
    same(parse.shellparse("a b `ls`"), { "a", "b", "`ls`" })
    same(parse.shellparse("a $(echo b)"), { "a", "$(echo b)" })
    same(parse.shellparse([[$(echo "ab c")]]), { [[$(echo "ab c")]] })
  end)

  it("handles comments correctly", function()
    same(parse.shellparse("a #b"), { "a" })
    same(parse.shellparse("a#b"), { "a#b" })
    same(parse.shellparse("a #b\nc"), { "a", "c" })
    same(parse.shellparse("a b#c"), { "a", "b#c" })
    same(parse.shellparse('--foo="bar #baz"'), { "--foo=bar #baz" })
    same(parse.shellparse('--foo="bar" #baz'), { "--foo=bar" })
  end)

  it("stops at certain operators", function()
    same(parse.shellparse("a ; b"), { "a" })
    same(parse.shellparse("a & b"), { "a" })
    same(parse.shellparse("a | b"), { "a" })
    same(parse.shellparse("a < b"), { "a" })
    same(parse.shellparse("a > b"), { "a" })
    same(parse.shellparse("> file"), {})
    same(parse.shellparse("abc 2>"), { "abc" })
    same(parse.shellparse("2>"), {})
    same(parse.shellparse("abc2>"), { "abc2" })
  end)

  it("returns error on unclosed quotes", function()
    local res, err = parse.shellparse('"abc')
    eq(res, nil)
    eq(err, "invalid command line string")

    res, err = parse.shellparse("'abc")
    eq(res, nil)
    eq(err, "invalid command line string")

    res, err = parse.shellparse("a `b")
    eq(res, nil)
    eq(err, "invalid command line string")

    res, err = parse.shellparse("a $(b")
    eq(res, nil)
    eq(err, "invalid command line string")
  end)

  it("invalid unclosed bracket command", function()
    local res, err = parse.shellparse("a (b")
    eq(res, nil)
    eq(err, "invalid command line string")
  end)

  it("tests config parser wrapper", function()
    local res = parse.parse("")
    same(res, {})

    res = parse.parse("foo bar")
    same(res, { foo = nil, bar = nil })

    res = parse.parse("--foo")
    same(res, { ["--foo"] = true })

    res = parse.parse("--foo=bar")
    same(res, { ["--foo"] = "bar" })

    res = parse.parse("--foo='bar baz'")
    same(res, { ["--foo"] = "bar baz" })

    res = parse.parse("--foo 'bar baz'")
    same(res, { ["--foo"] = "bar baz" })

    -- When tokenizing multiple '='
    res = parse.parse([[--bind='ctrl-a:execute(echo "==")']])
    same(res, { ["--bind"] = [[ctrl-a:execute(echo "==")]] })
  end)
end)

describe("Testing config version gate", function()
  local config = require("fzf-lua.config")
  local utils = require("fzf-lua.utils")
  local defaults = require("fzf-lua.defaults").defaults

  -- normalize_opts probes the real binary; stub the version query and the
  -- executable check so the gate is exercised on any host
  local function normalize_sk(ver, is_windows)
    local orig = {
      sk_version = utils.sk_version,
      error = utils.error,
      executable = vim.fn.executable,
      is_windows = utils.__IS_WINDOWS,
    }
    local err
    utils.sk_version = function() return ver, 0, utils.ver2str(ver) end
    utils.error = function(fmt, ...)
      err = select("#", ...) > 0 and fmt:format(...) or fmt
    end
    vim.fn.executable = function() return 1 end
    utils.__IS_WINDOWS = is_windows
    local ok, res = pcall(config.normalize_opts, { fzf_bin = "sk" }, defaults.files)
    utils.sk_version, utils.error = orig.sk_version, orig.error
    vim.fn.executable, utils.__IS_WINDOWS = orig.executable, orig.is_windows
    if not ok then error(res) end
    return res, err
  end

  it("rejects skim < 5.8.0 on Windows", function()
    local res, err = normalize_sk({ 5, 7, 5 }, true)
    eq(res, nil)
    eq(type(err), "string")
    if type(err) == "string" then
      eq(err:match("skim version 5%.7%.5") ~= nil, true)
      eq(err:match("5%.8%.0") ~= nil, true)
    end
  end)

  it("accepts skim < 5.8.0 off Windows", function()
    local res, err = normalize_sk({ 5, 7, 5 }, false)
    assert.is.True(res ~= nil)
    eq(err, nil)
  end)

  it("accepts skim >= 5.8.0 on Windows", function()
    local res, err = normalize_sk({ 5, 8, 0 }, true)
    assert.is.True(res ~= nil)
    eq(err, nil)
  end)
end)
