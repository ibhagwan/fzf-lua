local helpers = require("fzf-lua.test.helpers")
local assert = helpers.assert

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

  it("ps_escape", function()
    -- PowerShell single-quoted strings: everything literal except '' (escaped ')
    eq(libuv.ps_escape([[plain]]), [['plain']])
    eq(libuv.ps_escape([[it's]]), [['it''s']])
    eq(libuv.ps_escape([['quoted']]), [['''quoted''']])
    -- metacharacters ($, backtick, ", (), &, |) stay literal inside single quotes
    eq(libuv.ps_escape([[$(x) `" & | ; ( )]]), [['$(x) `" & | ; ( )']])
    eq(libuv.ps_escape([[]]), [['']])
    eq(libuv.ps_escape([[a b]]), [['a b']])
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
    -- powershell: value segments via ps_escape
    local ps = libuv.escape_cli(elems, "powershell")
    eq(ps[1], "--bind='ctrl-r:reload(a b)'")
    eq(ps[2], "--query")
    eq(ps[3], "'it''s'")
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
  ---@param stdio { integer, integer, integer }
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
end)
