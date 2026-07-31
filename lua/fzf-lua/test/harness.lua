---@diagnostic disable: undefined-field
--- fzf-lua test harness entry point.
---
--- This module is the only entry the fzf-lua test code uses for runner /
--- expectation / child-process utilities. It re-exports a curated surface
--- from the vendored `mini.test` plus the in-house bridge functions, so the
--- rest of the harness (and every spec file) never has to `require` upstream
--- modules directly.
---
--- Why this indirection: when we eventually move off `mini.test` (replace it
--- with a hand-rolled runner, swap implementations, fork it for fzf-lua
--- specific extensions, etc.) only this file changes. Specs and helpers
--- stay put.
---
--- To extend, add the new entry to `M` and import it where used. Never add
--- `require("fzf-lua.test._mini_test")` outside this file.

local MiniTest = require("fzf-lua.test._mini_test")
---@type fzf-lua.test._internal
local bridge = require("fzf-lua.test._internal")

---@class fzf-lua.test.harness
local M = {}

---@diagnostic disable-next-line: undefined-doc-class
M.run = MiniTest.run
M.run_file = MiniTest.run_file
M.run_at_location = MiniTest.run_at_location
M.collect = MiniTest.collect
M.execute = MiniTest.execute
M.stop = MiniTest.stop
M.skip = MiniTest.skip
M.add_note = MiniTest.add_note
M.finally = MiniTest.finally
M.new_set = MiniTest.new_set
M.new_child_neovim = MiniTest.new_child_neovim
M.new_expectation = MiniTest.new_expectation
M.is_executing = MiniTest.is_executing

-- MiniTest.expect is a mutable table that callers (notably helpers.lua)
-- `vim.deepcopy` and extend. Re-export it by reference so copies still
-- observe upstream additions but our writes to `expect.*` would also leak
-- back upstream. That's the upstream behaviour today, so we keep parity.
M.expect = MiniTest.expect

-- Test-case execution context (current case under execution, etc.).
-- Same aliasing concern as `expect`; matches upstream.
M.current = MiniTest.current

-- Bridge functions: the only stable accessor for the vendored mini.test's
-- private `H` table. Documented in `vendor/mini/internal.lua`.
M.bump_screenshot_counter = bridge.bump_screenshot_counter
M.get_screenshot_counter = bridge.get_screenshot_counter
M.case_to_stringid = bridge.case_to_stringid
M.write_screenshot = bridge.write_screenshot
M.fail_with_emphasis = bridge.fail_with_emphasis

return M