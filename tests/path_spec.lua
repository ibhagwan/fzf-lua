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
      vim.api.nvim_buf_delete(buf, { force = true })
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
      vim.api.nvim_buf_delete(buf, { force = true })
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

    it("parse loaded path", function()
      helpers.SKIP_IF_WIN()
      local win = vim.api.nvim_get_current_win()
      local r = {}
      vim.cmd.new()
      local name = "/tmp/foo:bar.txt"
      vim.cmd.edit(name)
      vim.cmd([[sil write]])
      eq(path.entry_to_file(name, r), {
        col = 0,
        line = 0,
        stripped = name,
        path = name,
        bufnr = vim.fn.bufnr(),
        bufname = name,
      })
      vim.api.nvim_buf_delete(0, { force = true })
      vim.api.nvim_set_current_win(win)
    end)
  end)

  describe("jj_root", function()
    local fs_stat = vim.uv.fs_stat
    local io_systemlist = utils.io_systemlist

    after_each(function()
      vim.uv.fs_stat = fs_stat
      utils.io_systemlist = io_systemlist
    end)

    it("returns nil when no .jj directory exists", function()
      vim.uv.fs_stat = function(_) return nil end
      eq(path.jj_root({ cwd = "/some/path/without/jj" }, true), nil)
    end)

    it("returns nil when .jj exists but jj command fails", function()
      vim.uv.fs_stat = function(p)
        if p == "/some/project/.jj" then return { type = "directory" } end
        return nil
      end
      utils.io_systemlist = function(_)
        return { "error: not a jj repo" }, 1
      end
      eq(path.jj_root({ cwd = "/some/project" }, true), nil)
    end)

    it("returns root when .jj exists and jj command succeeds", function()
      vim.uv.fs_stat = function(p)
        if p == "/some/project/.jj" then return { type = "directory" } end
        return nil
      end
      utils.io_systemlist = function(_)
        return { "/some/project" }, 0
      end
      eq(path.jj_root({ cwd = "/some/project" }, true), "/some/project")
    end)

    it("walks up to find .jj in parent directory", function()
      vim.uv.fs_stat = function(p)
        if p == "/some/project/.jj" then return { type = "directory" } end
        return nil
      end
      utils.io_systemlist = function(_)
        return { "/some/project" }, 0
      end
      eq(path.jj_root({ cwd = "/some/project/deep/subdir" }, true), "/some/project")
    end)

    it("passes -R flag when opts.cwd is set", function()
      local captured_cmd
      vim.uv.fs_stat = function(p)
        if p == "/workspace/.jj" then return { type = "directory" } end
        return nil
      end
      utils.io_systemlist = function(cmd)
        captured_cmd = cmd
        return { "/workspace" }, 0
      end
      path.jj_root({ cwd = "/workspace" }, true)
      assert.is.same(captured_cmd, { "jj", "-R", "/workspace", "root", "--ignore-working-copy" })
    end)

    it("omits -R flag when no opts.cwd", function()
      -- When opts.cwd is nil, we use uv.cwd() for the walk-up but
      -- don't pass -R to the jj command
      local real_cwd = vim.uv.cwd()
      vim.uv.fs_stat = function(p)
        if p == real_cwd .. "/.jj" then return { type = "directory" } end
        -- Walk up parents
        return nil
      end
      utils.io_systemlist = function(cmd)
        assert.is.same(cmd, { "jj", "root", "--ignore-working-copy" })
        return { real_cwd }, 0
      end
      path.jj_root({}, true)
    end)
  end)

  describe("is_jj_repo", function()
    local fs_stat = vim.uv.fs_stat
    local io_systemlist = utils.io_systemlist

    after_each(function()
      vim.uv.fs_stat = fs_stat
      utils.io_systemlist = io_systemlist
    end)

    it("returns false when not in a jj repo", function()
      vim.uv.fs_stat = function(_) return nil end
      assert.is.False(path.is_jj_repo({ cwd = "/not/a/jj/repo" }, true))
    end)

    it("returns true when in a jj repo", function()
      vim.uv.fs_stat = function(p)
        if p == "/jj/workspace/.jj" then return { type = "directory" } end
        return nil
      end
      utils.io_systemlist = function(_)
        return { "/jj/workspace" }, 0
      end
      assert.is.True(path.is_jj_repo({ cwd = "/jj/workspace" }, true))
    end)
  end)

  ---@diagnostic disable: duplicate-set-field
  describe("vcs_files", function()
    local files_provider = require("fzf-lua.providers.files")
    local jj_provider = require("fzf-lua.providers.jj")
    local git_provider = require("fzf-lua.providers.git")

    local orig_is_jj_repo = path.is_jj_repo
    local orig_is_git_repo = path.is_git_repo
    local orig_jj_files = jj_provider.files
    local orig_git_files = git_provider.files
    local orig_files = files_provider.files

    after_each(function()
      path.is_jj_repo = orig_is_jj_repo
      path.is_git_repo = orig_is_git_repo
      jj_provider.files = orig_jj_files
      git_provider.files = orig_git_files
      files_provider.files = orig_files
    end)

    it("delegates to jj.files when in a jj repo", function()
      local called = nil
      path.is_jj_repo = function() return true end
      path.is_git_repo = function() return true end -- should not matter
      jj_provider.files = function() called = "jj" end
      git_provider.files = function() called = "git" end
      files_provider.files = function() called = "files" end
      files_provider.vcs_files({})
      eq(called, "jj")
    end)

    it("delegates to git.files when in git repo but not jj", function()
      local called = nil
      path.is_jj_repo = function() return false end
      path.is_git_repo = function() return true end
      jj_provider.files = function() called = "jj" end
      git_provider.files = function() called = "git" end
      files_provider.files = function() called = "files" end
      files_provider.vcs_files({})
      eq(called, "git")
    end)

    it("delegates to files when not in any vcs repo", function()
      local called = nil
      path.is_jj_repo = function() return false end
      path.is_git_repo = function() return false end
      jj_provider.files = function() called = "jj" end
      git_provider.files = function() called = "git" end
      files_provider.files = function() called = "files" end
      files_provider.vcs_files({})
      eq(called, "files")
    end)

    it("prefers jj over git in colocated repos", function()
      local called = nil
      path.is_jj_repo = function() return true end
      path.is_git_repo = function() return true end
      jj_provider.files = function() called = "jj" end
      git_provider.files = function() called = "git" end
      files_provider.vcs_files({})
      eq(called, "jj")
    end)

    it("handles nil opts without error", function()
      local called = nil
      path.is_jj_repo = function() return false end
      path.is_git_repo = function() return false end
      jj_provider.files = function() called = "jj" end
      git_provider.files = function() called = "git" end
      files_provider.files = function() called = "files" end
      files_provider.vcs_files()
      eq(called, "files")
    end)

    it("sets winopts.title to 'VCS Files (jj)' in a jj repo", function()
      local received_opts
      path.is_jj_repo = function() return true end
      path.is_git_repo = function() return false end
      jj_provider.files = function(opts) received_opts = opts end
      files_provider.vcs_files({})
      eq(received_opts.winopts.title, " VCS Files (jj) ")
    end)

    it("sets winopts.title to 'VCS Files (git)' in a git repo", function()
      local received_opts
      path.is_jj_repo = function() return false end
      path.is_git_repo = function() return true end
      git_provider.files = function(opts) received_opts = opts end
      files_provider.vcs_files({})
      eq(received_opts.winopts.title, " VCS Files (git) ")
    end)

    it("does not set winopts.title when falling back to files", function()
      local received_opts
      path.is_jj_repo = function() return false end
      path.is_git_repo = function() return false end
      files_provider.files = function(opts) received_opts = opts end
      files_provider.vcs_files({})
      eq(received_opts.winopts, nil)
    end)

    it("does not override user-supplied winopts.title", function()
      local received_opts
      path.is_jj_repo = function() return true end
      path.is_git_repo = function() return false end
      jj_provider.files = function(opts) received_opts = opts end
      files_provider.vcs_files({ winopts = { title = " My Title " } })
      eq(received_opts.winopts.title, " My Title ")
    end)
  end)

  describe("git_files quiet failure", function()
    local orig_git_root = path.git_root

    after_each(function()
      path.git_root = orig_git_root
    end)

    it("shows info message and returns nil when not in a git repo", function()
      local info_msg = nil
      local orig_info = utils.info
      utils.info = function(msg) info_msg = msg end
      -- path.git_root calls utils.info when noerr is falsy
      path.git_root = function(opts, noerr)
        if not noerr then
          utils.info("not a git repository")
        end
        return nil
      end
      local git_provider = require("fzf-lua.providers.git")
      local config = require("fzf-lua.config")
      local orig_normalize = config.normalize_opts
      config.normalize_opts = function(opts) return opts or {} end
      local result = git_provider.files({})
      config.normalize_opts = orig_normalize
      utils.info = orig_info
      eq(info_msg, "not a git repository")
      eq(result, nil)
    end)
  end)

  describe("_headers configuration", function()
    local defaults = require("fzf-lua.defaults").defaults

    it("git.files has cwd in _headers", function()
      assert.is.True(defaults.git.files._headers ~= nil)
      assert.is.True(vim.tbl_contains(defaults.git.files._headers, "cwd"))
    end)

    it("jj.files has cwd in _headers", function()
      assert.is.True(defaults.jj.files._headers ~= nil)
      assert.is.True(vim.tbl_contains(defaults.jj.files._headers, "cwd"))
    end)
  end)
end)
