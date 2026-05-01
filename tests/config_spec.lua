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
