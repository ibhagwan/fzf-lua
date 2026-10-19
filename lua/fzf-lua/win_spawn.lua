---@diagnostic disable-next-line: deprecated
-- This file should only be loaded from the mediator headless instance,
-- spawned by `fzf.raw_fzf` via `termopen` inside a terminal buffer (TUI).
-- It executes a serialized `fzf-lua.WinSpawnSpec`: `uv.spawn` runs fzf with
-- raw argv (no shell, no escaping), stderr inherits this pty (fzf's light
-- renderer needs a console), stdout is redirected to the result file and the
-- optional item producer is pumped into fzf's stdin. The exit code becomes
-- the terminal job's exit code (see `fzf.raw_fzf`).
assert(#vim.api.nvim_list_uis() == 0)

-- every Windows nvim listens by default (`\\.\pipe\nvim.<pid>.<n>`); the
-- mediator doesn't need the server and its pipe would be listed as a
-- server in the `serverlist` picker (`providers/nvim.lua` discovery globs
-- that namespace), stopping the server removes the pipe (same as
-- `spawn.lua`/`rpc.lua`/`scripts/cli.lua`)
if vim.v.servername and #vim.v.servername > 0 then
  pcall(vim.fn.serverstop, vim.v.servername)
end

-- path to this file
local _info = debug.getinfo(1, "S")
---@cast _info {source: string}
local __FILE__ = _info.source:gsub("^@", "")

-- add the current folder to package.path so we can 'require'
-- prepend this folder first, so our modules always get first
-- priority over some unknown random module with the same name
package.path = ("%s/?.lua;"):format(vim.fn.fnamemodify(__FILE__, ":h:h")) .. package.path

local libuv = require("fzf-lua.libuv")

local spec_path = assert(_G.arg[1], "win_spawn.lua: missing spec path")
local f = assert(io.open(spec_path, "r"), "win_spawn.lua: cannot open " .. spec_path)
local spec_str = f:read("*a") --[[@as string]]
f:close()
vim.fn.delete(spec_path)

local rc ---@type integer?
local spec = libuv.deserialize(spec_str)
---@cast spec fzf-lua.WinSpawnSpec
libuv.win_spawn(spec, {
  on_exit = function(code) rc = code end,
})

-- keep the event loop running until fzf and the producer tree exited,
-- then exit with fzf's code (`cquit` keeps the temp dir cleanup intact,
-- unlike `os.exit`)
vim.wait(2147483647, function() return rc ~= nil end)
vim.cmd.cquit({ count = rc })
