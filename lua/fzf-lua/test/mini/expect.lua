--- Expectations (`assert`-like functions throwing informative errors).

local H = require("fzf-lua.test.mini.util")

H.normalize_reason = function(reason, fallback, ...)
  if vim.is_callable(reason) then reason = reason(...) end
  if type(reason) ~= "string" then reason = fallback end
  return reason
end

--- Raise an expectation failure with an emphasised subject line. Always
--- throws; callers rely on this to terminate the failing path.
H.error_with_emphasis = function(msg, context)
  local lines = { "", H.add_style(msg, "emphasis"), context }
  error(table.concat(lines, "\n"), 0)
end

H.compute_no_equality_cause = function(left, right)
  if type(left) ~= type(right) then return "different types" end

  if type(left) == "string" then
    if vim.fn.strchars(left) ~= vim.fn.strchars(right) then return "different string length" end
    for i = 1, vim.fn.strchars(left) do
      local lchar, rchar = vim.fn.strcharpart(left, i - 1, 1), vim.fn.strcharpart(right, i - 1, 1)
      if lchar ~= rchar then
        return string.format("different character at position %s", i)
            .. string.format(", left = %s, right = %s", vim.inspect(lchar), vim.inspect(rchar))
      end
    end
  end

  if type(left) ~= "table" then return "different values" end

  -- Find key branch with different values
  local traverse
  traverse = function(branch, diff, a, b)
    if not (type(a) == "table" and type(b) == "table") then return end
    local keys = vim.tbl_keys(a)
    table.sort(keys, function(x, y) return tostring(x) < tostring(y) end)
    for _, k in ipairs(keys) do
      if not vim.deep_equal(a[k], b[k]) then
        table.insert(branch, k)
        diff.left, diff.right = a[k], b[k]
        return traverse(branch, diff, a[k], b[k])
      end
    end
  end

  -- - Traverse with both table orders to find the longest possible branch.
  --   This also covers the "present in one but not the other" cases.
  local left_branch, left_diff = {}, {}
  traverse(left_branch, left_diff, left, right)
  local right_branch, right_diff = {}, {}
  traverse(right_branch, right_diff, right, left)

  local branch, ldiff, rdiff = left_branch, left_diff.left, left_diff.right
  if #left_branch < #right_branch then
    branch, ldiff, rdiff = right_branch, right_diff.right, right_diff.left
  end
  ldiff = vim.inspect(ldiff, { newline = " ", indent = "" })
  rdiff = vim.inspect(rdiff, { newline = " ", indent = "" })
  local key_branch = table.concat(vim.tbl_map(vim.inspect, branch), "->")
  return string.format("different values at key %s%s", #branch > 1 and "branch " or "", key_branch)
      .. string.format(", left = %s, right = %s", ldiff, rdiff)
end

--- <fail_reason> `(string|function)` - reason for failing expectation. A
--- function is called with expectation input and should return a string.
--- Default: `nil` for default reason like "Failed expectation for ...".
---@alias __test_expect_fail_reason string|function|nil

H.expect = {}

--- Expect equality of two objects.
---
--- Equality is tested via `vim.deep_equal()`. On failure computes a detailed
--- cause: differing types, string position, or the "key branch" at which two
--- nested tables differ.
---@param left any First object.
---@param right any Second object.
---@param opts table|nil Options. Possible fields:
---   __test_expect_fail_reason
---@return true when the objects are equal
H.expect.equality = function(left, right, opts)
  if vim.deep_equal(left, right) then return true end

  opts = opts or {}
  local fail_reason = H.normalize_reason(opts.fail_reason, "Failed expectation for equality", left, right)
  local cause = H.compute_no_equality_cause(left, right)
  local context = string.format("Cause: %s\nLeft:  %s\nRight: %s", cause, vim.inspect(left), vim.inspect(right))
  ---@diagnostic disable-next-line: missing-return
  H.error_with_emphasis(fail_reason, context)
end

--- Expect no equality of two objects.
---@param left any First object.
---@param right any Second object.
---@param opts table|nil Options. Possible fields:
---   __test_expect_fail_reason
---@return true when the objects are not equal
H.expect.no_equality = function(left, right, opts)
  if not vim.deep_equal(left, right) then return true end

  opts = opts or {}
  local fail_reason = H.normalize_reason(opts.fail_reason, "Failed expectation for *no* equality", left, right)
  local context = string.format("Object: %s", vim.inspect(left))
  ---@diagnostic disable-next-line: missing-return
  H.error_with_emphasis(fail_reason, context)
end

--- Expect function call to raise error.
---@param f function Function to be tested for raising error.
---@param pattern string|nil Pattern which error message should match.
---   Use `nil` or empty string to not test for pattern matching.
---@param opts table|nil Options. Possible fields:
---   __test_expect_fail_reason
---@return true when the call raises a matching error
H.expect.error = function(f, pattern, opts)
  H.check_type("pattern", pattern, "string", true)

  local ok, err = pcall(f)
  err = tostring(err)
  local has_matched_error = not ok and string.find(err, pattern or "") ~= nil
  if has_matched_error then return true end

  opts = opts or {}
  local pattern_suffix = pattern == nil and "" or (" matching pattern " .. vim.inspect(pattern))
  local fail_reason = H.normalize_reason(opts.fail_reason, "Failed expectation for error" .. pattern_suffix, f, pattern)
  local context = ok and "Observed no error" or ("Observed error: " .. err)
  ---@diagnostic disable-next-line: missing-return
  H.error_with_emphasis(fail_reason, context)
end

--- Expect function call to not raise error.
---@param f function Function to be tested for not raising error.
---@param opts table|nil Options. Possible fields:
---   __test_expect_fail_reason
---@return true when the call does not raise
H.expect.no_error = function(f, opts)
  local ok, err = pcall(f)
  if ok then return true end

  opts = opts or {}
  local fail_reason = H.normalize_reason(opts.fail_reason, "Failed expectation for *no* error", f)
  ---@diagnostic disable-next-line: missing-return
  H.error_with_emphasis(fail_reason, "Observed error: " .. tostring(err))
end

--- Expect equality to reference screenshot.
---@param screenshot table|nil Array with screenshot information. Usually an output
---   of `child.get_screenshot()` (see |MiniTest-child-neovim-get_screenshot()|).
---   If `nil`, expectation passed.
---@param path string|nil Path to reference screenshot. If `nil`, constructed
---   automatically in directory `opts.directory` from current case info and
---   total number of times it was called inside current case. If there is no
---   file at `path`, it is created with content of `screenshot`.
---@param opts table|nil Options:
---   - <force> `(boolean)` - whether to forcefully create reference screenshot.
---     Temporary useful during test writing. Default: `false`.
---   - <ignore_text> `(boolean|table)` - whether to ignore all or some text lines.
---     If `true` - ignore all, if number array - ignore text of those lines,
---     if `false` - do not ignore any. Default: `false`.
---   - <ignore_attr> `(boolean|table)` - whether to ignore all or some attr lines.
---     If `true` - ignore all, if number array - ignore attr of those lines,
---     if `false` - do not ignore any. Default: `false`.
---   - <directory> `(string)` - directory where automatically constructed `path`
---     is located. Default: "tests/screenshots".
---   __test_expect_fail_reason
---@return true when the screenshot matches the reference
H.expect.reference_screenshot = function(screenshot, path, opts)
  if screenshot == nil then return true end

  local default_opts = { force = false, ignore_text = false, ignore_attr = false, directory = "tests/screenshots" }
  opts = vim.tbl_extend("force", default_opts, opts or {})

  H.cache.n_screenshots = H.cache.n_screenshots + 1

  if path == nil then
    -- Sanitize path. Replace any control characters, whitespace, OS specific
    -- forbidden characters with '-' (with some useful exception)
    local linux_forbidden = [[/]]
    local windows_forbidden = [[<>:"/\|?*]]
    local pattern = string.format("[%%c%%s%s%s]", vim.pesc(linux_forbidden), vim.pesc(windows_forbidden))
    local replacements = setmetatable({ ['"'] = "'" }, { __index = function() return "-" end })
    local name = H.case_to_stringid(H.current.case):gsub(pattern, replacements)

    -- Don't end with whitespace or dot (forbidden on Windows)
    name = name:gsub("[%s%.]$", "-")
    path = vim.fs.normalize(opts.directory) .. "/" .. name

    -- Deal with multiple screenshots
    if H.cache.n_screenshots > 1 then path = path .. string.format("-%03d", H.cache.n_screenshots) end
  end

  -- If there is no readable screenshot file, create it. Pass with note.
  if opts.force or vim.fn.filereadable(path) == 0 then
    local dir_path = vim.fn.fnamemodify(path, ":p:h")
    vim.fn.mkdir(dir_path, "p")
    H.screenshot_write(screenshot, path)

    H.add_note("Created reference screenshot at path " .. vim.inspect(path))
    return true
  end

  local reference = H.screenshot_read(path)

  -- Compare
  local same_text, cause_text = H.screenshot_compare_part("text", reference, screenshot, opts)
  local same_attr, cause_attr = H.screenshot_compare_part("attr", reference, screenshot, opts)
  if same_text and same_attr then return true end

  local fail_reason_fallback = "Failed expectation for screenshot equality to reference at " .. vim.inspect(path)
  local fail_reason = H.normalize_reason(opts.fail_reason, fail_reason_fallback, screenshot, path)
  local cause = same_text and cause_attr or cause_text
  local context = string.format("%s\nReference:\n%s\n\nObserved:\n%s", cause, tostring(reference), tostring(screenshot))
  ---@diagnostic disable-next-line: missing-return
  H.error_with_emphasis(fail_reason, context)
end

--- Create new expectation function.
---
--- Helper for writing custom functions with behavior similar to other methods
--- of `MiniTest.expect`.
---@param subject string|function|table Subject of expectation. If callable,
---   called with expectation input arguments to produce string value.
---@param predicate function|table Predicate callable. Called with expectation
---   input arguments. Output `false` or `nil` means failed expectation.
---@param fail_context string|function|table Information about fail. If callable,
---   called with expectation input arguments to produce string value.
---@return function Expectation function.
H.new_expectation = function(subject, predicate, fail_context)
  return function(...)
    if predicate(...) then return true end

    local cur_subject = vim.is_callable(subject) and subject(...) or subject
    local cur_context = vim.is_callable(fail_context) and fail_context(...) or fail_context
    H.error_with_emphasis("Failed expectation for " .. cur_subject, cur_context)
  end
end

return H
