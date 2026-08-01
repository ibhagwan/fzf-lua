--- Screenshot primitives for the fzf-lua test framework.
---
--- Two reference formats coexist:
--- * attr format: `text` + `attr` halves, used by `expect.reference_screenshot`
---   and `child.get_screenshot()` (line numbers + ruler on both halves).
--- * text format: text only, used by `helpers.expect_screen_lines()` (fzf-lua
---   references only carry text, so trailing whitespace is auto-padded).
---
--- Isolated here so a future ui-client-backed capture backend can replace the
--- capture side without touching case/expect/child logic.

local state = require("fzf-lua.test.harness.state")
local util = require("fzf-lua.test.harness.util")

---@class MiniTestScreenshot

local M = {}

--- Widen a display string into an array of per-column screen chars.
---@param s string
---@return string[]
M.string_to_screenchars = function(s)
  -- Can't use `vim.split(s, '')` because of multibyte characters
  local res = {}
  for i = 1, vim.fn.strchars(s) do
    local ch = vim.fn.strcharpart(s, i - 1, 1)
    table.insert(res, ch)
    -- Not single-width characters are read as a single char, but result into
    -- `{ ch, '', ... }` when computing observed screenshot (as this is how
    -- `vim.fn.screenstring()` works)
    for _ = 1, vim.fn.strdisplaywidth(ch) - 1 do
      table.insert(res, "")
    end
  end
  return res
end

-- Attr format ---------------------------------------------------------------

--- Render a 2D screen array with line numbers and a ruler.
---@param arr_2d string[][]
---@param with_ruler boolean
---@return string
local function process_screen(arr_2d, with_ruler)
  local n_lines, n_cols = #arr_2d, #arr_2d[1]

  -- Prepend lines with line number of the form `01|`
  local n_digits = math.floor(math.log10(n_lines)) + 1
  local format = string.format("%%0%dd|%%s", n_digits)
  local lines = {}
  for i = 1, n_lines do
    table.insert(lines, string.format(format, i, table.concat(arr_2d[i])))
  end

  -- Make ruler
  local prefix = string.rep("-", n_digits) .. "|"
  local ruler = prefix .. ("---------|"):rep(math.ceil(0.1 * n_cols)):sub(1, n_cols)

  if not with_ruler then return table.concat(lines, "\n") end
  return string.format("%s\n%s", ruler, table.concat(lines, "\n"))
end

--- Wrap raw screenshot arrays (`text`/`attr`) in an object with `tostring`.
---@param t table
---@return table MiniTestScreenshot
M.new_attr = function(t)
  return setmetatable(t, {
    __tostring = function(x) return string.format("%s\n\n%s", process_screen(x.text, true), process_screen(x.attr, true)) end,
  })
end

--- Encode numeric `screenattr()` values as single characters, cycling 33..126.
M.encode_attr = function(attr)
  local attr_codes, res = {}, {}
  -- Use 48 so that codes start from `'0'`
  local cur_code_id = 48
  for _, l in ipairs(attr) do
    local res_line = {}
    for _, s in ipairs(l) do
      -- Assign character codes to numerical attributes in order of their
      -- appearance on the screen. This leads to be a more reliable way of
      -- comparing two different screenshots (at cost of bigger effect when
      -- screenshot changes slightly).
      if not attr_codes[s] then
        attr_codes[s] = string.char(cur_code_id)
        -- Cycle through 33...126
        cur_code_id = math.fmod(cur_code_id + 1 - 33, 94) + 33
      end
      table.insert(res_line, attr_codes[s])
    end
    table.insert(res, res_line)
  end
  return res
end

--- Compare one part (`'text'`/`'attr'`) of reference vs observed screenshot.
---@param part string part name, `"text"` or `"attr"`
---@param ref table reference screenshot
---@param obs table observed screenshot
---@param opts table comparison options (`ignore_text`/`ignore_attr`)
---@return boolean are_same
---@return string cause
M.compare_attr_part = function(part, ref, obs, opts)
  local ignore_part = opts["ignore_" .. part]
  if ignore_part == true then return true, "" end

  local compare = function(x, y, desc)
    if x == y then return true, "" end
    return false, ("Cause: different %s, reference = %s, observed = %s"):format(desc, vim.inspect(x), vim.inspect(y))
  end

  local ok, cause
  ok, cause = compare(#ref[part], #obs[part], "number of `" .. part .. "` lines")
  if not ok then return ok, cause end

  local lines_to_check = {}
  for i = 1, #ref[part] do
    local is_ignore_part = type(ignore_part) == "table" and vim.tbl_contains(ignore_part, i)
    if not is_ignore_part then table.insert(lines_to_check, i) end
  end

  for _, i in ipairs(lines_to_check) do
    ok, cause = compare(#ref[part][i], #obs[part][i], "number of columns in `" .. part .. "` line " .. i)
    if not ok then return ok, cause end

    for j = 1, #ref[part][i] do
      ok, cause = compare(ref[part][i][j], obs[part][i][j], "`" .. part .. "` cell at line " .. i .. " column " .. j)
      if not ok then return ok, cause end
    end
  end

  return true, ""
end

--- Write a screenshot to `path` in the reference file format.
M.write = function(screenshot, path) vim.fn.writefile(vim.split(tostring(screenshot), "\n"), path) end

--- Read a screenshot reference file written by `M.write` (attr format).
---@param path string
---@return table MiniTestScreenshot
M.read_attr = function(path)
  -- General structure of screenshot with `n` lines:
  -- 1: ruler-separator
  -- 2, n+1: `prefix`|`text`
  -- n+2: empty line
  -- n+3: ruler-separator
  -- n+4, 2n+3: `prefix`|`attr`
  local lines = vim.fn.readfile(path)
  local n = 0.5 * (#lines - 3)
  local text_lines, attr_lines = vim.list_slice(lines, 2, n + 1), vim.list_slice(lines, n + 4, 2 * n + 3)

  local f = function(x) return M.string_to_screenchars(x:gsub("^%d+|", "")) end
  return M.new_attr({ text = vim.tbl_map(f, text_lines), attr = vim.tbl_map(f, attr_lines) })
end

-- Text format ----------------------------------------------------------------
-- Borrowed from grug-far.nvim: compare screenshots without "attrs". References
-- only carry text, and trailing whitespace beyond the reference is auto-padded
-- so references written at narrower widths still match wider runs.

--- Wrap text-only screenshot arrays in an object with `tostring`. Line
--- numbering and ruler match the attr format so captures line up regardless.
---@param t { text?: string[] }
---@param opts test.ScreenOpts?
---@return MiniTestScreenshot
M.new_text = function(t, opts)
  opts = opts or {}
  local process = function(arr_2d)
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
    local prefix = string.rep("-", math.floor(math.log10(n_lines)) + 1) .. "|"
    local ruler = prefix .. ("---------|"):rep(math.ceil(0.1 * #arr_2d[1])):sub(1, #arr_2d[1])
    return string.format("%s\n%s", ruler, table.concat(lines, "\n"))
  end

  return setmetatable(t, {
    __tostring = function(x)
      return process(x.text)
    end,
  })
end

---@param text_lines string[]
---@param opts test.ScreenOpts?
---@return MiniTestScreenshot
M.from_lines = function(text_lines, opts)
  opts = opts or {}
  if opts.normalize_paths then
    text_lines = vim.tbl_map(function(x) return (x:gsub([[\]], [[/]])) end, text_lines)
  end
  return M.new_text({ text = vim.tbl_map(M.string_to_screenchars, text_lines) }, opts)
end

---@param child MiniTest.child
---@param opts test.ScreenOpts?
---@return MiniTestScreenshot
M.from_child_screen = function(child, opts)
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
--- the first line.
---@param path string
---@return MiniTestScreenshot
M.read_text = function(path)
  local lines = vim.fn.readfile(path)
  local f = function(x) return M.string_to_screenchars(x:gsub("^%d+|", "")) end
  return M.new_text({ text = vim.tbl_map(f, vim.list_slice(lines, 2, #lines)) })
end

--- Compare text-only reference vs observed screenshot. The reference may be
--- narrower than the observed (extra columns are compared against spaces).
---@param screen_ref table
---@param screen_obs table
---@param opts table comparison options (`ignore_text`)
---@return boolean are_same
---@return string cause
M.compare_text = function(screen_ref, screen_obs, opts)
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

--- Expect equality of a text-only screenshot to a reference file. When the
--- reference is missing it is created (with a note); `opts.force` overwrites.
---@param screenshot MiniTestScreenshot|nil
---@param path string|nil
---@param opts table|nil `force`/`ignore_text`/`directory`
---@return boolean when the screenshot matches the reference
M.reference_text = function(screenshot, path, opts)
  if screenshot == nil then return true end

  opts = vim.tbl_extend("force",
    { force = false, ignore_text = {}, directory = "tests/screenshots" }, opts or {})

  state.cache.n_screenshots = state.cache.n_screenshots + 1
  local n_screenshot = state.cache.n_screenshots

  if path == nil then
    -- Sanitize path: replace control chars, whitespace and OS-forbidden
    -- characters with '-' (with some useful exception)
    local linux_forbidden = [[/]]
    local windows_forbidden = [[<>:"/\|?*]]
    local pattern = string.format("[%%c%%s%s%s]", vim.pesc(linux_forbidden),
      vim.pesc(windows_forbidden))
    local replacements = setmetatable({ ['"'] = "'" }, { __index = function() return "-" end })
    local name = util.case_to_stringid(state.current.case):gsub(pattern, replacements)

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
    M.write(screenshot, path)

    state.add_note("Created reference screenshot at path " .. vim.inspect(path))
    return true
  end

  local reference = M.read_text(path)
  local are_same, cause = M.compare_text(reference, screenshot, opts)

  if are_same then return true end

  local subject = "screenshot equality to reference at " .. vim.inspect(path)
  local context = string.format("%s\nReference:\n%s\n\nObserved:\n%s", cause, tostring(reference),
    tostring(screenshot))
  ---@diagnostic disable-next-line: missing-return
  util.error_with_emphasis(subject, context)
end

return M
