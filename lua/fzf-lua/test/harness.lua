--- fzf-lua test harness entry point.
---
--- The only entry fzf-lua test code uses for runner / expectation /
--- child-process utilities. Re-exports the framework modules (`harness/`)
--- so specs and helpers never require internals directly. To extend, add the
--- new entry to `M`.

local runner = require("fzf-lua.test.harness.runner")
local expect = require("fzf-lua.test.harness.expect")
local child = require("fzf-lua.test.harness.child")
local state = require("fzf-lua.test.harness.state")
local util = require("fzf-lua.test.harness.util")

---@class fzf-lua.test.harness
local M = {}

M.run = runner.run
M.stop = runner.stop
M.skip = state.skip
M.add_note = state.add_note
M.new_set = util.new_set
M.new_child_neovim = child.new_child_neovim
M.new_expectation = expect.new_expectation
M.is_executing = state.is_executing

-- `expect` is a mutable table that callers (notably helpers.lua)
-- `vim.deepcopy` and extend. Re-export by reference keeps copies observing
-- additions; that matches upstream behavior, so keep parity.
M.expect = expect.expect

-- Test-case execution context. Same aliasing concern as `expect`.
M.current = state.current

return M
