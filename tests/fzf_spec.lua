local helpers = require("fzf-lua.test.helpers")
local assert = helpers.assert

local libuv = require("fzf-lua.libuv")
local utils = require("fzf-lua.utils")
local eq = assert.are.equal
local same = assert.are.same

local _orig_is_windows = utils.__IS_WINDOWS

describe("Testing fzf launcher", function()
  after_each(function()
    utils.__IS_WINDOWS = _orig_is_windows
    _G.fzf_jobstart = nil
  end)

  ---@param fzf_cli_args string[]
  ---@param opts table
  ---@param bom_content string?
  ---@return table captured
  ---@return table? output
  ---@return integer? rc
  local function mock_run(fzf_cli_args, opts, bom_content)
    local captured = {}
    local output, rc
    local old_jobstart = _G.fzf_jobstart
    _G.fzf_jobstart = function(shell_cmd, job_opts)
      captured.shell_cmd = shell_cmd
      captured.env = job_opts.env
      if bom_content and shell_cmd[1] == "powershell.exe" then
        -- outputtmpname is ps_escaped inside the single fused -Command string
        local qpath = shell_cmd[5]:match("%-RedirectStandardOutput%s+('[^']+')")
        if qpath then
          local path = qpath:sub(2, -2):gsub("''", "'")
          local f = io.open(path, "w")
          if f then
            f:write(bom_content)
            f:close()
          end
        end
      end
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

  it("uses cmd.exe below threshold on Windows", function()
    utils.__IS_WINDOWS = true
    local fzf_cli_args = { "--bind=" .. libuv.shellescape("ctrl-t:execute(echo hi)") }
    local captured = mock_run(fzf_cli_args, {})
    eq(captured.shell_cmd[1], "cmd.exe")
    eq(captured.env.SHELL, "cmd.exe")
  end)

  it("uses powershell.exe above 8000 chars on Windows", function()
    utils.__IS_WINDOWS = true
    local val = string.rep("a", 8100)
    local raw_bind = "ctrl-t:" .. val
    local fzf_cli_args = { "--bind=" .. libuv.shellescape(raw_bind) }
    local segments = {
      { { text = "--bind=", escape = false }, { text = raw_bind, escape = true } },
    }
    local captured = mock_run(fzf_cli_args, { _cli_segments = segments })
    eq(captured.shell_cmd[1], "powershell.exe")
    eq(captured.shell_cmd[2], "-NoProfile")
    eq(captured.shell_cmd[3], "-NonInteractive")
    eq(captured.shell_cmd[4], "-Command")
    eq(captured.env.SHELL, "cmd.exe")
    local fused = captured.shell_cmd[5]
    assert.is.True(fused:find("Start%-Process") ~= nil)
    assert.is.True(fused:find("%-FilePath%s+'fzf'") ~= nil)
    assert.is.True(fused:find("%-ArgumentList%s+'.-'") ~= nil)
    assert.is.True(fused:find("%-RedirectStandardOutput%s+'.-'") ~= nil)
    assert.is.True(fused:find("exit $proc%.ExitCode$") ~= nil)
    -- The argument line uses CommandLineToArgvW-style double-quote quoting.
    local expected = libuv.shellescape("--bind=" .. raw_bind, 1)
    assert.is.True(fused:find(expected, 1, true) ~= nil)
  end)

  it("empty --query remains a distinct argument for PowerShell", function()
    utils.__IS_WINDOWS = true
    local val = string.rep("a", 8100)
    local raw_bind = "ctrl-t:" .. val
    local fzf_cli_args = {
      "--query", libuv.shellescape(""),
      "--bind=" .. libuv.shellescape(raw_bind),
    }
    local segments = {
      { { text = "--query", escape = false } },
      { { text = "", escape = true } },
      { { text = "--bind=", escape = false }, { text = raw_bind, escape = true } },
    }
    local captured = mock_run(fzf_cli_args, { _cli_segments = segments })
    eq(captured.shell_cmd[1], "powershell.exe")
    local fused = captured.shell_cmd[5]
    local expected = libuv.shellescape("--query", 1) .. " " .. libuv.shellescape("", 1)
    assert.is.True(fused:find("-ArgumentList '" .. expected, 1, true) ~= nil)
  end)

  it("Windows-quotes arguments with embedded quotes and backslashes", function()
    utils.__IS_WINDOWS = true
    local val = string.rep("a", 8100)
    local raw_bind = "ctrl-t:" .. val
    local tricky = [[foo"bar\]]
    local fzf_cli_args = {
      "--query", libuv.shellescape(tricky),
      "--bind=" .. libuv.shellescape(raw_bind),
    }
    local segments = {
      { { text = "--query", escape = false } },
      { { text = tricky, escape = true } },
      { { text = "--bind=", escape = false }, { text = raw_bind, escape = true } },
    }
    local captured = mock_run(fzf_cli_args, { _cli_segments = segments })
    eq(captured.shell_cmd[1], "powershell.exe")
    local fused = captured.shell_cmd[5]
    local expected = libuv.shellescape("--query", 1) .. " " .. libuv.shellescape(tricky, 1)
    assert.is.True(fused:find(expected, 1, true) ~= nil)
  end)

  it("does not wrap fzf-tmux in powershell even when over threshold", function()
    utils.__IS_WINDOWS = true
    local val = string.rep("a", 8100)
    local raw_bind = "ctrl-t:" .. val
    local fzf_cli_args = { "--bind=" .. libuv.shellescape(raw_bind) }
    local segments = {
      { { text = "--bind=", escape = false }, { text = raw_bind, escape = true } },
    }
    local captured = mock_run(fzf_cli_args, { is_fzf_tmux = true, _cli_segments = segments })
    eq(captured.shell_cmd[1], "cmd.exe")
    eq(captured.env.SHELL, "cmd.exe")
  end)

  it("streams pipe_cmd items into fzf above threshold (win)", function()
    utils.__IS_WINDOWS = true
    local val = string.rep("a", 8100)
    local raw_bind = "ctrl-t:" .. val
    local fzf_cli_args = { "--bind=" .. libuv.shellescape(raw_bind) }
    local segments = {
      { { text = "--bind=", escape = false }, { text = raw_bind, escape = true } },
    }
    local captured = mock_run(fzf_cli_args, { pipe_cmd = true, _cli_segments = segments })
    eq(captured.shell_cmd[1], "powershell.exe")
    eq(captured.env.SHELL, "cmd.exe")
    eq(captured.env.FZF_DEFAULT_COMMAND, nil)
    local fused = captured.shell_cmd[5]
    -- both processes start through ProcessStartInfo (verbatim `Arguments`),
    -- no Start-Process and no blocking wait on the item producer
    assert.is.True(fused:find("New%-Object System%.Diagnostics%.ProcessStartInfo") ~= nil)
    assert.is.False(fused:find("Start%-Process") ~= nil)
    -- item command runs through cmd.exe without a redirect; its stdout is
    -- pumped into fzf's stdin so items stream in while fzf is already up
    assert.is.True(fused:find(
      "$ipsi.Arguments = '/d /e:off /f:off /v:off /c (echo foo || break)'", 1, true) ~= nil)
    assert.is.True(fused:find(
      "$iproc.StandardOutput.BaseStream.CopyTo($fproc.StandardInput.BaseStream)", 1, true) ~= nil)
    -- fzf receives the long argument line through the verbatim Arguments string
    assert.is.True(fused:find("$fpsi.Arguments = ", 1, true) ~= nil)
    local expected = libuv.shellescape("--bind=" .. raw_bind, 1)
    assert.is.True(fused:find(expected, 1, true) ~= nil)
    -- fzf's stdout is drained into the output temp file for on_exit
    -- asynchronously (before the pump, so a large selection can't dead-lock
    -- against the still-running item producer) and the fzf exit code is
    -- propagated after both finish
    assert.is.True(fused:find("$drain = $fproc.StandardOutput.BaseStream.CopyToAsync($ofs)", 1, true) ~= nil)
    assert.is.True(fused:find("$drain.Wait(); $ofs.Close()", 1, true) ~= nil)
    assert.is.True(fused:find("exit $code", 1, true) ~= nil)
  end)

  it("uses cmd.exe for pipe_cmd below threshold", function()
    utils.__IS_WINDOWS = true
    local fzf_cli_args = { "--bind=" .. libuv.shellescape("ctrl-t:execute(echo hi)") }
    local captured = mock_run(fzf_cli_args, { pipe_cmd = true })
    eq(captured.shell_cmd[1], "cmd.exe")
    eq(captured.env.FZF_DEFAULT_COMMAND, nil)
    assert.is.True(captured.shell_cmd[7]:find("echo foo", 1, true) ~= nil)
  end)

  it("strips UTF-8 BOM from powershell output", function()
    utils.__IS_WINDOWS = true
    local val = string.rep("a", 8100)
    local raw_bind = "ctrl-t:" .. val
    local fzf_cli_args = { "--bind=" .. libuv.shellescape(raw_bind) }
    local segments = {
      { { text = "--bind=", escape = false }, { text = raw_bind, escape = true } },
    }
    local captured, output = mock_run(fzf_cli_args, { _cli_segments = segments },
      "\239\187\191line1\nline2\n")
    eq(captured.shell_cmd[1], "powershell.exe")
    same(output, { "line1", "line2" })
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
