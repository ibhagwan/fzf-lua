local shell = require("fzf-lua.shell")
-- local MiniTest = require("mini.test")
local ok = function(f, ...) assert(pcall(f, ...)) end
local err = function(f, ...)
  local _ok, _err = pcall(f, ...)
  assert(not _ok, _err)
end

-- Drives the function registered by `stringify_data2` (the RPC receiving
-- function) synchronously, as if fzf sent `lines` via the action pipe:
-- stubs `uv.pipe_connect` to succeed immediately and `vim.schedule` to
-- run inline. `cmd` is the stringified shell command, from which the
-- registered function id is parsed as the argument following `rpc.lua`.
-- NOTE: the rpc.lua path is shellescaped differently per platform
-- ('...' on Unix, "^"...^"" or "..." on Windows), so we match any
-- non-digit run after `rpc.lua` up to the id rather than a hard quote.
local function simulate_fzf_output(cmd, lines)
  local id = tonumber(assert(cmd:match("rpc%.lua%D-(%d+)")))
  local uv = vim.uv
  local orig_pipe_connect, orig_schedule = uv.pipe_connect, vim.schedule
  ---@diagnostic disable: duplicate-set-field
  ---@param cb? fun(err: string?)
  uv.pipe_connect = function(_, _, cb) if cb then cb(nil) end end
  vim.schedule = function(f) f() end
  ---@diagnostic enable: duplicate-set-field
  local ok_, err_ = pcall(shell.get_func(id), {
    pipe_path = "",
    selection = lines,
    env = {},
  })
  uv.pipe_connect, vim.schedule = orig_pipe_connect, orig_schedule
  assert(ok_, err_)
end

describe("Testing shell module", function()
  it("stringify_data2 appends '{n} {q}' and extracts idx, query in that order", function()
    local opts = { __resume_key = "shell_spec" }
    ---@type string[]
    local captured
    local cmd = shell.stringify_data2(function(items, _)
      captured = vim.deepcopy(items)
      return ""
    end, opts, "{+}")
    -- "{n} {q}" (not "{q} {n}") is appended to the field index
    assert(cmd:match("{%+} {n} {q}"), cmd)
    -- simulate fzf output: last two lines are "{n}" (idx) then "{q}" (query)
    simulate_fzf_output(cmd, { "entry", "3", "query" })
    -- trailing "{n} {q}" lines are stripped from the items
    assert(#captured == 1 and captured[1] == "entry")
    -- resume query is set from the last line ("{q}")
    assert(FzfLua.config.resume_get("query", opts) == "query")
    assert(opts.last_query == "query")
  end)

  it("stringify_data2 '{n} {q}' order keeps zero-match/zero-selected detection", function()
    local opts = { __resume_key = "shell_spec" }
    ---@type string[]
    local captured
    local cmd = shell.stringify_data2(function(items, _)
      captured = vim.deepcopy(items)
      return ""
    end, opts, "{+}")
    -- no match + no selection: both {n} and {+} expand to "", items
    -- arriving as { "", "", "<query>" } must be converted to {}
    simulate_fzf_output(cmd, { "", "", "query" })
    assert(#captured == 0)
  end)

  it("check_upvalue", function()
    ok(shell.check_upvalue, function() end, "no upvalue")

    ---@diagnostic disable: need-check-nil
    err(shell.check_upvalue, (function()
      local upvalue
      ---@diagnostic disable-next-line: undefined-field
      return function() return upvalue.index end
    end)(), "index upvalue")

    err(shell.check_upvalue, (function()
      local upvalue
      return function() return upvalue() end
    end)(), "call upvalue")
    ---@diagnostic enable: need-check-nil
  end)
end)
