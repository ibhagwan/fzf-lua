local helpers = require("fzf-lua.test.helpers")
local assert = helpers.assert

local libuv = require("fzf-lua.libuv")
local eq = assert.are.equal

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
    assert.are.same(libuv.shellescape([[]], 1), [[""]])
    assert.are.same(libuv.shellescape([[^]], 1), [["^"]])
    assert.are.same(libuv.shellescape([[""]], 1), [["\"\""]])
    assert.are.same(libuv.shellescape([["^"]], 1), [["\"^\""]])
    assert.are.same(libuv.shellescape([[foo]], 1), [["foo"]])
    assert.are.same(libuv.shellescape([["foo"]], 1), [["\"foo\""]])
    assert.are.same(libuv.shellescape([["foo"bar"]], 1), [["\"foo\"bar\""]])
    assert.are.same(libuv.shellescape([[foo"bar]], 1), [["foo\"bar"]])
    assert.are.same(libuv.shellescape([[foo""bar]], 1), [["foo\"\"bar"]])
    assert.are.same(libuv.shellescape([["foo\"bar"]], 1), [["\"foo\\\"bar\""]])
    assert.are.same(libuv.shellescape([[foo\]], 1), [["foo\\"]])
    assert.are.same(libuv.shellescape([[foo\\]], 1), [["foo\\\\"]])
    assert.are.same(libuv.shellescape([[foo\^]], 1), [["foo\^"]])
    assert.are.same(libuv.shellescape([[foo\\\\]], 1), [["foo\\\\\\\\"]])
    assert.are.same(libuv.shellescape([[foo\"]], 1), [["foo\\\""]])
    assert.are.same(libuv.shellescape([["foo\"]], 1), [["\"foo\\\""]])
    assert.are.same(libuv.shellescape([["foo\""]], 1), [["\"foo\\\"\""]])
    assert.are.same(libuv.shellescape([[foo\bar]], 1), [["foo\bar"]])
    assert.are.same(libuv.shellescape([[foo\\bar]], 1), [["foo\\bar"]])
    assert.are.same(libuv.shellescape([[foo\\"bar]], 1), [["foo\\\\\"bar"]])
    assert.are.same(libuv.shellescape([[foo\\\"bar]], 1), [["foo\\\\\\\"bar"]])
  end)

  it("shellescape (win caret)", function()
    assert.are.same(libuv.shellescape([[]], 2), [[^"^"]])
    assert.are.same(libuv.shellescape([["]], 2), [[^"\^"^"]])
    assert.are.same(libuv.shellescape([[^"]], 2), [[^"^^\^"^"]])
    assert.are.same(libuv.shellescape([[\"]], 2), [[^"\\\^"^"]])
    assert.are.same(libuv.shellescape([[\^"]], 2), [[^"^^\\\^"^"]])
    assert.are.same(libuv.shellescape([[^"^"]], 2), [[^"^^\^"^^\^"^"]])
    assert.are.same(libuv.shellescape([[__^^"^"__]], 2), [[^"__^^^^\^"^^\^"__^"]])
    assert.are.same(libuv.shellescape([[__!^^"^"__]], 2),
      -- 1st: ^"_^!^^^^\^"^^\^"_^"
      -- 2nd: ^"_^^^!^^^^^^^^^^\\\^"^^^^^^\\\^"_^"
      [[^"__^^^!^^^^^^^^^^\\\^"^^^^^^\\\^"__^"]])
    assert.are.same(libuv.shellescape([[__^^^^\^"^^\^"__]], 2),
      [[^"__^^^^^^^^^^\\\^"^^^^^^\\\^"__^"]])
    assert.are.same(libuv.shellescape([[^]], 2), [[^"^^^"]])
    assert.are.same(libuv.shellescape([[^^]], 2), [[^"^^^^^"]])
    assert.are.same(libuv.shellescape([[^^^]], 2), [[^"^^^^^^^"]])
    assert.are.same(libuv.shellescape([[^!^]], 2), [[^"^^^^^^^!^^^^^"]])
    assert.are.same(libuv.shellescape([[!^"]], 2),
      -- 1st inner: ^!^^\^"
      -- 2nd inner: ^^^!^^^^^^\\\^"
      [[^"^^^!^^^^^^\\\^"^"]])
    assert.are.same(libuv.shellescape([[!\"]], 2), [[^"^^^!^^\\\\\\\^"^"]])
    assert.are.same(libuv.shellescape([[!\^"]], 2), [[^"^^^!^^^^^^\\\\\\\^"^"]])
    assert.are.same(libuv.shellescape([[()%^"<>&|;]], 2), [[^"^(^)^%^^\^"^<^>^&^|^;^"]])
    assert.are.same(libuv.shellescape([[()%^"<>&|;!]], 2),
      -- 1st inner: ^(^)^%^^\^"^<^>^&^|^!
      -- 2nd inner: ^^^(^^^)^^^%^^^^^^\^"^^^<^^^>^^^&^^^|^^^!
      [[^"^^^(^^^)^^^%^^^^^^\\\^"^^^<^^^>^^^&^^^|^^^;^^^!^"]])
    assert.are.same(libuv.shellescape([[foo]], 2), [[^"foo^"]])
    assert.are.same(libuv.shellescape([[foo\]], 2), [[^"foo\\^"]])
    assert.are.same(libuv.shellescape([[foo^]], 2), [[^"foo^^^"]])
    assert.are.same(libuv.shellescape([[foo\\]], 2), [[^"foo\\\\^"]])
    assert.are.same(libuv.shellescape([[foo\\\]], 2), [[^"foo\\\\\\^"]])
    assert.are.same(libuv.shellescape([[foo\\\\]], 2), [[^"foo\\\\\\\\^"]])
    assert.are.same(libuv.shellescape([[f!oo]], 2), [[^"f^^^!oo^"]])
    assert.are.same(libuv.shellescape([[^"foo^"]], 2), [[^"^^\^"foo^^\^"^"]])
    assert.are.same(libuv.shellescape([[\^"foo\^"]], 2), [[^"^^\\\^"foo^^\\\^"^"]])
    assert.are.same(libuv.shellescape([[foo""bar]], 2), [[^"foo\^"\^"bar^"]])
    assert.are.same(libuv.shellescape([[foo^"^"bar]], 2), [[^"foo^^\^"^^\^"bar^"]])
    assert.are.same(libuv.shellescape([["foo\"bar"]], 2), [[^"\^"foo\\\^"bar\^"^"]])
    assert.are.same(libuv.shellescape([[foo\^"]], 2), [[^"foo^^\\\^"^"]])
    assert.are.same(libuv.shellescape([[foo\"]], 2), [[^"foo\\\^"^"]])
    assert.are.same(libuv.shellescape([[^"foo\^"^"]], 2), [[^"^^\^"foo^^\\\^"^^\^"^"]])
    assert.are.same(libuv.shellescape([[foo\"bar]], 2), [[^"foo\\\^"bar^"]])
    assert.are.same(libuv.shellescape([[foo\\"bar]], 2), [[^"foo\\\\\^"bar^"]])
    assert.are.same(libuv.shellescape([[foo\\^^"bar]], 2), [[^"foo\\^^^^\^"bar^"]])
    assert.are.same(libuv.shellescape([[foo\\\^^^"]], 2), [[^"foo\\\^^^^^^\^"^"]])
  end)

  it("escape {q} (win, fzf v0.50)", function()
    assert.are.same(libuv.escape_fzf([[]], 0.50, true), [[]])
    assert.are.same(libuv.escape_fzf([[\]], 0.50, true), [[\]])
    assert.are.same(libuv.escape_fzf([[\\]], 0.50, true), [[\\]])
    assert.are.same(libuv.escape_fzf([[foo]], 0.50, true), [[foo]])
    assert.are.same(libuv.escape_fzf([[\foo]], 0.50, true), [[\\foo]])
    assert.are.same(libuv.escape_fzf([[\\foo]], 0.50, true), [[\\\\foo]])
    assert.are.same(libuv.escape_fzf([[\\\foo]], 0.50, true), [[\\\\\\foo]])
    assert.are.same(libuv.escape_fzf([[\\\\foo]], 0.50, true), [[\\\\\\\\foo]])
    assert.are.same(libuv.escape_fzf([[foo\]], 0.50, true), [[foo\]])
    assert.are.same(libuv.escape_fzf([[foo\\]], 0.50, true), [[foo\\]])
  end)

  it("unescape {q} (win, fzf v0.50)", function()
    assert.are.same(libuv.unescape_fzf([[]], 0.50, true), [[]])
    assert.are.same(libuv.unescape_fzf([[\]], 0.50, true), [[\]])
    assert.are.same(libuv.unescape_fzf([[\\]], 0.50, true), [[\\]])
    assert.are.same(libuv.unescape_fzf([[foo]], 0.50, true), [[foo]])
    assert.are.same(libuv.unescape_fzf([[\foo]], 0.50, true), [[\foo]])
    assert.are.same(libuv.unescape_fzf([[\\foo]], 0.50, true), [[\foo]])
    assert.are.same(libuv.unescape_fzf([[\\\foo]], 0.50, true), [[\foo]])
    assert.are.same(libuv.unescape_fzf([[\\\\foo]], 0.50, true), [[\\foo]])
    assert.are.same(libuv.unescape_fzf([[foo\]], 0.50, true), [[foo\]])
    assert.are.same(libuv.unescape_fzf([[foo\\]], 0.50, true), [[foo\\]])
  end)

  it("escape {q} (win, fzf v0.52)", function()
    assert.are.same(libuv.escape_fzf([[]], 0.52, true), [[]])
    assert.are.same(libuv.escape_fzf([[\]], 0.52, true), [[\]])
    assert.are.same(libuv.escape_fzf([[\\]], 0.52, true), [[\\]])
    assert.are.same(libuv.escape_fzf([[foo]], 0.52, true), [[foo]])
    assert.are.same(libuv.escape_fzf([[\foo]], 0.52, true), [[\foo]])
    assert.are.same(libuv.escape_fzf([[\\foo]], 0.52, true), [[\\foo]])
    assert.are.same(libuv.escape_fzf([[\\\foo]], 0.52, true), [[\\\foo]])
    assert.are.same(libuv.escape_fzf([[\\\\foo]], 0.52, true), [[\\\\foo]])
    assert.are.same(libuv.escape_fzf([[foo\]], 0.52, true), [[foo\]])
    assert.are.same(libuv.escape_fzf([[foo\\]], 0.52, true), [[foo\\]])
  end)

  it("unescape {q} (win, fzf v0.52)", function()
    assert.are.same(libuv.unescape_fzf([[]], 0.52, true), [[]])
    assert.are.same(libuv.unescape_fzf([[\]], 0.52, true), [[\]])
    assert.are.same(libuv.unescape_fzf([[\\]], 0.52, true), [[\\]])
    assert.are.same(libuv.unescape_fzf([[foo]], 0.52, true), [[foo]])
    assert.are.same(libuv.unescape_fzf([[\foo]], 0.52, true), [[\foo]])
    assert.are.same(libuv.unescape_fzf([[\\foo]], 0.52, true), [[\\foo]])
    assert.are.same(libuv.unescape_fzf([[\\\foo]], 0.52, true), [[\\\foo]])
    assert.are.same(libuv.unescape_fzf([[\\\\foo]], 0.52, true), [[\\\\foo]])
    assert.are.same(libuv.unescape_fzf([[foo\]], 0.52, true), [[foo\]])
    assert.are.same(libuv.unescape_fzf([[foo\\]], 0.52, true), [[foo\\]])
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
    local job = chans[#chans].id
    eq({ 0 }, vim.fn.jobwait({ job }))
    eq(0, exit_code)
    assert.are.equal(selected, {
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
end)
