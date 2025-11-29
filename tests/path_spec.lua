local helpers = require("fzf-lua.test.helpers")
local assert = helpers.assert

local fzf = require("fzf-lua")
local path = fzf.path
local utils = fzf.utils
local eq = assert.are.equal

describe("Testing path module", function()
  it("separator", function()
    utils.__IS_WINDOWS = false
    eq(path.separator(), "/")
    eq(path.separator(""), "/")
    eq(path.separator("~/foo"), "/")
    eq(path.separator([[~\foo]]), "/")
    eq(path.separator([[c:\foo]]), "/")

    utils.__IS_WINDOWS = true
    eq(path.separator(), [[\]])
    eq(path.separator(""), [[\]])
    eq(path.separator("~/foo"), "/")
    eq(path.separator([[~\foo]]), [[\]])
    eq(path.separator([[c:\foo]]), [[\]])
    eq(path.separator([[foo\bar]]), [[\]])
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
    eq(path.add_trailing(""), "/")
    eq(path.add_trailing("/"), "/")
    eq(path.add_trailing("/some"), "/some/")
    eq(path.add_trailing("/some/"), "/some/")
    utils.__IS_WINDOWS = true
    eq(path.add_trailing(""), [[\]])
    eq(path.add_trailing("/"), [[/]])
    eq(path.add_trailing("/some"), [[/some\]])
    eq(path.add_trailing("/some/"), [[/some/]])
    eq(path.add_trailing([[C:\some\]]), [[C:\some\]])
    eq(path.add_trailing([[C:\some]]), [[C:\some\]])
    eq(path.add_trailing([[C:/some]]), [[C:/some/]])
    eq(path.add_trailing([[~/some]]), [[~/some/]])
    eq(path.add_trailing([[some\path]]), [[some\path\]])
  end)

  it("Remove trailing separator", function()
    utils.__IS_WINDOWS = false
    eq(path.remove_trailing(""), "")
    eq(path.remove_trailing("/"), "")
    eq(path.remove_trailing("//"), "")
    eq(path.remove_trailing("/some"), "/some")
    eq(path.remove_trailing("/some/"), "/some")
    eq(path.remove_trailing("/some/////"), "/some")
    eq(path.remove_trailing([[/some\]]), [[/some\]])
    utils.__IS_WINDOWS = true
    eq(path.remove_trailing(""), "")
    eq(path.remove_trailing("/"), "")
    eq(path.remove_trailing("//"), "")
    eq(path.remove_trailing("/some"), "/some")
    eq(path.remove_trailing("/some/"), "/some")
    eq(path.remove_trailing("/some/////"), "/some")
    eq(path.remove_trailing([[/some\]]), [[/some]])
    eq(path.remove_trailing([[C:\some\]]), [[C:\some]])
    eq(path.remove_trailing([[C:\some\\\\//]]), [[C:\some]])
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
    eq(path.strip_cwd_prefix(""), "")
    eq(path.strip_cwd_prefix("./"), "")
    eq(path.strip_cwd_prefix([[.\]]), [[.\]])
    eq(path.strip_cwd_prefix("/some/path"), "/some/path")
    eq(path.strip_cwd_prefix("./some/path/"), "some/path/")

    utils.__IS_WINDOWS = true
    eq(path.strip_cwd_prefix(""), "")
    eq(path.strip_cwd_prefix("./"), "")
    eq(path.strip_cwd_prefix([[.\]]), "")
    eq(path.strip_cwd_prefix("/some/path"), "/some/path")
    eq(path.strip_cwd_prefix("./some/path/"), "some/path/")
    eq(path.strip_cwd_prefix([[.\some\path/]]), [[some\path/]])
    eq(path.strip_cwd_prefix([[c:\some\path]]), [[c:\some\path]])
  end)

  it("Tail", function()
    utils.__IS_WINDOWS = false
    eq(path.tail(""), "")
    eq(path.tail("/"), "/")
    eq(path.tail("foo"), "foo")
    eq(path.tail(".foo"), ".foo")
    eq(path.tail("/foo"), "foo")
    eq(path.tail("/foo/"), "foo/")
    eq(path.tail("/foo/bar"), "bar")
    eq(path.tail([[/foo\bar]]), [[foo\bar]])

    utils.__IS_WINDOWS = true
    eq(path.tail(""), "")
    eq(path.tail("/"), "/")
    eq(path.tail([[\]]), [[\]])
    eq(path.tail("foo"), "foo")
    eq(path.tail(".foo"), ".foo")
    eq(path.tail([[c:\foo]]), "foo")
    eq(path.tail([[c:\foo\]]), [[foo\]])
    eq(path.tail([[c:\foo\bar]]), "bar")
    eq(path.tail([[c:/foo\bar]]), "bar")
    eq(path.tail([[c:/foo//\//bar]]), "bar")
  end)

  it("Parent", function()
    utils.__IS_WINDOWS = false
    eq(path.parent(""), nil)
    eq(path.parent("/"), nil)
    eq(path.parent("/foo"), "/")
    eq(path.parent("/foo/bar"), "/foo/")
    eq(path.parent("/foo/bar", true), "/foo")
    eq(path.parent([[/foo\bar]]), [[/]])

    utils.__IS_WINDOWS = true
    eq(path.parent(""), nil)
    eq(path.parent("/"), nil)
    eq(path.parent([[\]]), nil)
    eq(path.parent([[c:]]), nil)
    eq(path.parent([[c:\foo]]), [[c:\]])
    eq(path.parent([[c:\foo]], true), [[c:]])
    eq(path.parent([[c:\foo\bar]]), [[c:\foo\]])
    eq(path.parent([[c:\foo/bar]]), [[c:\foo/]])
    eq(path.parent([[c:/foo//\//bar]], true), [[c:/foo]])
  end)

  it("Normalize", function()
    utils.__IS_WINDOWS = false
    eq(path.normalize("/some/path"), "/some/path")
    eq(path.normalize([[\some\path]]), [[\some\path]])
    eq(path.normalize("~/some/path"), path.HOME() .. "/some/path")
    utils.__IS_WINDOWS = true
    eq(path.normalize("/some/path"), "/some/path")
    eq(path.normalize([[\some\path]]), "/some/path")
    eq(path.normalize("~/some/path"), path.normalize(path.HOME()) .. "/some/path")
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
    ---@type ({ [1]: string, [2]: string, [3]: [boolean, string?] })[]
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
      eq({ path.is_relative_to(v[1], v[2]) }, v[3])
      -- mini.nvim shim support 2 args only
      -- string.format('\n\nis_relative_to("%s", "%s") ~= "%s"\n', v[1], v[2], v[3][2])
    end
    utils.__IS_WINDOWS = true
    for _, v in ipairs(win) do
      eq({ path.is_relative_to(v[1], v[2]) }, v[3])
      -- string.format('\n\nis_relative_to("%s", "%s") ~= "%s"\n', v[1], v[2], v[3][2])
    end
  end)

  it("Extension", function()
    utils.__IS_WINDOWS = false
    eq(path.extension("/some/path/foobar"), nil)
    eq(path.extension("/some/pa.th/foobar"), nil)
    assert.is.same(path.extension("/some/path/foobar."), "")
    assert.is.same(path.extension("/some/path/foo.bar"), "bar")
    assert.is.same(path.extension("/some/path/foo.bar.baz"), "baz")
    assert.is.same(path.extension("/some/path/.foobar"), "foobar")
    -- override that doesn't "tail" the path
    eq(path.extension("/some/pa.th/foobar", true), "th/foobar")
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
    eq(path.shorten(""), "")
    eq(path.shorten("/"), "/")
    eq(path.shorten("/foo"), "/foo")
    eq(path.shorten("/foo/"), "/f/")
    eq(path.shorten("/foo/bar"), "/f/bar")
    eq(path.shorten("/foo/bar/baz"), "/f/b/baz")
    eq(path.shorten("~/foo/bar/baz"), "~/f/b/baz")
    eq(path.shorten("~/foo/bar/baz/"), "~/f/b/b/")
    eq(path.shorten("~/foo/bar/baz//"), "~/f/b/b//")
    eq(path.shorten("~/.foo/.bar/baz"), "~/.f/.b/baz")
    eq(path.shorten("~/foo/bar/baz", 2), "~/fo/ba/baz")
    eq(path.shorten("~/fo/barrr/baz", 3), "~/fo/bar/baz")
    eq(path.shorten([[/foo\bar]]), [[/foo\bar]])
    -- multibyte characters
    eq(path.shorten("/ñab/bar"), "/ñ/bar")
    eq(path.shorten("/אבגד/bar"), "/א/bar")
    eq(path.shorten("/こんにちは/bar"), "/こ/bar")
    eq(vim.fn.pathshorten("/ñab/bar"), path.shorten("/ñab/bar"))
    eq(vim.fn.pathshorten("/אבגד/bar"), path.shorten("/אבגד/bar"))
    eq(vim.fn.pathshorten("/こんにちは/bar"), path.shorten("/こんにちは/bar"))

    utils.__IS_WINDOWS = true
    eq(path.shorten("/foo"), [[\foo]])
    eq(path.shorten([[/foo\bar]]), [[\f\bar]])
    eq(path.shorten([[/foo/bar]]), [[\f\bar]])
    eq(path.shorten([[/foo/bar\baz]]), [[\f\b\baz]])
    eq(path.shorten([[\]]), [[\]])
    eq(path.shorten([[c:/]]), [[c:/]])
    eq(path.shorten([[c:\]]), [[c:\]])
    eq(path.shorten([[c:\foo]]), [[c:\foo]])
    eq(path.shorten([[c:\foo\bar]]), [[c:\f\bar]])
    eq(path.shorten([[c:\foo\bar\baz]]), [[c:\f\b\baz]])
    eq(path.shorten([[c:\.foo\.bar\baz]]), [[c:\.f\.b\baz]])
    eq(path.shorten([[c:/foo\bar]]), [[c:/f/bar]])
    eq(path.shorten([[~/foo/bar]]), [[~/f/bar]])
    eq(path.shorten([[~\foo\bar]]), [[~\f\bar]])
    eq(path.shorten([[~\foo/bar]]), [[~\f\bar]])
    eq(path.shorten([[~\foo\bar\]]), [[~\f\b\]])
    -- override separator auto-detect
    eq(path.shorten([[c:\foo\bar]], nil, [[/]]), [[c:/f/bar]])
    eq(path.shorten([[c:/foo\bar]], nil, [[\]]), [[c:\f\bar]])
    -- shorten len
    eq(path.shorten([[c:\foo\bar\baz]], 2), [[c:\fo\ba\baz]])
    eq(path.shorten([[c:/foo\bar\baz]], 2), [[c:/fo/ba/baz]])
    utils.__IS_WINDOWS = nil
  end)

  describe("entry_to_file", function()
    local fs_stat = vim.uv.fs_stat
    before_each(function()
      local t = {
        ["/tmp/foo:bar.txt"] = true,
        ["/tmp/test:foo:bar.txt"] = true,
        ["C:\\Users\\foo:bar"] = true
      }
      -- assume these files exists, maybe we can create them
      vim.uv.fs_stat = function(f)
        if t[f] then return t[f] end
        return fs_stat(f)
      end
    end)
    after_each(function() vim.uv.fs_stat = fs_stat end)

    -- actually this won't work as expected when a pathname is prefix of another
    it("file with colons", function()
      local e, p
      p = "/tmp/foo:bar.txt"
      eq(path.entry_to_file(p), { stripped = p, path = p, line = 0, col = 0 })
      e = "/tmp/foo:bar.txt:42"
      eq(path.entry_to_file(e), { stripped = e, path = p, line = 42, col = 0 })
      e = "/tmp/foo:bar.txt:42:"
      eq(path.entry_to_file(e), { stripped = e, path = p, line = 42, col = 0 })
      e = "/tmp/foo:bar.txt:42:7"
      eq(path.entry_to_file(e), { stripped = e, path = p, line = 42, col = 7 })
      e = "/tmp/foo:bar.txt:42:7:"
      eq(path.entry_to_file(e), { stripped = e, path = p, line = 42, col = 7 })

      eq(path.entry_to_file("/tmp/test:foo:bar.txt:8:2"), {
        stripped = "/tmp/test:foo:bar.txt:8:2",
        path = "/tmp/test:foo:bar.txt",
        line = 8,
        col = 2,
      })

      utils.__IS_WINDOWS = true
      eq(path.entry_to_file("C:\\Users\\foo:bar:12:3"), {
        col = 3,
        line = 12,
        path = "C:\\Users\\foo:bar",
        stripped = "C:\\Users\\foo:bar:12:3"
      })
      utils.__IS_WINDOWS = false
    end)

    it("tilde expansion", function()
      helpers.SKIP_IF_WIN()
      local home = os.getenv("HOME")
      eq(path.entry_to_file("~/test.txt:1:2"), {
        stripped = home .. "/test.txt:1:2",
        path = home .. "/test.txt",
        line = 1,
        col = 2,
      })
    end)

    it("buffer", function()
      helpers.SKIP_IF_WIN()
      local buf = vim.api.nvim_create_buf(false, true)
      local bufname = "/tmp/test.txt"
      vim.api.nvim_buf_set_name(buf, bufname)
      local e = ("[%d]%s%s:42"):format(buf, utils.nbsp, bufname)
      eq(path.entry_to_file(e), {
        bufname = helpers.IS_MAC() and vim.fs.joinpath("/private", bufname) or bufname,
        bufnr = buf,
        col = 0,
        line = 42,
        path = bufname,
        stripped = "/tmp/test.txt:42",
        terminal = false
      })
    end)

    it("man://", function()
      -- must be loaded?
      local buf = vim.api.nvim_create_buf(false, true)
      local bufname = "man://ls(1)"
      vim.api.nvim_buf_set_name(buf, bufname)
      eq(true, path.is_uri(bufname))
      -- local e = ("[%d]%s%s:42:7"):format(buf, utils.nbsp, bufname)
      local e = ("[%d]%s%s:42:7:"):format(buf, utils.nbsp, bufname)
      eq(path.entry_to_file(e), {
        bufname = "man://ls(1)",
        bufnr = buf,
        col = 7,
        line = 42,
        path = "man://ls(1)",
        stripped = "man://ls(1):42:7:",
        terminal = false
      })
    end)

    it("force_uri", function()
      local r = {
        col = 1,
        line = 1,
        range = {
          start = { character = 0, line = 0 },
          ["end"] = { character = 0, line = 0 },
        },
        stripped = "file:///tmp/test.txt:5:6"
      }
      eq(path.entry_to_file("/tmp/test.txt:5:6", {}, true), r)
      eq(path.entry_to_file("file:///tmp/test.txt:5:6", {}, false), r)
      eq(path.entry_to_file("file:///tmp/test.txt:5:6", {}, true), r)
    end)
  end)
end)
