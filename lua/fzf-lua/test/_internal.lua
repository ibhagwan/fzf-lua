---@diagnostic disable: undefined-field
--- Bridge over private internals of the vendored `mini.test`.
---
--- Why this module exists
--- ----------------------
--- The vendored `_mini_test.lua` keeps its helpers in a module-local `H`
--- table that is never exported. Reaching into it without going through a
--- single dedicated site would mean every consumer duplicates
--- `debug.getupvalue(MiniTest.expect.equality, ...)` and tries to find `H`,
--- which is brittle: any upstream refactor that moves `H` to a different
--- upvalue slot, wraps the relevant functions in another closure, or stops
--- exporting the function we picked as a probe silently breaks the harness.
---
--- Why we use `debug.getupvalue` instead of globals / vendored modifications
--- ----------------------------------------------------------------------
--- Two natural alternatives were considered and rejected:
---  1. Adding `MiniTest._internals = H` (or similar) to the vendored file:
---     breaks the byte-for-byte vendor promise; every bump upstream needs a
---     re-touch.
---  2. Setting `_G._fzf_lua_mini_test_h = H` after require: pollutes `_G`,
---     which leaks to the rest of the user's Neovim session during
---     interactive runs and makes the bridge visible to unrelated code.
---
--- `debug.getupvalue` is the only option that touches neither vendored code
--- nor `_G`. The lookup is cached after the first successful resolution so
--- the cost is paid exactly once per process. All upstream probe failures
--- surface as a single import-time error rather than mid-test failures.
---
--- When to update this file
--- ------------------------
--- If upstream `mini.test` reorganizes its upvalue layout (reorders locals,
--- wraps `MiniTest.expect.equality` in another closure, etc.) only the
--- probe list and the read sites need updating. Callers stay put.
---
--- What this module exposes
--- -------------------------
--- Curated, version-stable forwards over the handful of `H` entry points the
--- fzf-lua test harness actually needs:
---   * `bump_screenshot_counter`, `get_screenshot_counter` - per-case count
---   * `case_to_stringid` - sanitize a case into a filename-safe id
---   * `read_screenshot`, `write_screenshot` - reference image persistence
---   * `string_to_screenchars` - widen one display column into screen chars
---   * `fail_with_emphasis` - assertion failure renderer
---
--- Anything else in `H` is intentionally NOT re-exported; add to this list
--- only after a concrete call site exists, so the surface stays small.

local M = {}

---@type table|nil cached H table from vendored mini.test
local _h

---@return table the H table from vendored mini.test
local function get_h()
  if _h ~= nil then return _h end

  -- Ordered list of well-known exported closures, each expected to capture
  -- `H` as an upvalue. Earlier entries are preferred because they were the
  -- historically stable shape of the upstream module; later entries are
  -- fallbacks for hypothetical refactors that wrap the original probe in
  -- another closure (in which case the inner probe still has `H`).
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
  return get_h().cache.n_screenshots or 0
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

--- Read a reference screenshot from `path` and return it as a fresh
--- `MiniTestScreenshot` value (with both `text` and `attr` populated).
---@param path string
---@return table
function M.read_screenshot(path)
  return get_h().screenshot_read(path)
end

--- Widen a one-line display string into an array of per-column screen chars.
--- Used by `_screenshot.lua` to build MiniTestScreenshot.text entries.
---@param s string
---@return string[]
function M.string_to_screenchars(s)
  return get_h().string_to_screenchars(s)
end

--- Raise an assertion failure with a coloured, framed subject line.
--- Mirrors `H.error_with_emphasis`.
---@param subject string short label (e.g. "screenshot equality to reference at ...").
---@param context string|table|nil optional body shown under the subject.
function M.fail_with_emphasis(subject, context)
  get_h().error_with_emphasis(subject, context)
end

return M