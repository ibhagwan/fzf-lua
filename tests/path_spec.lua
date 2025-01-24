local helpers = require("fzf-lua.test.helpers")
local assert = helpers.assert

local fzf = require("fzf-lua")
local path = fzf.path
local utils = fzf.utils

describe("Testing path module", function()
  it("separator", function()
    utils.__IS_WINDOWS = false
    assert.are.same(path.separator(), "/")
    assert.are.same(path.separator(""), "/")
    assert.are.same(path.separator("~/foo"), "/")
    assert.are.same(path.separator([[~\foo]]), "/")
    assert.are.same(path.separator([[c:\foo]]), "/")

    utils.__IS_WINDOWS = true
    assert.are.same(path.separator(), [[\]])
    assert.are.same(path.separator(""), [[\]])
    assert.are.same(path.separator("~/foo"), "/")
    assert.are.same(path.separator([[~\foo]]), [[\]])
    assert.are.same(path.separator([[c:\foo]]), [[\]])
    assert.are.same(path.separator([[foo\bar]]), [[\]])
  end)

  it("Ends with separator", function()
    utils.__IS_WINDOWS = false
    assert.is.False(path.ends_with_separator(""))
    assert.is.True(path.ends_with_separator("/"))
    assert.is.False(path.ends_with_separator([[\]]))
    assert.is.False(path.ends_with_separator("/some/path"))
    assert.is.True(path.ends_with_separator("/some/path/"))

    utils.__IS_WINDOWS = true
    assert.is.False(path.ends_with_separator(""))
    assert.is.True(path.ends_with_separator("/"))
    assert.is.True(path.ends_with_separator([[\]]))
    assert.is.False(path.ends_with_separator("/some/path"))
    assert.is.True(path.ends_with_separator("/some/path/"))
    assert.is.False(path.ends_with_separator([[c:\some\path]]))
    assert.is.True(path.ends_with_separator([[c:\some\path\]]))
  end)

  it("Add trailing separator", function()
    utils.__IS_WINDOWS = false
    assert.are.equal(path.add_trailing(""), "/")
    assert.are.equal(path.add_trailing("/"), "/")
    assert.are.equal(path.add_trailing("/some"), "/some/")
    assert.are.equal(path.add_trailing("/some/"), "/some/")
    utils.__IS_WINDOWS = true
    assert.are.equal(path.add_trailing(""), [[\]])
    assert.are.equal(path.add_trailing("/"), [[/]])
    assert.are.equal(path.add_trailing("/some"), [[/some\]])
    assert.are.equal(path.add_trailing("/some/"), [[/some/]])
    assert.are.equal(path.add_trailing([[C:\some\]]), [[C:\some\]])
    assert.are.equal(path.add_trailing([[C:\some]]), [[C:\some\]])
    assert.are.equal(path.add_trailing([[C:/some]]), [[C:/some/]])
    assert.are.equal(path.add_trailing([[~/some]]), [[~/some/]])
    assert.are.equal(path.add_trailing([[some\path]]), [[some\path\]])
  end)

  it("Remove trailing separator", function()
    utils.__IS_WINDOWS = false
    assert.are.equal(path.remove_trailing(""), "")
    assert.are.equal(path.remove_trailing("/"), "")
    assert.are.equal(path.remove_trailing("//"), "")
    assert.are.equal(path.remove_trailing("/some"), "/some")
    assert.are.equal(path.remove_trailing("/some/"), "/some")
    assert.are.equal(path.remove_trailing("/some/////"), "/some")
    assert.are.equal(path.remove_trailing([[/some\]]), [[/some\]])
    utils.__IS_WINDOWS = true
    assert.are.equal(path.remove_trailing(""), "")
    assert.are.equal(path.remove_trailing("/"), "")
    assert.are.equal(path.remove_trailing("//"), "")
    assert.are.equal(path.remove_trailing("/some"), "/some")
    assert.are.equal(path.remove_trailing("/some/"), "/some")
    assert.are.equal(path.remove_trailing("/some/////"), "/some")
    assert.are.equal(path.remove_trailing([[/some\]]), [[/some]])
    assert.are.equal(path.remove_trailing([[C:\some\]]), [[C:\some]])
    assert.are.equal(path.remove_trailing([[C:\some\\\\//]]), [[C:\some]])
  end)

  it("Is absolute", function()
    utils.__IS_WINDOWS = false
    assert.is.False(path.is_absolute(""))
    assert.is.True(path.is_absolute("/"))
    assert.is.False(path.is_absolute([[\]]))
    assert.is.True(path.is_absolute("/some/path"))
    assert.is.False(path.is_absolute("./some/path/"))
    assert.is.False(path.is_absolute([[c:\some\path\]]))

    utils.__IS_WINDOWS = true
    assert.is.False(path.is_absolute(""))
    assert.is.False(path.is_absolute("/"))
    assert.is.False(path.is_absolute([[\]]))
    assert.is.False(path.is_absolute("/some/path"))
    assert.is.False(path.is_absolute("./some/path/"))
    assert.is.False(path.is_absolute([[.\some\path/]]))
    assert.is.True(path.is_absolute([[c:\some\path]]))
    assert.is.True(path.is_absolute([[C:\some\path\]]))
  end)

  it("Has cwd prefix", function()
    utils.__IS_WINDOWS = false
    assert.is.False(path.has_cwd_prefix(""))
    assert.is.True(path.has_cwd_prefix("./"))
    assert.is.False(path.has_cwd_prefix([[.\]]))
    assert.is.False(path.has_cwd_prefix("/some/path"))
    assert.is.True(path.has_cwd_prefix("./some/path/"))

    utils.__IS_WINDOWS = true
    assert.is.False(path.has_cwd_prefix(""))
    assert.is.True(path.has_cwd_prefix("./"))
    assert.is.True(path.has_cwd_prefix([[.\]]))
    assert.is.False(path.has_cwd_prefix("/some/path"))
    assert.is.True(path.has_cwd_prefix("./some/path/"))
    assert.is.True(path.has_cwd_prefix([[.\some\path/]]))
    assert.is.False(path.has_cwd_prefix([[c:\some\path]]))
    assert.is.False(path.has_cwd_prefix([[c:\some\path\]]))
    assert.is.False(path.has_cwd_prefix([[c:\some/path\]]))
  end)

  it("Strip cwd prefix", function()
    utils.__IS_WINDOWS = false
    assert.are.equal(path.strip_cwd_prefix(""), "")
    assert.are.equal(path.strip_cwd_prefix("./"), "")
    assert.are.equal(path.strip_cwd_prefix([[.\]]), [[.\]])
    assert.are.equal(path.strip_cwd_prefix("/some/path"), "/some/path")
    assert.are.equal(path.strip_cwd_prefix("./some/path/"), "some/path/")

    utils.__IS_WINDOWS = true
    assert.are.equal(path.strip_cwd_prefix(""), "")
    assert.are.equal(path.strip_cwd_prefix("./"), "")
    assert.are.equal(path.strip_cwd_prefix([[.\]]), "")
    assert.are.equal(path.strip_cwd_prefix("/some/path"), "/some/path")
    assert.are.equal(path.strip_cwd_prefix("./some/path/"), "some/path/")
    assert.are.equal(path.strip_cwd_prefix([[.\some\path/]]), [[some\path/]])
    assert.are.equal(path.strip_cwd_prefix([[c:\some\path]]), [[c:\some\path]])
  end)

  it("Tail", function()
    utils.__IS_WINDOWS = false
    assert.are.equal(path.tail(""), "")
    assert.are.equal(path.tail("/"), "/")
    assert.are.equal(path.tail("foo"), "foo")
    assert.are.equal(path.tail(".foo"), ".foo")
    assert.are.equal(path.tail("/foo"), "foo")
    assert.are.equal(path.tail("/foo/"), "foo/")
    assert.are.equal(path.tail("/foo/bar"), "bar")
    assert.are.equal(path.tail([[/foo\bar]]), [[foo\bar]])

    utils.__IS_WINDOWS = true
    assert.are.equal(path.tail(""), "")
    assert.are.equal(path.tail("/"), "/")
    assert.are.equal(path.tail([[\]]), [[\]])
    assert.are.equal(path.tail("foo"), "foo")
    assert.are.equal(path.tail(".foo"), ".foo")
    assert.are.equal(path.tail([[c:\foo]]), "foo")
    assert.are.equal(path.tail([[c:\foo\]]), [[foo\]])
    assert.are.equal(path.tail([[c:\foo\bar]]), "bar")
    assert.are.equal(path.tail([[c:/foo\bar]]), "bar")
    assert.are.equal(path.tail([[c:/foo//\//bar]]), "bar")
  end)

  it("Parent", function()
    utils.__IS_WINDOWS = false
    assert.are.equal(path.parent(""), nil)
    assert.are.equal(path.parent("/"), nil)
    assert.are.equal(path.parent("/foo"), "/")
    assert.are.equal(path.parent("/foo/bar"), "/foo/")
    assert.are.equal(path.parent("/foo/bar", true), "/foo")
    assert.are.equal(path.parent([[/foo\bar]]), [[/]])

    utils.__IS_WINDOWS = true
    assert.are.equal(path.parent(""), nil)
    assert.are.equal(path.parent("/"), nil)
    assert.are.equal(path.parent([[\]]), nil)
    assert.are.equal(path.parent([[c:]]), nil)
    assert.are.equal(path.parent([[c:\foo]]), [[c:\]])
    assert.are.equal(path.parent([[c:\foo]], true), [[c:]])
    assert.are.equal(path.parent([[c:\foo\bar]]), [[c:\foo\]])
    assert.are.equal(path.parent([[c:\foo/bar]]), [[c:\foo/]])
    assert.are.equal(path.parent([[c:/foo//\//bar]], true), [[c:/foo]])
  end)

  it("Normalize", function()
    utils.__IS_WINDOWS = false
    assert.are.equal(path.normalize("/some/path"), "/some/path")
    assert.are.equal(path.normalize([[\some\path]]), [[\some\path]])
    assert.are.equal(path.normalize("~/some/path"), path.HOME() .. "/some/path")
    utils.__IS_WINDOWS = true
    assert.are.equal(path.normalize("/some/path"), "/some/path")
    assert.are.equal(path.normalize([[\some\path]]), "/some/path")
    assert.are.equal(path.normalize("~/some/path"), path.normalize(path.HOME()) .. "/some/path")
  end)

  it("Equals", function()
    utils.__IS_WINDOWS = false
    assert.is.False(path.equals("/some/path", "/some/path/foo"))
    assert.is.True(path.equals("/some/path", "/some/path/"))
    assert.is.False(path.equals("/some/Path", "/some/path"))
    assert.is.True(path.equals("~/some/path", path.HOME() .. "/some/path"))
    assert.is.False(path.equals([[/some\\path]], "/some/path/"))
    utils.__IS_WINDOWS = true
    assert.is.False(path.equals("/some/path", "/some/path/foo"))
    assert.is.True(path.equals("/some/path", "/some/path/"))
    assert.is.True(path.equals("/some/PATH", "/some/path"))
    assert.is.True(path.equals("~/some/path", path.HOME() .. "/some/path"))
    assert.is.True(path.equals([[/some\path\\]], "/some/path/"))
  end)

  it("Is relative to", function()
    -- Testing both `path.is_relative_to` and `path.relative_to`
    -- [1]: path
    -- [2]: relative_to
    -- [3]: expected result (bool, relative_path)
    local unix = {
      { "/some/path",          "/some/path",          { true, "." } },
      { "/some/path",          "/some/path//",        { true, "." } },
      { "/some/path//",        "/some/path",          { true, "." } },
      { "/some",               "/somepath",           { false, nil } },
      { "some",                "somepath",            { false, nil } },
      { "some",                "some/path",           { false, nil } },
      { "some/path",           "some",                { true, "path" } },
      { "some/path/",          "some",                { true, "path/" } },
      { "some/path//",         "some",                { true, "path//" } },
      { "some/path/",          [[some\]],             { false, nil } },
      { [[some\path]],         "some",                { false, nil } },
      { "/some/path/to",       "/some///",            { true, "path/to" } },
      { "/SOME/PATH",          "/some",               { false, nil } },
      { "a///b//////c",        "a//b",                { true, "c" } },
      { "~",                   path.HOME(),           { true, "." } },
      { "~/a/b/c",             "~/a",                 { true, "b/c" } },
      { "~//a/b/c",            path.HOME() .. "/a/b", { true, "c" } },
      { path.HOME() .. "/a/b", "~/a/",                { true, "b" } },
      { "/",                   "/some/path",          { false, nil } },
      { "/some",               "/some/path",          { false, nil } },
    }
    local win = {
      { [[\some\path]],      [[\some/path]],     { true, "." } },
      { [[/some/path]],      [[/some/path\/\/]], { true, "." } },
      { "/some/path/",       "/some/path",       { true, "." } },
      { [[\some]],           [[\somepath]],      { false, nil } },
      { "some/path",         "some",             { true, "path" } },
      { [[some\path\]],      [[some\/\]],        { true, [[path\]] } },
      { [[c:\some\path]],    [[c:\some]],        { true, [[path]] } },
      { [[c:\some\path\]],   [[c:\some]],        { true, [[path\]] } },
      { [[c:\some\path\\]],  [[c:\some]],        { true, [[path\\]] } },
      { [[c:\some\path\]],   [[c:\some\\///]],   { true, [[path\]] } },
      { [[c:\SOME\PATH]],    [[C:\some/\/\]],    { true, [[PATH]] } },
      { [[~\SOME\PATH\to]],  [[~\some/]],        { true, [[PATH\to]] } },
      { [[~\SOME\PATH/to]],  [[~\some]],         { true, [[PATH/to]] } },
      { [[C:\a/\/b///\\\c]], [[c:\/\a\/b]],      { true, "c" } },
      { [[C:\a/b\c\d\e]],    [[c:\A\/b\]],       { true, [[c\d\e]] } },
      { [[C:\Users]],        [[c:\]],            { true, [[Users]] } },
      { [[C:\Users\foo]],    [[c:\]],            { true, [[Users\foo]] } },
      { [[C:\]],             [[C:\Users]],       { false, nil } },
      { [[C:]],              [[C:\Users]],       { false, nil } },
    }
    utils.__IS_WINDOWS = false
    for _, v in ipairs(unix) do
      assert.are.same({ path.is_relative_to(v[1], v[2]) }, v[3],
        string.format('\n\nis_relative_to("%s", "%s") ~= "%s"\n', v[1], v[2], v[3][2]))
    end
    utils.__IS_WINDOWS = true
    for _, v in ipairs(win) do
      assert.are.same({ path.is_relative_to(v[1], v[2]) }, v[3],
        string.format('\n\nis_relative_to("%s", "%s") ~= "%s"\n', v[1], v[2], v[3][2]))
    end
  end)

  it("Extension", function()
    utils.__IS_WINDOWS = false
    assert.are.equal(path.extension("/some/path/foobar"), nil)
    assert.are.equal(path.extension("/some/pa.th/foobar"), nil)
    assert.is.same(path.extension("/some/path/foobar."), "")
    assert.is.same(path.extension("/some/path/foo.bar"), "bar")
    assert.is.same(path.extension("/some/path/foo.bar.baz"), "baz")
    assert.is.same(path.extension("/some/path/.foobar"), "foobar")
    -- override that doesn't "tail" the path
    assert.are.equal(path.extension("/some/pa.th/foobar", true), "th/foobar")
  end)

  it("Join", function()
    utils.__IS_WINDOWS = false
    assert.is.same(path.join({ "some" }), "some")
    assert.is.same(path.join({ nil, "path" }), "path")
    assert.is.same(path.join({ "/some", "path" }), "/some/path")
    assert.is.same(path.join({ "/some", "path/" }), "/some/path/")
    assert.is.same(path.join({ "/some/", "path" }), "/some/path")
    assert.is.same(path.join({ "/some//", "path" }), "/some//path")
    assert.is.same(path.join({ "~/some/", "path" }), "~/some/path")
    assert.is.same(path.join({ [[~\some\]], "path" }), [[~\some\/path]])
    assert.is.same(path.join({ [[c:\some\]], "path" }), [[c:\some\/path]])
    utils.__IS_WINDOWS = true
    assert.is.same(path.join({ "some" }), "some")
    assert.is.same(path.join({ nil, "path" }), "path")
    assert.is.same(path.join({ "some", "path" }), [[some\path]])
    assert.is.same(path.join({ "some", [[path\]] }), [[some\path\]])
    assert.is.same(path.join({ "c:/some", "path" }), "c:/some/path")
    assert.is.same(path.join({ [[c:\some\]], "path" }), [[c:\some\path]])
    assert.is.same(path.join({ [[c:\some\]], "path", "foo", "bar" }), [[c:\some\path\foo\bar]])
    assert.is.same(path.join({ "~/some/", "path" }), "~/some/path")
    assert.is.same(path.join({ [[~\some\]], "path" }), [[~\some\path]])
  end)

  it("Shorten", function()
    utils.__IS_WINDOWS = false
    assert.are.equal(path.shorten(""), "")
    assert.are.equal(path.shorten("/"), "/")
    assert.are.equal(path.shorten("/foo"), "/foo")
    assert.are.equal(path.shorten("/foo/"), "/f/")
    assert.are.equal(path.shorten("/foo/bar"), "/f/bar")
    assert.are.equal(path.shorten("/foo/bar/baz"), "/f/b/baz")
    assert.are.equal(path.shorten("~/foo/bar/baz"), "~/f/b/baz")
    assert.are.equal(path.shorten("~/foo/bar/baz/"), "~/f/b/b/")
    assert.are.equal(path.shorten("~/foo/bar/baz//"), "~/f/b/b//")
    assert.are.equal(path.shorten("~/.foo/.bar/baz"), "~/.f/.b/baz")
    assert.are.equal(path.shorten("~/foo/bar/baz", 2), "~/fo/ba/baz")
    assert.are.equal(path.shorten("~/fo/barrr/baz", 3), "~/fo/bar/baz")
    assert.are.equal(path.shorten([[/foo\bar]]), [[/foo\bar]])
    -- multibyte characters
    assert.are.equal(path.shorten("/ñab/bar"), "/ñ/bar")
    assert.are.equal(path.shorten("/אבגד/bar"), "/א/bar")
    assert.are.equal(path.shorten("/こんにちは/bar"), "/こ/bar")
    assert.are.equal(vim.fn.pathshorten("/ñab/bar"), path.shorten("/ñab/bar"))
    assert.are.equal(vim.fn.pathshorten("/אבגד/bar"), path.shorten("/אבגד/bar"))
    assert.are.equal(vim.fn.pathshorten("/こんにちは/bar"), path.shorten("/こんにちは/bar"))

    utils.__IS_WINDOWS = true
    assert.are.equal(path.shorten("/foo"), [[\foo]])
    assert.are.equal(path.shorten([[/foo\bar]]), [[\f\bar]])
    assert.are.equal(path.shorten([[/foo/bar]]), [[\f\bar]])
    assert.are.equal(path.shorten([[/foo/bar\baz]]), [[\f\b\baz]])
    assert.are.equal(path.shorten([[\]]), [[\]])
    assert.are.equal(path.shorten([[c:/]]), [[c:/]])
    assert.are.equal(path.shorten([[c:\]]), [[c:\]])
    assert.are.equal(path.shorten([[c:\foo]]), [[c:\foo]])
    assert.are.equal(path.shorten([[c:\foo\bar]]), [[c:\f\bar]])
    assert.are.equal(path.shorten([[c:\foo\bar\baz]]), [[c:\f\b\baz]])
    assert.are.equal(path.shorten([[c:\.foo\.bar\baz]]), [[c:\.f\.b\baz]])
    assert.are.equal(path.shorten([[c:/foo\bar]]), [[c:/f/bar]])
    assert.are.equal(path.shorten([[~/foo/bar]]), [[~/f/bar]])
    assert.are.equal(path.shorten([[~\foo\bar]]), [[~\f\bar]])
    assert.are.equal(path.shorten([[~\foo/bar]]), [[~\f\bar]])
    assert.are.equal(path.shorten([[~\foo\bar\]]), [[~\f\b\]])
    -- override separator auto-detect
    assert.are.equal(path.shorten([[c:\foo\bar]], nil, [[/]]), [[c:/f/bar]])
    assert.are.equal(path.shorten([[c:/foo\bar]], nil, [[\]]), [[c:\f\bar]])
    -- shorten len
    assert.are.equal(path.shorten([[c:\foo\bar\baz]], 2), [[c:\fo\ba\baz]])
    assert.are.equal(path.shorten([[c:/foo\bar\baz]], 2), [[c:/fo/ba/baz]])
    utils.__IS_WINDOWS = nil
  end)
end)
