local helpers = require("fzf-lua.test.helpers")
local assert = helpers.assert
local libuv = require("fzf-lua.libuv")
local eq = assert.are.equal

describe("Testing spawn.lua", function()
  it("does not delete the cwd when tempname() fails (#2838)", function()
    ---@diagnostic disable-next-line: deprecated
    local _info = debug.getinfo(1, "S")
    ---@cast _info {source: string}
    -- must be absolute: the child runs with `cwd` set to a temp directory
    local root = vim.fn.fnamemodify(_info.source:gsub("^@", ""), ":p:h:h")
    local script = (root .. "/lua/fzf-lua/spawn.lua"):gsub("\\", "/")
    eq(1, vim.fn.filereadable(script))

    -- disposable cwd with a sentinel file that must survive
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, "p")
    local sentinel = dir .. "/sentinel"
    vim.fn.writefile({ "keep" }, sentinel)

    -- simulate Neovim failing to create its tempdir (e.g. disk full), which
    -- makes `tempname()` return an empty string
    local spec = libuv.serialize({ contents = { "spawn-test" } }, true)
    local jobid = vim.fn.jobstart({
      vim.v.progpath,
      "--headless",
      "--clean",
      "--cmd",
      [[lua vim.fn.tempname = function() return "" end]],
      "-l",
      script,
      spec,
    }, { cwd = dir })
    eq(true, jobid > 0)
    local rc = vim.fn.jobwait({ jobid }, 10000)[1]
    eq(0, rc)

    eq(1, vim.fn.filereadable(sentinel))
    vim.fn.delete(dir, "rf")
  end)

  it("does not exit from a fast event (#2858)", function()
    ---@diagnostic disable-next-line: deprecated
    local _info = debug.getinfo(1, "S")
    ---@cast _info {source: string}
    local root = vim.fn.fnamemodify(_info.source:gsub("^@", ""), ":p:h:h")
    root = root:gsub("\\", "/")
    local marker = vim.fn.tempname()
    local script = vim.fn.tempname() .. ".lua"
    vim.fn.writefile({
      ("local root, marker = %s, %s"):format(vim.inspect(root), vim.inspect(marker)),
      [[package.path = root .. "/lua/?.lua;" .. package.path]],
      [[local libuv = require("fzf-lua.libuv")]],
      [[local function record(lines)]],
      [[  local f = assert(io.open(marker, "w"))]],
      [[  f:write(table.concat(lines, "\n") .. "\n")]],
      [[  f:close()]],
      [[end]],
      -- replace the exit so the child can report how it was called, the real
      -- `:cquit` would terminate the process before anything could be checked
      [[vim.cmd.cquit = function(o)]],
      [[  record({ ("cquit count=%s fast=%s"):format(tostring(o.count), tostring(vim.in_fast_event())) })]],
      [[  vim.cmd("qa!")]],
      [[end]],
      -- call `on_finish` from a fast event (no `fn_postprocess`): the exit
      -- must be deferred to the main loop, `:cquit` is rejected with E5560
      -- when called from a libuv callback
      [[local timer = assert(vim.uv.new_timer())]],
      [[timer:start(0, 0, function()]],
      [[  timer:close()]],
      [[  local ok, err = pcall(libuv.spawn_stdio, { contents = {} })]],
      [[  if not ok then record({ "error: " .. tostring(err) }) end]],
      [[end)]],
      [[vim.wait(5000, function() return vim.fn.filereadable(marker) == 1 end)]],
      [[if vim.fn.filereadable(marker) == 0 then record({ "timeout" }) end]],
    }, script)

    local jobid = vim.fn.jobstart({
      vim.v.progpath,
      "--headless",
      "--clean",
      "-l",
      script,
    }, { cwd = root })
    eq(true, jobid > 0)
    local rc = vim.fn.jobwait({ jobid }, 10000)[1]
    eq(0, rc)
    eq({ "cquit count=0 fast=false" }, vim.fn.readfile(marker))
    vim.fn.delete(script)
    vim.fn.delete(marker)
  end)
end)
