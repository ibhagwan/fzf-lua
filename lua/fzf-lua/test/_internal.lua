---@diagnostic disable: undefined-field
--- Stable bridge over private internals of the vendored `mini.test`.
---
--- The upstream `lua/mini/test.lua` exposes everything we need as part of a
--- module-local table `H`. Because `H` is not exported, callers have to dig
--- it out of the module's closures via `debug.getupvalue`. Doing that in more
--- than one place makes the harness fragile: any upstream refactor that moves
--- `H` to a different upvalue slot or wraps the relevant functions in another
--- closure silently breaks the screenshot helpers.
---
--- This module is the single scrape site. It reads `H` once at load time,
--- caches it, and re-exports the four entry points the harness actually
--- touches as a documented, version-stable API. If upstream moves things
--- around, only this file needs to change.

local M = {}

local _h ---@type table|nil cached H table from vendored mini.test

---@return table the H table from vendored mini.test
local function get_h()
  if _h ~= nil then return _h end

  -- Probe an ordered list of well-known exported closures for an upvalue
  -- literally named `H`. If upstream ever drops one of these or wraps it in
  -- another closure, fall through to the next probe.
  local MiniTest = require("fzf-lua.test._mini_test")

  ---@type fun(...): any
  local probes = {
    MiniTest.expect and MiniTest.expect.reference_screenshot,
    MiniTest.expect and MiniTest.expect.error,
    MiniTest.expect and MiniTest.expect.equality,
    MiniTest.new_set,
    MiniTest.run,
  }

  for _, fn in ipairs(probes) do
    if type(fn) == "function" then
      for i = 1, 64 do
        local name, value = debug.getupvalue(fn, i)
        if not name then break end
        if name == "H" and type(value) == "table" then
          _h = value
          return _h
        end
      end
    end
  end

  error("fzf-lua.test._internal: failed to locate `H` in vendored mini.test")
end

-- Force the H lookup to happen during the first require, so any failure
-- shows up as an import error rather than mid-test.
get_h()

--- Increment the per-case screenshot counter and return the new value.
--- Mirrors `H.cache.n_screenshots += 1` as used by mini.test.
---@return integer
function M.bump_screenshot_counter()
  local h = get_h()
  h.cache.n_screenshots = (h.cache.n_screenshots or 0) + 1
  return h.cache.n_screenshots
end

---@return integer current value of `H.cache.n_screenshots` (without mutating)
function M.get_screenshot_counter()
  local h = get_h()
  return h.cache.n_screenshots or 0
end

--- Build a stable string id for a test case.
---@param case table
---@return string
function M.case_to_stringid(case)
  return get_h().case_to_stringid(case)
end

--- Persist a `MiniTestScreenshot` to `path`.
---@param screenshot table|string a value that `vim.fn.writefile` can render
---@param path string
function M.write_screenshot(screenshot, path)
  get_h().screenshot_write(screenshot, path)
end

--- Raise an assertion failure with a coloured, framed subject line.
--- Mirrors `H.error_with_emphasis`.
---@param subject string short label (e.g. "screenshot equality to reference at ...").
---@param context string|table|nil optional body shown under the subject.
function M.fail_with_emphasis(subject, context)
  get_h().error_with_emphasis(subject, context)
end

return M