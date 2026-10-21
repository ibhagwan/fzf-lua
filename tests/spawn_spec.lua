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
end)
