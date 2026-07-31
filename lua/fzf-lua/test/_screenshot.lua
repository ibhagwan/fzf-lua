-- Borrowed from grug-far.nvim
-- Used to compare screenshots without "attrs" (highlights)
--
-- This module is the fzf-lua customization on top of vendored `mini.test`.
-- The upstream `H.screenshot_*` helpers in `_mini_test.lua` expect a file
-- format with both `text` and `attr` halves plus separator lines; the
-- fzf-lua reference screenshots we compare against only carry a `text`
-- half, so most of the screenshot machinery stays local. The pieces that
-- are byte-for-byte identical to upstream (`string_to_screenchars`) are
-- delegated through `fzf-lua.test._internal` to keep a single source of
-- truth.
local M = {}

---@diagnostic disable: undefined-field, undefined-global

local MiniTest = require("fzf-lua.test.harness")
-- `_internal` is the single scrape site for the vendored mini.test's
-- private `H` table. All access to upstream internals goes through it so
-- upstream refactors only touch one place.
local internal = require("fzf-lua.test._internal")
local bump_screenshot_counter = internal.bump_screenshot_counter
local case_to_stringid = internal.case_to_stringid
local write_screenshot = internal.write_screenshot
local fail_with_emphasis = internal.fail_with_emphasis
local string_to_screenchars = internal.string_to_screenchars

---@class MiniTestScreenshot

--- modified version of `H.screenshot_new` from vendored mini.test: only
--- carries `text` (no `attr`), and `__tostring` only renders the text
--- block. The line-numbering and ruler layout match upstream so terminal
--- captures line up regardless of which format the reference uses.
---@param t { text?: string[] }
---@param opts test.ScreenOpts?
---@return MiniTestScreenshot
local function screenshot_new(t, opts)
  opts = opts or {}
  local process_screen = function(arr_2d)
    local n_lines, n_cols = #arr_2d, #arr_2d[1]

    -- Prepend lines with line number of the form `01|`
    local n_digits = math.floor(math.log10(n_lines)) + 1
    local format = string.format("%%0%dd|%%s", n_digits)
    local lines = {}
    for i = 1, n_lines do
      table.insert(lines, string.format(format, i, table.concat(arr_2d[i])))
    end

    if opts.no_ruler then
      return table.concat(lines, "\n")
    end
    -- Make ruler
    local prefix = string.rep("-", n_digits) .. "|"
    local ruler = prefix .. ("---------|"):rep(math.ceil(0.1 * n_cols)):sub(1, n_cols)

    return string.format("%s\n%s", ruler, table.concat(lines, "\n"))
  end

  return setmetatable(t, {
    __tostring = function(x)
      return string.format("%s", process_screen(x.text))
    end,
  })
end

--- gets a screenshot from given text lines and attrs
--- note that length of text lines and length of attrs must match
---@param text_lines string[]
---@param opts test.ScreenOpts?
---@return MiniTestScreenshot
function M.from_lines(text_lines, opts)
  opts = opts or {}
  if opts and opts.normalize_paths then
    text_lines = vim.tbl_map(function(x) return (x:gsub([[\]], [[/]])) end, text_lines)
  end
  return screenshot_new({ text = vim.tbl_map(string_to_screenchars, text_lines) }, opts)
end

---@param child MiniTest.child
---@param buf integer
---@param opts test.ScreenOpts?
---@return MiniTestScreenshot
function M.fromChildBufLines(child, buf, opts)
  opts = opts or {}
  if opts and opts.redraw then child.cmd("redraw") end
  local lines = child.api.nvim_buf_get_lines(
    buf or 0,
    opts.start_line and 0,
    opts.end_line and opts.end_line + 1 or -1,
    true)
  return M.from_lines(lines, opts)
end

---@param child MiniTest.child
---@param opts test.ScreenOpts?
---@return MiniTestScreenshot
function M.fromChildScreen(child, opts)
  opts = opts or {}
  if opts and opts.redraw then child.cmd("redraw") end
  local lines = child.lua(([[
      local lines = {}
      for i = %s, %s do
        local line_text = {}
        for j = 1, vim.o.columns do
          table.insert(line_text, vim.fn.screenstring(i, j))
        end
        table.insert(lines, table.concat(line_text))
      end
      return lines
  ]]):format(opts.start_line or 1, opts.end_line or [[vim.o.lines]]))
  return M.from_lines(lines, opts)
end

-- modified version (no attr). Reads the fzf-lua text-only file format:
-- every line is `NN|<text>`, the first line is a ruler. Upstream
-- `H.screenshot_read` expects a richer layout (text + attr halves) so it
-- can't be reused here.
local screenshot_read = function(path)
  local lines = vim.fn.readfile(path)
  local text_lines = vim.list_slice(lines, 2, #lines)

  local f = function(x) return string_to_screenchars(x:gsub("^%d+|", "")) end
  return screenshot_new({ text = vim.tbl_map(f, text_lines) }, opts)
end


-- modified version of `H.screenshot_compare_part` from vendored mini.test:
-- text-only (no attr), and after the per-cell check it auto-pads any
-- extra trailing whitespace the observed screenshot has beyond the
-- reference. That second pass is the fzf-lua-specific tweak that lets
-- references written at narrower terminal widths keep matching when the
-- test runs in a wider one.
local screenshot_compare = function(screen_ref, screen_obs, opts)
  local compare = function(x, y, desc)
    if x ~= y then
      return false,
          ("Different %s. Reference: %s. Observed: %s."):format(desc, vim.inspect(x), vim.inspect(y))
    end
    return true, ""
  end

  --stylua: ignore start
  local ok, cause
  ok, cause = compare(#screen_ref.text, #screen_obs.text, "number of `text` lines")
  if not ok then return ok, cause end

  local lines_to_check, ignore_text = {}, opts.ignore_text or {}
  for i = 1, #screen_ref.text do
    if not vim.tbl_contains(ignore_text, i) then table.insert(lines_to_check, i) end
  end

  for _, i in ipairs(lines_to_check) do
    -- ref can have less col
    ok = #screen_ref.text[i] <= #screen_obs.text[i]
    _, cause = compare(#screen_ref.text[i], #screen_obs.text[i],
      "number of columns in `text` line " .. i)
    if not ok then return ok, cause end

    for j = 1, #screen_ref.text[i] do
      ok, cause = compare(screen_ref.text[i][j], screen_obs.text[i][j],
        string.format("`text` cell at line %s column %s", i, j))
      if not ok then return ok, cause end
    end

    -- auto padding whitespace to screenshots inside lua file?
    for j = #screen_ref.text[i] + 1, #screen_obs.text[i] do
      ok, cause = compare(" ", screen_obs.text[i][j],
        string.format("`text` cell at line %s column %s", i, j))
      if not ok then return ok, cause end
    end
  end
  --stylua: ignore end

  return true, ""
end

M.reference_screenshot = function(screenshot, path, opts)
  if screenshot == nil then return true end

  opts = vim.tbl_extend("force",
    { force = false, ignore_text = {}, directory = "tests/screenshots" }, opts or {})

  local n_screenshot = bump_screenshot_counter()

  if path == nil then
    -- Sanitize path. Replace any control characters, whitespace, OS specific
    -- forbidden characters with '-' (with some useful exception)
    local linux_forbidden = [[/]]
    local windows_forbidden = [[<>:"/\|?*]]
    local pattern = string.format("[%%c%%s%s%s]", vim.pesc(linux_forbidden),
      vim.pesc(windows_forbidden))
    local replacements = setmetatable({ ['"'] = "'" }, { __index = function() return "-" end })
    local name = case_to_stringid(MiniTest.current.case):gsub(pattern, replacements)

    -- Don't end with whitespace or dot (forbidden on Windows)
    name = name:gsub("[%s%.]$", "-")

    -- TODO: remove `:gsub()` after compatibility with Neovim=0.8 is dropped
    path = vim.fs.normalize(opts.directory):gsub("/$", "") .. "/" .. name

    -- Deal with multiple screenshots
    if n_screenshot > 1 then path = path .. string.format("-%03d", n_screenshot) end
  end

  -- If there is no readable screenshot file, create it. Pass with note.
  if opts.force or vim.fn.filereadable(path) == 0 then
    local dir_path = vim.fn.fnamemodify(path, ":p:h")
    vim.fn.mkdir(dir_path, "p")
    write_screenshot(screenshot, path)

    MiniTest.add_note("Created reference screenshot at path " .. vim.inspect(path))
    return true
  end

  local reference = screenshot_read(path)

  -- Compare
  local are_same, cause = screenshot_compare(reference, screenshot, opts)

  if are_same then return true end

  local subject = "screenshot equality to reference at " .. vim.inspect(path)
  local context = string.format("%s\nReference:\n%s\n\nObserved:\n%s", cause, tostring(reference),
    tostring(screenshot))
  fail_with_emphasis(subject, context)
end

-- modified version (no attr, trim trailing whitespace). Mirrors the
-- internal path of `M.reference_screenshot` but takes the reference
-- screenshot as a direct argument so callers can compare two in-memory
-- captures without going through disk.
M.compare = function(reference, screenshot, opts)
  opts = opts or {}
  -- Compare
  local are_same, cause = screenshot_compare(reference, screenshot, opts)

  -- make ruler if we don't embeded it in screenshot
  local ruler = ""
  if opts.no_ruler then
    local arr_2d = reference.text
    local n_lines, n_cols = #arr_2d, #arr_2d[1]
    -- Prepend lines with line number of the form `01|`
    local n_digits = math.floor(math.log10(n_lines)) + 1
    local prefix = string.rep("-", n_digits) .. "|"
    ruler = prefix .. ("---------|"):rep(math.ceil(0.1 * n_cols)):sub(1, n_cols) .. "\n"
  end

  if are_same then return true end

  local subject = "screenshot equality to reference at " .. vim.inspect(path)
  local context = string.format("%s\nReference:\n%s\n\nObserved:\n%s", cause,
    ruler .. tostring(reference),
    ruler .. tostring(screenshot))
  fail_with_emphasis(subject, context)
end

return M