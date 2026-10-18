local helpers = require("fzf-lua.test.helpers")
local assert = helpers.assert

---@diagnostic disable-next-line: deprecated
local uv = vim.uv or vim.loop
local libuv = require("fzf-lua.libuv")
local utils = require("fzf-lua.utils")
local eq = assert.are.equal

local fzf_bin = vim.fn.exepath("fzf")

---@param path string
---@param content string
local function write_file(path, content)
  local f = io.open(path, "w")
  if not f then error("cannot open " .. path .. " for writing") end
  f:write(content)
  f:close()
end

---@param path string
---@return string
local function read_file(path)
  local f = io.open(path, "r")
  if not f then return "" end
  local content = f:read("*a") or ""
  f:close()
  return content
end

--- `cmd.exe` builtins (eg. `type`) reject '/'-separated paths; nightly neovim
--- returns forward-slash `vim.fn.tempname()` values on Windows, so convert to
--- native separators before embedding paths into cmd-syntax producer items
---@param p string
---@return string
local function cmd_path(p)
  return (p:gsub("/", "\\"))
end

describe("Testing win_spawn (Windows one route)", function()
  --- Run one full `libuv.win_spawn` cycle (item producer -> pump -> result
  --- file) and return fzf's exit code and the result file contents
  ---@param item string producer command (cmd syntax)
  ---@param args string[] raw fzf argv (without the executable)
  ---@return integer? rc
  ---@return string out
  local function win_run(item, args)
    local outfile = utils.tempname()
    local rc ---@type integer?
    local ok, err = pcall(libuv.win_spawn, {
      bin = fzf_bin,
      args = args,
      item = item,
      outfile = outfile,
      env = { SHELL = "cmd.exe" },
    }, { on_exit = function(code) rc = code end })
    if not ok then error(err) end
    vim.wait(30000, function() return rc ~= nil end)
    local out = read_file(outfile)
    vim.fn.delete(outfile)
    return rc, out
  end

  it("pump preserves bytes: argv quoting, streaming and result file", function()
    helpers.SKIP_IF_NOT_WIN()
    local infile = utils.tempname()
    local lines = { "ab c", [[E"f G]], [[H\I]], "汉 é" }
    write_file(infile, table.concat(lines, "\n") .. "\n")
    local item = string.format('type "%s"', cmd_path(infile))
    -- filter arguments with a space (single argv token), quotes, a trailing
    -- backslash and multi-byte characters survive the uv quoting + pump
    for _, case in ipairs({
      { filter = "ab c",  match = "ab c" },
      { filter = [[E"f G]], match = [[E"f G]] },
      { filter = [[H\I]], match = [[H\I]] },
      { filter = "汉 é", match = "汉 é" },
    }) do
      local rc, out = win_run(item, { "--filter=" .. case.filter })
      eq(rc, 0)
      eq(out, case.match .. "\n")
    end
    -- empty filter: match everything, the full stream is byte-identical
    local rc, out = win_run(item, { "--filter=", "--no-sort" })
    eq(rc, 0)
    eq(out, table.concat(lines, "\n") .. "\n")
    vim.fn.delete(infile)
  end)

  it("propagates fzf's exit code when nothing matches", function()
    helpers.SKIP_IF_NOT_WIN()
    local rc, out = win_run("echo abc", { "--filter=zzz" })
    eq(rc, 1)
    eq(out, "")
  end)

  it("streams a large input (backpressure) and matches the last line", function()
    helpers.SKIP_IF_NOT_WIN()
    local infile = utils.tempname()
    local f = io.open(infile, "w")
    if not f then error("cannot open " .. infile .. " for writing") end
    local buf = {}
    for i = 0, 399999 do
      buf[#buf + 1] = ("line %06d\n"):format(i)
      if #buf >= 4096 then
        f:write(table.concat(buf))
        buf = {}
      end
    end
    f:write(table.concat(buf))
    f:close()
    -- ~4.8MB (> the 4MB high watermark): exercises the pump across many
    -- chunks with the producer paused by the write queue backpressure
    local rc, out = win_run(string.format('type "%s"', cmd_path(infile)),
      { "--filter=line 399999" })
    eq(rc, 0)
    eq(out, "line 399999\n")
    vim.fn.delete(infile)
  end)

  it("kills the producer's process tree when fzf exits early", function()
    helpers.SKIP_IF_NOT_WIN()
    -- use a uniquely named copy of PING.EXE so the tasklist check below cannot
    -- match an unrelated `ping` running on the machine
    local exe_name = "fzflua_spawn_ping.exe"
    local tmpdir = utils.tempname() .. "_treekill"
    vim.fn.mkdir(tmpdir, "p")
    assert.is.True(vim.fn.isdirectory(tmpdir) == 1)
    local exe = tmpdir .. "/" .. exe_name
    uv.fs_copyfile(vim.fn.exepath("ping"), exe)
    assert.is.True(vim.fn.filereadable(exe) == 1)
    ---@return boolean
    local function ping_running()
      local out = vim.fn.system({ "tasklist", "/FI", "IMAGENAME eq " .. exe_name, "/NH" })
      return out:lower():find(exe_name) ~= nil
    end
    -- control: the unique binary is detected by `ping_running` while running
    local job = vim.fn.jobstart({ exe, "-n", "60", "127.0.0.1" })
    assert.is.True(job > 0)
    vim.wait(5000, ping_running)
    assert.is.True(ping_running())
    vim.fn.jobstop(job)
    vim.wait(5000, function() return not ping_running() end)
    assert.is.False(ping_running())
    -- fzf exits immediately with an invalid option while the producer is still
    -- alive (output to NUL so only the tree-kill can stop it)
    local rc = win_run(string.format('"%s" -n 60 127.0.0.1 >NUL', cmd_path(exe)),
      { "--fzflua-bad-option" })
    eq(rc, 2)
    assert.is.False(ping_running())
    vim.fn.delete(tmpdir, "rf")
  end)

  it("runs the spec through the win_spawn.lua mediator script", function()
    helpers.SKIP_IF_NOT_WIN()
    ---@diagnostic disable-next-line: deprecated
    local _info = debug.getinfo(1, "S")
    ---@cast _info {source: string}
    local root = vim.fn.fnamemodify(_info.source:gsub("^@", ""), ":h:h")
    local script = (root .. "/lua/fzf-lua/win_spawn.lua"):gsub("\\", "/")

    ---@param item string
    ---@param filter string
    ---@return integer? rc
    ---@return string out
    local function run_mediator(item, filter)
      local outfile = utils.tempname()
      local spec_path = utils.tempname()
      write_file(spec_path, libuv.serialize({
        bin = fzf_bin,
        args = { "--filter=" .. filter },
        item = item,
        outfile = outfile,
        env = { SHELL = "cmd.exe" },
      }, true))
      local rc ---@type integer?
      local handle = uv.spawn((vim.v.progpath):gsub("\\", "/"), {
        args = { "-u", "NONE", "-l", script, (spec_path:gsub("\\", "/")) },
        stdio = { nil, nil, nil },
      }, function(code, _)
        rc = code
      end)
      assert.is.True(handle ~= nil)
      vim.wait(30000, function() return rc ~= nil end)
      local out = read_file(outfile)
      vim.fn.delete(outfile)
      -- the mediator removes the spec file after reading it
      eq(vim.fn.filereadable(spec_path), 0)
      return rc, out
    end

    local infile = utils.tempname()
    write_file(infile, "abc\n")
    local item = string.format('type "%s"', cmd_path(infile))
    -- fzf's exit code becomes the mediator script's exit code
    local rc, out = run_mediator(item, "abc")
    eq(rc, 0)
    eq(out, "abc\n")
    rc, out = run_mediator(item, "zzz")
    eq(rc, 1)
    eq(out, "")
    vim.fn.delete(infile)
  end)
end)
