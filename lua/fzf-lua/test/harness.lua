---@diagnostic disable: undefined-field
--- fzf-lua test harness entry point.
---
--- The only entry fzf-lua test code uses for runner / expectation /
--- child-process utilities. Re-exports the curated surface from the vendored
--- `mini.test` plus the `_internal` bridge, so specs and helpers never require
--- upstream modules directly. Never `require("fzf-lua.test._mini_test")`
--- outside this file; to extend, add the new entry to `M`.

local MiniTest = require("fzf-lua.test._mini_test")
---@type fzf-lua.test._internal
local bridge = require("fzf-lua.test._internal")

---@class fzf-lua.test.harness
local M = {}

M.run = MiniTest.run
M.stop = MiniTest.stop
M.skip = MiniTest.skip
M.add_note = MiniTest.add_note
M.new_set = MiniTest.new_set
M.new_child_neovim = MiniTest.new_child_neovim
M.new_expectation = MiniTest.new_expectation
-- Used by `scripts/make_cli.lua` worker mode to wait for run completion
M.is_executing = MiniTest.is_executing

-- Parallel runner: executes cases across worker nvim processes, streaming
-- each result live. Used by `scripts/make_cli.lua` when `JOBS>1`.
M.run_parallel = require("fzf-lua.test.parallel").run

-- `MiniTest.expect` is a mutable table that callers (notably helpers.lua)
-- `vim.deepcopy` and extend. Re-export by reference keeps copies observing
-- upstream additions, at the cost of our writes leaking back upstream; that
-- matches upstream behavior, so keep parity.
M.expect = MiniTest.expect

-- Test-case execution context. Same aliasing concern as `expect`.
M.current = MiniTest.current

-- Bridge functions: the only stable accessor for the vendored mini.test's
-- private `H` table. Documented in `test/_internal.lua`.
M.bump_screenshot_counter = bridge.bump_screenshot_counter
M.case_to_stringid = bridge.case_to_stringid
M.write_screenshot = bridge.write_screenshot
M.fail_with_emphasis = bridge.fail_with_emphasis

return M
