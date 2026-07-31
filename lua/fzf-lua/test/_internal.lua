--- Bridge over private internals of the vendored `mini.test`.
---
--- The vendored `_mini_test.lua` exports its module-local helper table `H`
--- as `MiniTest._internals` (see the marked block before `return MiniTest`).
--- This module forwards the handful of `H` entry points the harness needs,
--- keeping the vendored-file usage surface small and grep-able.

---@class fzf-lua.test._internal
local M = {}

local MiniTest = require("fzf-lua.test._mini_test")
---@type table
local H = MiniTest._internals

--- Increment and return the per-case screenshot counter (`H.cache.n_screenshots`).
---@return integer
function M.bump_screenshot_counter()
  H.cache.n_screenshots = (H.cache.n_screenshots or 0) + 1
  return H.cache.n_screenshots
end

--- Build a stable, filename-safe string id for a test case.
---@param case table
---@return string
function M.case_to_stringid(case)
  return H.case_to_stringid(case)
end

--- Persist a `MiniTestScreenshot` to `path`.
---@param screenshot table|string
---@param path string
function M.write_screenshot(screenshot, path)
  H.screenshot_write(screenshot, path)
end

--- Widen a display string into an array of per-column screen chars.
---@param s string
---@return string[]
function M.string_to_screenchars(s)
  return H.string_to_screenchars(s)
end

--- Raise an assertion failure with a framed, emphasised subject line.
---@param subject string
---@param context string|table|nil
function M.fail_with_emphasis(subject, context)
  H.error_with_emphasis(subject, context)
end

return M
