-- Borrowed from grug-far.nvim
-- Compare screenshots without "attrs" (highlights)
--
-- The fzf-lua customization on top of vendored `mini.test`: upstream
-- `H.screenshot_*` helpers expect a file format with both `text` and `attr`
-- halves, while fzf-lua references only carry `text`, so the screenshot
-- machinery stays local. Pieces byte-for-byte identical to upstream
-- (`string_to_screenchars`) are delegated through `test._internal`.
local M = {}

---@diagnostic disable: undefined-field, undefined-global

local MiniTest = require("fzf-lua.test.harness")
-- Single scrape site for the vendored mini.test's private `H` table.
local internal = require("fzf-lua.test._internal")
local bump_screenshot_counter = internal.bump_screenshot_counter
local case_to_stringid = internal.case_to_stringid
local write_screenshot = internal.write_screenshot
local fail_with_emphasis = internal.fail_with_emphasis
local string_to_screenchars = internal.string_to_screenchars

---@class MiniTestScreenshot

--- `H.screenshot_new` modified for the text-only format: no `attr`, and
--- `__tostring` renders only the text block. Line numbering and ruler match
--- upstream so terminal captures line up regardless of reference format.
---@param t { text?: string[] }
---@param opts test.ScreenOpts?
---@return MiniTestScreenshot
local function screenshot_new(t, opts)
  opts = opts or {}
  local process_screen = function(arr_2d)
    local n_lines = #arr_2d
    -- Prepend lines with line number of the form `01|`
    local format = string.format("%%0%dd|%%s", math.floor(math.log10(n_lines)) + 1)
    local lines = {}
    for i = 1, n_lines do
      table.insert(lines, string.format(format, i, table.concat(arr_2d[i])))
    end
    if opts.no_ruler then
      return table.concat(lines, "\n")
    end
    -- Make ruler
    local prefix = string.rep("-", math.floor(math.log10(n_lines)) + 1) .. "|"
    local ruler = prefix .. ("---------|"):rep(math.ceil(0.1 * #arr_2d[1])):sub(1, #arr_2d[1])
    return string.format("%s\n%s", ruler, table.concat(lines, "\n"))
  end

  return setmetatable(t, {
    __tostring = function(x)
      return process_screen(x.text)
    end,
  })
end

---@param text_lines string[]
---@param opts test.ScreenOpts?
---@return MiniTestScreenshot
function M.from_lines(text_lines, opts)
  opts = opts or {}
  if opts.normalize_paths then
    text_lines = vim.tbl_map(function(x) return (x:gsub([[\]], [[/]])) end, text_lines)
  end
  return screenshot_new({ text = vim.tbl_map(string_to_screenchars, text_lines) }, opts)
end

---@param child MiniTest.child
---@param opts test.ScreenOpts?
---@return MiniTestScreenshot
function M.fromChildScreen(child, opts)
  opts = opts or {}
  if opts.redraw then child.cmd("redraw") end
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

--- Read the fzf-lua text-only file format: `NN|<text>` lines with a ruler on
--- the first line. Upstream `H.screenshot_read` expects a text+attr layout,
--- so it can't be reused.
local screenshot_read = function(path)
  local lines = vim.fn.readfile(path)
  local f = function(x) return string_to_screenchars(x:gsub("^%d+|", "")) end
  return screenshot_new({ text = vim.tbl_map(f, vim.list_slice(lines, 2, #lines)) })
end

--- `H.screenshot_compare_part` modified for text-only: after the per-cell
--- check, trailing whitespace beyond the reference is auto-padded so
--- references written at narrower widths still match wider runs.
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

    -- Auto-pad trailing whitespace past the reference width
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
    -- Sanitize path: replace control chars, whitespace and OS-forbidden
    -- characters with '-' (with some useful exception)
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

  -- Create the reference file when missing or forced
  if opts.force or vim.fn.filereadable(path) == 0 then
    local dir_path = vim.fn.fnamemodify(path, ":p:h")
    vim.fn.mkdir(dir_path, "p")
    write_screenshot(screenshot, path)

    MiniTest.add_note("Created reference screenshot at path " .. vim.inspect(path))
    return true
  end

  local reference = screenshot_read(path)
  local are_same, cause = screenshot_compare(reference, screenshot, opts)

  if are_same then return true end

  local subject = "screenshot equality to reference at " .. vim.inspect(path)
  local context = string.format("%s\nReference:\n%s\n\nObserved:\n%s", cause, tostring(reference),
    tostring(screenshot))
  fail_with_emphasis(subject, context)
end

return M
