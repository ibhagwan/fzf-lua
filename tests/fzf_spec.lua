local helpers = require("fzf-lua.test.helpers")
local assert = helpers.assert

local libuv = require("fzf-lua.libuv")
local utils = require("fzf-lua.utils")
local eq = assert.are.equal
local same = assert.are.same

local _orig_is_windows = utils.__IS_WINDOWS
local _orig_termopen = utils.termopen

describe("Testing fzf launcher", function()
  after_each(function()
    utils.__IS_WINDOWS = _orig_is_windows
    utils.termopen = _orig_termopen
    _G.fzf_jobstart = nil
  end)

  ---@param fzf_cli_args string[]
  ---@param opts table
  ---@return table captured
  ---@return table? output
  ---@return integer? rc
  local function mock_run(fzf_cli_args, opts)
    local captured = {}
    local output, rc
    local old_jobstart = _G.fzf_jobstart
    _G.fzf_jobstart = function(shell_cmd, job_opts)
      captured.shell_cmd = shell_cmd
      captured.env = job_opts.env
      -- Real jobstart calls on_exit asynchronously; mimic that so the
      -- coroutine is suspended before it is resumed.
      vim.schedule(function() job_opts.on_exit({}, 1, {}) end)
    end
    vim.cmd("botright new")
    local ok, err = pcall(function()
      coroutine.wrap(function()
        local fzf = require("fzf-lua.fzf")
        output, rc = fzf.raw_fzf("echo foo", fzf_cli_args, opts)
      end)()
      vim.wait(2000, function() return rc ~= nil end)
    end)
    _G.fzf_jobstart = old_jobstart
    vim.api.nvim_win_close(0, true)
    if not ok then error(err) end
    return captured, output, rc
  end

  --- Same as `mock_run` but for the TUI route (no `_G.fzf_jobstart`, the
  --- `termopen` mediator is intercepted instead of being executed)
  ---@return table captured
  ---@return table? output
  ---@return integer? rc
  local function mock_run_tui(fzf_cli_args, opts)
    local captured = {}
    local output, rc
    local ok, err = pcall(function()
      utils.termopen = function(shell_cmd, job_opts)
        captured.shell_cmd = shell_cmd
        captured.env = job_opts.env
        vim.schedule(function() job_opts.on_exit({}, 1, {}) end)
        return 1
      end
      coroutine.wrap(function()
        local fzf = require("fzf-lua.fzf")
        output, rc = fzf.raw_fzf("echo foo", fzf_cli_args, opts)
      end)()
      vim.wait(2000, function() return rc ~= nil end)
    end)
    if not ok then error(err) end
    return captured, output, rc
  end

  it("uses the legacy cmd.exe launcher without raw segments", function()
    utils.__IS_WINDOWS = true
    local fzf_cli_args = { "--bind=" .. libuv.shellescape("ctrl-t:execute(echo hi)") }
    local captured = mock_run(fzf_cli_args, {})
    eq(captured.shell_cmd[1], "cmd.exe")
    eq(captured.env.SHELL, "cmd.exe")
    eq(captured.env.FZF_DEFAULT_COMMAND, "echo foo || break")
  end)

  it("builds a win_spawn spec with raw argv (no shell escaping)", function()
    utils.__IS_WINDOWS = true
    local raw_bind = [[ctrl-t:execute(echo "hi" && echo bye)]]
    local fzf_cli_args = { "--bind=" .. libuv.shellescape(raw_bind) }
    local segments = {
      { { text = "--bind=", escape = false }, { text = raw_bind, escape = true } },
    }
    local captured = mock_run(fzf_cli_args,
      { _cli_segments = segments, cwd = "C:/some/dir" })
    -- no shell command line, just the direct spawn spec
    eq(captured.shell_cmd[1], nil)
    local spec = captured.shell_cmd.__win_spawn
    eq(spec.bin, "fzf")
    -- raw unescaped argument, uv quoting handles the rest
    eq(spec.args[1], "--bind=" .. raw_bind)
    eq(spec.cwd, "C:/some/dir")
    eq(spec.item, nil)
    eq(type(spec.outfile), "string")
    assert.is.True(#spec.outfile > 0)
    eq(captured.env.SHELL, "cmd.exe")
    eq(captured.env.FZF_DEFAULT_COMMAND, "echo foo || break")
  end)

  it("has no cmd.exe/PowerShell length limit for long arguments", function()
    utils.__IS_WINDOWS = true
    local raw_bind = "ctrl-t:" .. string.rep("a", 8100)
    local fzf_cli_args = { "--bind=" .. libuv.shellescape(raw_bind) }
    local segments = {
      { { text = "--bind=", escape = false }, { text = raw_bind, escape = true } },
    }
    local captured = mock_run(fzf_cli_args, { _cli_segments = segments })
    local spec = captured.shell_cmd.__win_spawn
    same(spec.args, { "--bind=" .. raw_bind })
  end)

  it("keeps empty arguments as distinct raw argv entries", function()
    utils.__IS_WINDOWS = true
    local segments = {
      { { text = "--query", escape = false } },
      { { text = "", escape = true } },
    }
    local captured = mock_run({ "--query", libuv.shellescape("") },
      { _cli_segments = segments })
    local spec = captured.shell_cmd.__win_spawn
    same(spec.args, { "--query", "" })
  end)

  it("keeps embedded quotes and backslashes raw in the spec argv", function()
    utils.__IS_WINDOWS = true
    local tricky = [[foo"bar\]]
    local segments = {
      { { text = "--query", escape = false } },
      { { text = tricky, escape = true } },
    }
    local captured = mock_run({ "--query", libuv.shellescape(tricky) },
      { _cli_segments = segments })
    local spec = captured.shell_cmd.__win_spawn
    same(spec.args, { "--query", tricky })
  end)

  it("streams pipe_cmd items through the spec item command", function()
    utils.__IS_WINDOWS = true
    local segments = {
      { { text = "--bind=", escape = false }, { text = "ctrl-t:execute(echo hi)", escape = true } },
    }
    local captured = mock_run({ "--bind=" .. libuv.shellescape("ctrl-t:execute(echo hi)") },
      { pipe_cmd = true, _cli_segments = segments })
    local spec = captured.shell_cmd.__win_spawn
    eq(spec.item, "echo foo || break")
    eq(spec.args[1], "--bind=ctrl-t:execute(echo hi)")
    -- the item command is no longer exported via the environment
    eq(captured.env.FZF_DEFAULT_COMMAND, nil)
    eq(captured.env.SHELL, "cmd.exe")
  end)

  it("wires the TUI route through the win_spawn.lua mediator", function()
    utils.__IS_WINDOWS = true
    local raw_bind = "ctrl-t:execute(echo hi)"
    local segments = {
      { { text = "--bind=", escape = false }, { text = raw_bind, escape = true } },
    }
    local captured = mock_run_tui({ "--bind=" .. libuv.shellescape(raw_bind) },
      { _cli_segments = segments })
    local shell_cmd = captured.shell_cmd
    ---@cast shell_cmd string[]
    eq(shell_cmd[1], os.getenv("FZF_LUA_NVIM_BIN") or vim.v.progpath)
    eq(shell_cmd[2], "-u")
    eq(shell_cmd[3], "NONE")
    eq(shell_cmd[4], "-l")
    local prog = shell_cmd[5] or error("missing win_spawn.lua argument")
    assert.is.True(prog:find("win_spawn%.lua") ~= nil)
    -- the spec file exists and round-trips the spawn spec
    local spec_path = shell_cmd[6] or error("missing spec path argument")
    eq(vim.fn.filereadable(spec_path), 1)
    local f = io.open(spec_path, "r")
    if not f then error("cannot open " .. spec_path) end
    local payload = f:read("*a")
    f:close()
    local spec = libuv.deserialize(payload)
    eq(spec.bin, "fzf")
    same(spec.args, { "--bind=" .. raw_bind })
    eq(spec.env.SHELL, "cmd.exe")
    vim.fn.delete(spec_path)
  end)

  it("keeps fzf-tmux on the shell route", function()
    utils.__IS_WINDOWS = true
    local fzf_cli_args = { "--bind=" .. libuv.shellescape("ctrl-t:execute(echo hi)") }
    local segments = {
      { { text = "--bind=", escape = false }, { text = "ctrl-t:execute(echo hi)", escape = true } },
    }
    local captured = mock_run(fzf_cli_args, { is_fzf_tmux = true, _cli_segments = segments })
    eq(captured.shell_cmd[1], "cmd.exe")
    eq(captured.env.SHELL, "cmd.exe")
    -- result file redirect via the legacy shell route
    assert.is.True(table.concat(captured.shell_cmd, " "):find(">", 1, true) ~= nil)
  end)

  it("uses the legacy cmd.exe pipe for pipe_cmd without raw segments", function()
    utils.__IS_WINDOWS = true
    local captured = mock_run({}, { pipe_cmd = true })
    eq(captured.shell_cmd[1], "cmd.exe")
    eq(captured.env.FZF_DEFAULT_COMMAND, nil)
    assert.is.True(captured.shell_cmd[7]
      :find("(echo foo || break) | ", 1, true) ~= nil)
  end)

  it("does not emit --with-shell for skim", function()
    utils.__IS_WINDOWS = true
    local fzf_cli_args = { "--bind=" .. libuv.shellescape("ctrl-t:execute(echo hi)") }
    local captured = mock_run(fzf_cli_args, { fzf_bin = "sk" })
    local cmd_str = table.concat(captured.shell_cmd, " ")
    assert.is.False(cmd_str:find("--with%-shell", 1, true) ~= nil)
  end)

  it("keeps Unix sh -c path byte-identical", function()
    helpers.SKIP_IF_WIN()
    local val = string.rep("a", 8100)
    local raw_bind = "ctrl-t:" .. val
    local fzf_cli_args = { "--bind=" .. libuv.shellescape(raw_bind) }
    local segments = {
      { { text = "--bind=", escape = false }, { text = raw_bind, escape = true } },
    }
    local captured = mock_run(fzf_cli_args, { _cli_segments = segments })
    eq(captured.shell_cmd[1], "sh")
    eq(captured.env.SHELL, "sh")
    assert.is.True(captured.shell_cmd[3]:find("^fzf .* > ") ~= nil)
  end)
end)
