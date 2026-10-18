local helpers = require("fzf-lua.test.helpers")
local assert = helpers.assert

local MiniTest = require("mini.test")
local libuv = require("fzf-lua.libuv")
local eq = assert.are.equal
local same = assert.are.same

describe("Testing libuv module", function()
  it("is_escaped (posix)", function()
    assert.is.False(libuv.is_escaped([[]], false))
    assert.is.True(libuv.is_escaped([[""]], false))
    assert.is.True(libuv.is_escaped([['']], false))
    assert.is.True(libuv.is_escaped([['foo']], false))
  end)

  it("is_escaped (win)", function()
    assert.is.False(libuv.is_escaped([[]], true))
    assert.is.True(libuv.is_escaped([[""]], true))
    assert.is.True(libuv.is_escaped([[^"^"]], true))
    assert.is.False(libuv.is_escaped([['']], true))
  end)

  it("shellescape (win bslash)", function()
    eq(libuv.shellescape([[]], 1), [[""]])
    eq(libuv.shellescape([[^]], 1), [["^"]])
    eq(libuv.shellescape([[""]], 1), [["\"\""]])
    eq(libuv.shellescape([["^"]], 1), [["\"^\""]])
    eq(libuv.shellescape([[foo]], 1), [["foo"]])
    eq(libuv.shellescape([["foo"]], 1), [["\"foo\""]])
    eq(libuv.shellescape([["foo"bar"]], 1), [["\"foo\"bar\""]])
    eq(libuv.shellescape([[foo"bar]], 1), [["foo\"bar"]])
    eq(libuv.shellescape([[foo""bar]], 1), [["foo\"\"bar"]])
    eq(libuv.shellescape([["foo\"bar"]], 1), [["\"foo\\\"bar\""]])
    eq(libuv.shellescape([[foo\]], 1), [["foo\\"]])
    eq(libuv.shellescape([[foo\\]], 1), [["foo\\\\"]])
    eq(libuv.shellescape([[foo\^]], 1), [["foo\^"]])
    eq(libuv.shellescape([[foo\\\\]], 1), [["foo\\\\\\\\"]])
    eq(libuv.shellescape([[foo\"]], 1), [["foo\\\""]])
    eq(libuv.shellescape([["foo\"]], 1), [["\"foo\\\""]])
    eq(libuv.shellescape([["foo\""]], 1), [["\"foo\\\"\""]])
    eq(libuv.shellescape([[foo\bar]], 1), [["foo\bar"]])
    eq(libuv.shellescape([[foo\\bar]], 1), [["foo\\bar"]])
    eq(libuv.shellescape([[foo\\"bar]], 1), [["foo\\\\\"bar"]])
    eq(libuv.shellescape([[foo\\\"bar]], 1), [["foo\\\\\\\"bar"]])
  end)

  it("shellescape (win caret)", function()
    eq(libuv.shellescape([[]], 2), [[^"^"]])
    eq(libuv.shellescape([["]], 2), [[^"\^"^"]])
    eq(libuv.shellescape([[^"]], 2), [[^"^^\^"^"]])
    eq(libuv.shellescape([[\"]], 2), [[^"\\\^"^"]])
    eq(libuv.shellescape([[\^"]], 2), [[^"^^\\\^"^"]])
    eq(libuv.shellescape([[^"^"]], 2), [[^"^^\^"^^\^"^"]])
    eq(libuv.shellescape([[__^^"^"__]], 2), [[^"__^^^^\^"^^\^"__^"]])
    eq(libuv.shellescape([[__!^^"^"__]], 2),
      -- 1st: ^"_^!^^^^\^"^^\^"_^"
      -- 2nd: ^"_^^^!^^^^^^^^^^\\\^"^^^^^^\\\^"_^"
      [[^"__^^^!^^^^^^^^^^\\\^"^^^^^^\\\^"__^"]])
    eq(libuv.shellescape([[__^^^^\^"^^\^"__]], 2),
      [[^"__^^^^^^^^^^\\\^"^^^^^^\\\^"__^"]])
    eq(libuv.shellescape([[^]], 2), [[^"^^^"]])
    eq(libuv.shellescape([[^^]], 2), [[^"^^^^^"]])
    eq(libuv.shellescape([[^^^]], 2), [[^"^^^^^^^"]])
    eq(libuv.shellescape([[^!^]], 2), [[^"^^^^^^^!^^^^^"]])
    eq(libuv.shellescape([[!^"]], 2),
      -- 1st inner: ^!^^\^"
      -- 2nd inner: ^^^!^^^^^^\\\^"
      [[^"^^^!^^^^^^\\\^"^"]])
    eq(libuv.shellescape([[!\"]], 2), [[^"^^^!^^\\\\\\\^"^"]])
    eq(libuv.shellescape([[!\^"]], 2), [[^"^^^!^^^^^^\\\\\\\^"^"]])
    eq(libuv.shellescape([[()%^"<>&|;]], 2), [[^"^(^)^%^^\^"^<^>^&^|^;^"]])
    eq(libuv.shellescape([[()%^"<>&|;!]], 2),
      -- 1st inner: ^(^)^%^^\^"^<^>^&^|^!
      -- 2nd inner: ^^^(^^^)^^^%^^^^^^\^"^^^<^^^>^^^&^^^|^^^!
      [[^"^^^(^^^)^^^%^^^^^^\\\^"^^^<^^^>^^^&^^^|^^^;^^^!^"]])
    eq(libuv.shellescape([[foo]], 2), [[^"foo^"]])
    eq(libuv.shellescape([[foo\]], 2), [[^"foo\\^"]])
    eq(libuv.shellescape([[foo^]], 2), [[^"foo^^^"]])
    eq(libuv.shellescape([[foo\\]], 2), [[^"foo\\\\^"]])
    eq(libuv.shellescape([[foo\\\]], 2), [[^"foo\\\\\\^"]])
    eq(libuv.shellescape([[foo\\\\]], 2), [[^"foo\\\\\\\\^"]])
    eq(libuv.shellescape([[f!oo]], 2), [[^"f^^^!oo^"]])
    eq(libuv.shellescape([[^"foo^"]], 2), [[^"^^\^"foo^^\^"^"]])
    eq(libuv.shellescape([[\^"foo\^"]], 2), [[^"^^\\\^"foo^^\\\^"^"]])
    eq(libuv.shellescape([[foo""bar]], 2), [[^"foo\^"\^"bar^"]])
    eq(libuv.shellescape([[foo^"^"bar]], 2), [[^"foo^^\^"^^\^"bar^"]])
    eq(libuv.shellescape([["foo\"bar"]], 2), [[^"\^"foo\\\^"bar\^"^"]])
    eq(libuv.shellescape([[foo\^"]], 2), [[^"foo^^\\\^"^"]])
    eq(libuv.shellescape([[foo\"]], 2), [[^"foo\\\^"^"]])
    eq(libuv.shellescape([[^"foo\^"^"]], 2), [[^"^^\^"foo^^\\\^"^^\^"^"]])
    eq(libuv.shellescape([[foo\"bar]], 2), [[^"foo\\\^"bar^"]])
    eq(libuv.shellescape([[foo\\"bar]], 2), [[^"foo\\\\\^"bar^"]])
    eq(libuv.shellescape([[foo\\^^"bar]], 2), [[^"foo\\^^^^\^"bar^"]])
    eq(libuv.shellescape([[foo\\\^^^"]], 2), [[^"foo\\\^^^^^^\^"^"]])
  end)

  it("cmd_argv round-trips shellescape (cmd style)", function()
    -- `win_style = true` forces the `cmd.exe` caret escaping (the default
    -- on Windows), also runs on posix CI
    local values = {
      "foo", "a b", "x^y", "a^^b", "p%q", "a&b", "it's", [["q"]], [[E\f]],
      "汉 é", "bang!x", "eq=a", "semi;x", "lt<x", "pipe|x", "paren(x)",
      "amp&pipe|semi;", "trailback\\", " caret^ leading", "^caret",
      "trailcaret^", [[a"b]], [[a\"b]], "two  spaces", "10%%", "a!b",
      "%TEMP%", "a(b)c", "cur|pipe", "d>e", "a<b",
      "load:+execute-silent:echo hi",
    }
    for _, v in ipairs(values) do
      same(libuv.cmd_argv(libuv.shellescape(v, true)), { v })
    end
    -- the pre-escaped user fragment pattern, e.g. test harness
    -- `"--bind=" .. shellescape("load:+execute-silent:...")`
    same(libuv.cmd_argv("--bind=" .. libuv.shellescape("load:+execute-silent:echo hi", true)),
      { "--bind=load:+execute-silent:echo hi" })
  end)

  it("cmd_argv parses cmd fragments", function()
    same(libuv.cmd_argv(""), {})
    same(libuv.cmd_argv("   "), {})
    same(libuv.cmd_argv("--no-multi --layout=reverse"), { "--no-multi", "--layout=reverse" })
    same(libuv.cmd_argv([[--header="a b" --no-multi]]), { "--header=a b", "--no-multi" })
    same(libuv.cmd_argv("--bind=ctrl-a:first --expect=ctrl-e"),
      { "--bind=ctrl-a:first", "--expect=ctrl-e" })
    -- caret escaping quotes/spaces (user args are cmd fragments)
    same(libuv.cmd_argv([[--header=^"a b^"]]), { "--header=a b" })
    same(libuv.cmd_argv([[--bind=^"load:+execute-silent:echo^ hi^"]]),
      { "--bind=load:+execute-silent:echo hi" })
    -- carets are only special outside of double quotes (cmd.exe): inside a
    -- quoted fragment a caret is literal and only the quote toggles state
    same(libuv.cmd_argv([["x^y"]]), { "x^y" })
    same(libuv.cmd_argv([["x^^y"]]), { "x^^y" })
    same(libuv.cmd_argv([["a^"b"]]), { "a^b" })
    same(libuv.cmd_argv([["A ^" B"]]), { "A ^", "B" })
    -- a doubled `""` inside quotes is one literal quote, the pair is consumed
    -- and the quote state toggles once (Go runtime `os/exec_windows.go`
    -- "Prior to 2008" rule; verified against `fzf.exe` driven through
    -- `cmd.exe`, e.g. fzf's own `--query` parser)
    same(libuv.cmd_argv([[--header="say ""hi"""]]), { [[--header=say "hi"]] })
    same(libuv.cmd_argv([["a""b"]]), { [[a"b]] })
    -- the state toggles after the pair: the space is not quoted anymore
    same(libuv.cmd_argv([["say ""hi"" tail"]]), { [[say "hi]], "tail" })
    -- caret inside quotes stays literal (`cmd.exe` pass), pair still collapses
    same(libuv.cmd_argv([["a^""b"]]), { [[a^"b]] })
    -- dangling caret: dropped outside quotes, literal inside quotes
    same(libuv.cmd_argv([["abc^"]]), { "abc^" })
    same(libuv.cmd_argv("^^"), { "^" })
    -- backslashes: literal unless collapsing before a quote (2n/2n+1 rules)
    same(libuv.cmd_argv([[C:\dir\sub]]), { [[C:\dir\sub]] })
    same(libuv.cmd_argv([[a\"b]]), { [[a"b]] })
    same(libuv.cmd_argv([[trailback\\]]), { [[trailback\\]] })
    same(libuv.cmd_argv([[\^^]]), { [[\^]] })
  end)

  it("escape_cli escapes value segments per shell, keeps literal segments", function()
    local elems = {
      { { text = "--bind=", escape = false }, { text = "ctrl-r:reload(a b)", escape = true } },
      { { text = "--query", escape = false } },
      { { text = "it's", escape = true } },
    }
    -- cmd: value segments via shellescape, flags literal, element re-fused
    local cmd = libuv.escape_cli(elems, "cmd")
    eq(cmd[1], "--bind=" .. libuv.shellescape("ctrl-r:reload(a b)"))
    eq(cmd[2], "--query")
    eq(cmd[3], libuv.shellescape("it's"))
    -- posix: value segments via posix shellescape
    local posix = libuv.escape_cli(elems, "posix")
    eq(posix[1], "--bind=" .. libuv.shellescape("ctrl-r:reload(a b)"))
    eq(posix[3], libuv.shellescape("it's"))
  end)

  it("build_fzf_cli raw segments round-trip to the escaped cli_args", function()
    -- the sync invariant: the raw `segments` second return value must, when
    -- escaped for the *current* shell, reproduce the legacy escaped `cli_args`
    -- byte-for-byte. This guards the defer-escape refactor against drift.
    local core = require("fzf-lua.core")
    local config = require("fzf-lua.config")
    local defaults = require("fzf-lua.defaults").defaults
    local opts = config.normalize_opts({ cwd = vim.fn.getcwd() }, defaults.files)
    local cli_args, segments = core.build_fzf_cli(opts)
    eq(#cli_args, #segments)
    -- no marker tables leak into the escaped string form
    for _, a in ipairs(cli_args) do eq(type(a), "string") end
    -- re-escaping the raw segments for the current shell reproduces cli_args
    local shell = helpers.IS_WIN() and "cmd" or "posix"
    same(libuv.escape_cli(segments, shell), cli_args)
  end)

  it("escape {q} (win, fzf v0.50)", function()
    eq(libuv.escape_fzf([[]], 0.50, true), [[]])
    eq(libuv.escape_fzf([[\]], 0.50, true), [[\]])
    eq(libuv.escape_fzf([[\\]], 0.50, true), [[\\]])
    eq(libuv.escape_fzf([[foo]], 0.50, true), [[foo]])
    eq(libuv.escape_fzf([[\foo]], 0.50, true), [[\\foo]])
    eq(libuv.escape_fzf([[\\foo]], 0.50, true), [[\\\\foo]])
    eq(libuv.escape_fzf([[\\\foo]], 0.50, true), [[\\\\\\foo]])
    eq(libuv.escape_fzf([[\\\\foo]], 0.50, true), [[\\\\\\\\foo]])
    eq(libuv.escape_fzf([[foo\]], 0.50, true), [[foo\]])
    eq(libuv.escape_fzf([[foo\\]], 0.50, true), [[foo\\]])
  end)

  it("unescape {q} (win, fzf v0.50)", function()
    eq(libuv.unescape_fzf([[]], 0.50, true), [[]])
    eq(libuv.unescape_fzf([[\]], 0.50, true), [[\]])
    eq(libuv.unescape_fzf([[\\]], 0.50, true), [[\\]])
    eq(libuv.unescape_fzf([[foo]], 0.50, true), [[foo]])
    eq(libuv.unescape_fzf([[\foo]], 0.50, true), [[\foo]])
    eq(libuv.unescape_fzf([[\\foo]], 0.50, true), [[\foo]])
    eq(libuv.unescape_fzf([[\\\foo]], 0.50, true), [[\foo]])
    eq(libuv.unescape_fzf([[\\\\foo]], 0.50, true), [[\\foo]])
    eq(libuv.unescape_fzf([[foo\]], 0.50, true), [[foo\]])
    eq(libuv.unescape_fzf([[foo\\]], 0.50, true), [[foo\\]])
  end)

  it("escape {q} (win, fzf v0.52)", function()
    eq(libuv.escape_fzf([[]], 0.52, true), [[]])
    eq(libuv.escape_fzf([[\]], 0.52, true), [[\]])
    eq(libuv.escape_fzf([[\\]], 0.52, true), [[\\]])
    eq(libuv.escape_fzf([[foo]], 0.52, true), [[foo]])
    eq(libuv.escape_fzf([[\foo]], 0.52, true), [[\foo]])
    eq(libuv.escape_fzf([[\\foo]], 0.52, true), [[\\foo]])
    eq(libuv.escape_fzf([[\\\foo]], 0.52, true), [[\\\foo]])
    eq(libuv.escape_fzf([[\\\\foo]], 0.52, true), [[\\\\foo]])
    eq(libuv.escape_fzf([[foo\]], 0.52, true), [[foo\]])
    eq(libuv.escape_fzf([[foo\\]], 0.52, true), [[foo\\]])
  end)

  it("unescape {q} (win, fzf v0.52)", function()
    eq(libuv.unescape_fzf([[]], 0.52, true), [[]])
    eq(libuv.unescape_fzf([[\]], 0.52, true), [[\]])
    eq(libuv.unescape_fzf([[\\]], 0.52, true), [[\\]])
    eq(libuv.unescape_fzf([[foo]], 0.52, true), [[foo]])
    eq(libuv.unescape_fzf([[\foo]], 0.52, true), [[\foo]])
    eq(libuv.unescape_fzf([[\\foo]], 0.52, true), [[\\foo]])
    eq(libuv.unescape_fzf([[\\\foo]], 0.52, true), [[\\\foo]])
    eq(libuv.unescape_fzf([[\\\\foo]], 0.52, true), [[\\\\foo]])
    eq(libuv.unescape_fzf([[foo\]], 0.52, true), [[foo\]])
    eq(libuv.unescape_fzf([[foo\\]], 0.52, true), [[foo\\]])
  end)

  it("field index", function()
    helpers.SKIP_IF_WIN() -- skip on windows (cannot expand correctly, also segment fault)
    local curwin = vim.api.nvim_get_current_win()
    vim.cmd("botright new")
    local splitwin = vim.api.nvim_get_current_win()
    local fzf = require("fzf-lua.fzf")
    local selected, exit_code
    coroutine.wrap(function()
      selected, exit_code = fzf.raw_fzf(
        helpers.IS_WIN() and "echo foo&& echo bar" or "echo foo\nbar",
        {
          "--sync",
          "--query f",
          -- no quote
          "--bind start:+transform:" .. libuv.shellescape([[echo print:{q}]]),
          "--bind start:+transform:" .. libuv.shellescape([[echo print:{}]]),
          "--bind start:+transform:" .. libuv.shellescape([[echo print:{+}]]),
          "--bind start:+transform:" .. libuv.shellescape([[echo print:{n}]]),
          "--bind start:+transform:" .. libuv.shellescape([[echo print:{+n}]]),
          -- double quote
          "--bind start:+transform:" .. libuv.shellescape([[echo print:"{q}"]]),
          "--bind start:+transform:" .. libuv.shellescape([[echo print:"{}"]]),
          "--bind start:+transform:" .. libuv.shellescape([[echo print:"{+}"]]),
          "--bind start:+transform:" .. libuv.shellescape([[echo print:"{n}"]]),
          "--bind start:+transform:" .. libuv.shellescape([[echo print:"{+n}"]]),
          -- single quote
          "--bind start:+transform:" .. libuv.shellescape([[echo print:'{q}']]),
          "--bind start:+transform:" .. libuv.shellescape([[echo print:'{}']]),
          "--bind start:+transform:" .. libuv.shellescape([[echo print:'{+}']]),
          "--bind start:+transform:" .. libuv.shellescape([[echo print:'{n}']]),
          "--bind start:+transform:" .. libuv.shellescape([[echo print:'{+n}']]),
          -- force expand on windows?
          -- "--bind result:+transform:" .. libuv.shellescape([[echo print:{q} {} {+} {n} {+n}]]),
          -- "--bind result:+select-all",
          "--bind start:+accept",
        }, { is_fzf_tmux = false })
    end)()
    -- usually new job channel is the last one
    local chans = vim.api.nvim_list_chans()
    local job = (chans[#chans] or {}).id
    eq({ 0 }, vim.fn.jobwait({ job }))
    eq(0, exit_code)
    eq(selected, {
      "f", "foo", "foo", "0", "0",
      "'f'", "'foo'", "'foo'", "0", "0",
      "f", "foo", "foo", "0", "0",
      -- "f foo foo 0 0",
      "foo",
    })
    vim.api.nvim_set_current_win(curwin)
    vim.api.nvim_win_close(splitwin, true)
    FzfLua.utils.send_ctrl_c()
  end)

  it("serialize/deserialize with shared function reference", function()
    local func = function() return "test" end
    local obj = { fn1 = func, fn2 = func }
    local serialized = libuv.serialize(obj, false)
    local deserialized = libuv.deserialize(serialized, false)
    eq(type(deserialized.fn1), "function")
    eq(type(deserialized.fn2), "function")
    -- also verify both return the same value as original
    eq(deserialized.fn1, deserialized.fn2)
    eq(deserialized.fn1(), "test")
    eq(deserialized.fn2(), "test")
  end)

  it("win_console_stdio (posix)", function()
    helpers.SKIP_IF_WIN()
    eq(nil, libuv.win_console_stdio())
  end)

  --- Spawn a headless nvim that reports the handle type of its stderr and
  --- return that string ("tty" when the child sees a real console).
  ---@param stdio integer[]
  local function probe_stderr_handle(stdio)
    local file = vim.fn.tempname()
    local probe = vim.fn.tempname() .. ".lua"
    vim.fn.writefile({
      ("vim.fn.writefile({ tostring(vim.uv.guess_handle(2)) }, %s)")
          :format(vim.inspect(file)),
    }, probe)
    local done = false
    libuv.uv_spawn(vim.v.progpath, {
      args = { "--headless", "--clean", "-l", probe },
      stdio = stdio,
    }, function() done = true end)
    eq(true, vim.wait(10000, function() return done end))
    local got = vim.fn.readfile(file)[1]
    vim.fn.delete(file)
    vim.fn.delete(probe)
    return got
  end

  it("win_console_stdio reopens the console (win)", function()
    helpers.SKIP_IF_NOT_WIN()
    local fds = libuv.win_console_stdio()
    if fds == nil then
      -- no console attached (e.g. CI): nil is the documented result and a
      -- spawned probe child can't see a console either, nothing to assert
      return MiniTest.skip("no console attached")
    end
    eq({ "table", "number", "number", "number" },
      { type(fds), type(fds[1]), type(fds[2]), type(fds[3]) })
    eq(fds[2], fds[3])
    -- a child spawned with these fds must see a console on stderr
    eq("tty", probe_stderr_handle(fds))
  end)

  it("win_stderr_fd (posix)", function()
    helpers.SKIP_IF_WIN()
    eq(2, libuv.win_stderr_fd())
  end)

  it("win_stderr_fd gives a spawned child a console stderr (win)", function()
    helpers.SKIP_IF_NOT_WIN()
    local fd = libuv.win_stderr_fd()
    eq("number", type(fd))
    -- with a console available the child must see one; otherwise the only
    -- possible correct result is the fallback to the inherited fd 2
    if libuv.win_console_stdio() then
      eq("tty", probe_stderr_handle({ 0, 1, fd }))
    else
      eq(2, fd)
    end
  end)

  --- Read the handle flags of stdio `fd`; nil when it has no valid handle.
  --- Reuses the declarations made by `libuv.win_stdio_no_inherit`:
  --- `require("ffi")` returns the same cached FFI table (sharing the CType
  --- state), while `package.preload.ffi()` would re-initialize it and drop
  --- the declarations (see `win_ffi_init` in libuv.lua).
  ---@param fd integer
  ---@return integer? flags
  local function stdio_handle_flags(fd)
    local ffi = require("ffi")
    -- STD_INPUT_HANDLE/STD_OUTPUT_HANDLE/STD_ERROR_HANDLE
    local STD_HANDLES = { 0xFFFFFFF6, 0xFFFFFFF5, 0xFFFFFFF4 }
    local k32 = ffi.load("kernel32")
    local flags = ffi.new("unsigned long[1]")
    if k32.GetHandleInformation(k32.GetStdHandle(STD_HANDLES[fd + 1]), flags) == 0 then
      return
    end
    ---@diagnostic disable-next-line: undefined-field
    return flags[0]
  end

  it("win_stdio_no_inherit (posix)", function()
    helpers.SKIP_IF_WIN()
    eq(nil, libuv.win_stdio_no_inherit({ 3, 4, 4 }))
  end)

  it("win_stdio_no_inherit clears and restores the flag (win)", function()
    helpers.SKIP_IF_NOT_WIN()
    if not package.preload.ffi then return MiniTest.skip("no ffi") end
    -- no-op call to trigger the module's one-time FFI declarations
    eq(nil, libuv.win_stdio_no_inherit({ 0, 1, 2 }))
    local before = stdio_handle_flags(1)
    if not before then return MiniTest.skip("no valid stdio handle") end
    -- fds 0-2 are not part of the child's stdio: their inherit flag must be
    -- cleared for the spawn and restored afterwards (libuv <= 1.52 leaks
    -- every inheritable handle to the child regardless of `stdio`)
    local restore = libuv.win_stdio_no_inherit({ 3, 4, 4 })
    eq("function", type(restore))
    ---@cast restore fun()
    local hidden = stdio_handle_flags(1)
    ---@cast hidden integer
    eq(0, hidden % 2)
    restore()
    eq(before, stdio_handle_flags(1))
    -- all stdio fds in use: nothing to hide
    eq(nil, libuv.win_stdio_no_inherit({ 0, 1, 2 }))
  end)
end)
