-- Borrowed from grug-far.nvim
-- Used to compare screenshots without "attrs" (highlights)
local M = {}

---@diagnostic disable: undefined-field, undefined-global

local MiniTest = require("mini.test")

-- get helper module from upvalues
local _, H = debug.getupvalue(MiniTest.expect.reference_screenshot, 1)

---@class MiniTestScreenshot

--- copied over from mini.test
---@param t { text: string[], attr: string[] }
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

---@param s string
---@return string[]
local function string_to_chars(s)
  -- Can't use `vim.split(s, '')` because of multibyte characters
  local res = {}
  for i = 1, vim.fn.strchars(s) do
    table.insert(res, vim.fn.strcharpart(s, i - 1, 1))
  end
  return res
end

--- gets a screenshot from given text lines and attrs
--- note that length of text lines and length of attrs must match
---@param text_lines string[]
---@param opts test.ScreenOpts?
---@return MiniTestScreenshot
function M.from_lines(text_lines, opts)
  opts = opts or {}
  if opts and opts.normalize_paths then
    text_lines = vim.tbl_map(function(x) return x:gsub([[\]], [[/]]) end, text_lines)
  end
  local f = function(x)
    return string_to_chars(x)
  end
  return screenshot_new({ text = vim.tbl_map(f, text_lines) }, opts)
end

---@param child MiniTest.child
---@param buf integer
---@param opts test.ScreenOpts?
---@return MiniTestScreenshot
function M.fromChildBufLines(child, buf, opts)
  opts = opts or {}
  if opts and opts.redraw then child.cmd("redraw") end
  local lines = child.api.nvim_buf_get_lines(buf or 0, opts.start_line and 0, opts.end_line + 1 or -1,
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

-- modified version (no attr)
local screenshot_read = function(path)
  local lines = vim.fn.readfile(path)
  local text_lines = vim.list_slice(lines, 2, #lines)

  local f = function(x) return H.string_to_chars(x:gsub("^%d+|", "")) end
  return screenshot_new({ text = vim.tbl_map(f, text_lines) }, opts)
end


-- modified version (no attr)
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

  H.cache.n_screenshots = H.cache.n_screenshots + 1

  if path == nil then
    -- Sanitize path. Replace any control characters, whitespace, OS specific
    -- forbidden characters with '-' (with some useful exception)
    local linux_forbidden = [[/]]
    local windows_forbidden = [[<>:"/\|?*]]
    local pattern = string.format("[%%c%%s%s%s]", vim.pesc(linux_forbidden),
      vim.pesc(windows_forbidden))
    local replacements = setmetatable({ ['"'] = "'" }, { __index = function() return "-" end })
    local name = H.case_to_stringid(MiniTest.current.case):gsub(pattern, replacements)

    -- Don't end with whitespace or dot (forbidden on Windows)
    name = name:gsub("[%s%.]$", "-")

    -- TODO: remove `:gsub()` after compatibility with Neovim=0.8 is dropped
    path = vim.fs.normalize(opts.directory):gsub("/$", "") .. "/" .. name

    -- Deal with multiple screenshots
    if H.cache.n_screenshots > 1 then path = path .. string.format("-%03d", H.cache.n_screenshots) end
  end

  -- If there is no readable screenshot file, create it. Pass with note.
  if opts.force or vim.fn.filereadable(path) == 0 then
    local dir_path = vim.fn.fnamemodify(path, ":p:h")
    vim.fn.mkdir(dir_path, "p")
    H.screenshot_write(screenshot, path)

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
  H.error_expect(subject, context)
end

-- modified version (no attr, trim trailing whitespace)
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
  H.error_expect(subject, context)
end

return M
