---@diagnostic disable: undefined-field
--- fzf-lua test harness entry point.
---
--- The only entry fzf-lua test code uses for runner / expectation /
--- child-process utilities. Re-exports the refactored framework (`mini/`)
--- plus the screenshot bridge, so specs and helpers never require internals
--- directly. To extend, add the new entry to `M`.

local MiniTest = require("fzf-lua.test.mini.init")

---@class fzf-lua.test.harness
local M = {}

M.run = MiniTest.run
M.stop = MiniTest.stop
M.skip = MiniTest.skip
M.add_note = MiniTest.add_note
M.new_set = MiniTest.new_set
M.new_child_neovim = MiniTest.new_child_neovim
M.new_expectation = MiniTest.new_expectation
M.is_executing = MiniTest.is_executing

-- `MiniTest.expect` is a mutable table that callers (notably helpers.lua)
-- `vim.deepcopy` and extend. Re-export by reference keeps copies observing
-- additions; that matches upstream behavior, so keep parity.
M.expect = MiniTest.expect

-- Test-case execution context. Same aliasing concern as `expect`.
M.current = MiniTest.current

-- Screenshot bridge: reach into the framework's private `H` table for the
-- text-only screenshot backend (`_screenshot.lua`) without exposing it whole.
local H = MiniTest._internals
M.bump_screenshot_counter = function()
  H.cache.n_screenshots = (H.cache.n_screenshots or 0) + 1
  return H.cache.n_screenshots
end
M.case_to_stringid = H.case_to_stringid
M.write_screenshot = H.screenshot_write
M.string_to_screenchars = H.string_to_screenchars
M.fail_with_emphasis = H.error_with_emphasis

return M
