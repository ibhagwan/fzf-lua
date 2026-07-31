--- Shared state and generic helpers for the fzf-lua test framework.
---
--- The original `mini.test` shipped as one file; the fzf-lua refactor splits
--- it into logical modules (`mini/*.lua`) that all extend the single helper
--- table `H` below, and `init.lua` assembles the public API from it. Layout
--- keeps the future option of adopting Neovim's own screen/harness tooling:
--- screenshot primitives are isolated here and in `_screenshot.lua`.

-- Shared helper table; intentionally untyped so extending modules can inject
-- their own fields (same pattern as the original single-file mini.test).
local H = {}

-- Cache for various data, reset per `execute()` run
---@type table<string, any>
H.cache = {
  -- Message with which case is meant to be skipped
  skip_message = nil,
  -- Queue of callables to be executed after step (hook or test function)
  finally = {},
  -- Whether to stop async execution
  should_stop_execution = false,
  -- Number of screenshots made in current case
  n_screenshots = 0,
}

-- Registry of all Neovim child processes (stopped on `stop()`)
H.child_neovim_registry = {}

-- Current run state, aliased as `MiniTest.current`. Loosely typed so any
-- module can read/write `case` without the linter pinning its shape.
---@type table<string, any>
H.current = { all_cases = nil, case = nil }

-- ANSI codes for common cases
H.ansi_codes = {
  fail = "\27[1;31m", -- Bold red
  pass = "\27[1;32m", -- Bold green
  emphasis = "\27[1m", -- Bold
  reset = "\27[0m",
}

-- Symbols used in reporter output
--stylua: ignore
H.reporter_symbols = setmetatable({
  ["Pass"] = H.ansi_codes.pass .. "o" .. H.ansi_codes.reset,
  ["Pass with notes"] = H.ansi_codes.pass .. "O" .. H.ansi_codes.reset,
  ["Fail"] = H.ansi_codes.fail .. "x" .. H.ansi_codes.reset,
  ["Fail with notes"] = H.ansi_codes.fail .. "X" .. H.ansi_codes.reset,
}, {
  __index = function() return H.ansi_codes.emphasis .. "?" .. H.ansi_codes.reset end,
})

--- Raise an error with `(mini.test)` prefix.
---@param msg string
H.error = function(msg) error("(mini.test) " .. msg, 0) end

--- Validate `val` has type `ref` (`'callable'` matches any callable).
H.check_type = function(name, val, ref, allow_nil)
  if type(val) == ref or (ref == "callable" and vim.is_callable(val)) or (allow_nil and val == nil) then return end
  H.error(string.format("`%s` should be %s, not %s", name, ref, type(val)))
end

--- Call `f` if it is callable, forwarding all arguments.
---@param f any
---@param ... any
---@return any result of `f(...)`, `nil` when `f` is not callable
H.exec_callable = function(f, ...)
  if not vim.is_callable(f) then return nil end
  return f(...)
end

--- Wrap a callable in a fresh function (gives hooks stable identities).
---@param f function|table
---@return function|nil
H.wrap_callable = function(f)
  if not vim.is_callable(f) then return end
  return function(...) return f(...) end
end

--- Prefix every line of each entry of `tbl` with `prefix`, trimming trailing
--- whitespace on the prefix when an entry starts with a newline.
H.add_prefix = function(tbl, prefix)
  return vim.tbl_map(function(x)
    local p = prefix
    if x:sub(1, 1) == "\n" then p = p:gsub("%s*$", "") end
    return ("%s%s"):format(p, x)
  end, tbl)
end

--- Wrap `x` in an ANSI color.
H.add_style = function(x, ansi_code) return string.format("%s%s%s", H.ansi_codes[ansi_code], x, H.ansi_codes.reset) end

--- Flatten arbitrarily nested tables/iterables into a flat array.
H.tbl_flatten = function(x) return vim.iter(x):flatten(math.huge):totable() end

--- Whether `x` is an instance of a `new_set()`-created test set.
H.is_instance = function(x, class)
  local metatbl = getmetatable(x)
  return type(metatbl) == "table" and metatbl.class == class
end

--- Whether any of `cases` has at least one fail.
---@param cases table[] Test cases, each with optional `exec` field
---@return boolean
H.has_fails = function(cases)
  for _, c in ipairs(cases) do
    local exec = c.exec or {}
    if #(exec.fails or {}) > 0 then return true end
  end
  return false
end

--- Traceback of the current call stack, excluding this module's own frames.
---@return string[] array of `file:line` strings
H.traceback = function()
  local level, res = 1, {}
  local info = debug.getinfo(level, "Snl")
  local this_short_src = info.short_src
  while info ~= nil do
    local is_from_file = info.source:sub(1, 1) == "@"
    local is_from_this_file = info.short_src == this_short_src
    if is_from_file and not is_from_this_file then
      local line = string.format([[  %s:%s]], info.short_src, info.currentline)
      table.insert(res, line)
    end
    level = level + 1
    info = debug.getinfo(level, "Snl")
  end
  return res
end

--- Skip the rest of current case, adding `msg` to its notes.
---@param msg string|nil
H.skip = function(msg)
  H.cache.skip_message = msg or "Skip test"
  error(H.cache.skip_message, 0)
end

--- Add note to currently executed test case.
---@param msg string
H.add_note = function(msg)
  local case = H.current.case
  case.exec = case.exec or {}
  case.exec.notes = case.exec.notes or {}
  table.insert(case.exec.notes, msg)
end

--- Register callable execution after current callable finishes (regardless of
--- whether it ended with error or not).
---@param f function|table
H.finally = function(f) table.insert(H.cache.finally, f) end

--- Print a non-error message with `(mini.test)` prefix.
H.message = function(msg)
  msg = type(msg) == "string" and { { msg } } or msg
  table.insert(msg, 1, { "(mini.test) ", "WarningMsg" })
  vim.cmd([[echo '' | redraw]])
  vim.api.nvim_echo(msg, true, {})
end

-- Screenshots ---------------------------------------------------------------
-- Isolated so a future ui-client-backed capture backend can replace it
-- without touching case/expect/child logic.

--- Widen a display string into an array of per-column screen chars.
---@param s string
---@return string[]
H.string_to_screenchars = function(s)
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

--- Wrap raw screenshot arrays (`text`/`attr`) in an object with `tostring`.
---@param t table
---@return table MiniTestScreenshot
H.screenshot_new = function(t)
  local process_screen = function(arr_2d)
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

    return string.format("%s\n%s", ruler, table.concat(lines, "\n"))
  end

  return setmetatable(t, {
    __tostring = function(x) return string.format("%s\n\n%s", process_screen(x.text), process_screen(x.attr)) end,
  })
end

--- Encode numeric `screenattr()` values as single characters, cycling 33..126.
H.screenshot_encode_attr = function(attr)
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
H.screenshot_compare_part = function(part, ref, obs, opts)
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
H.screenshot_write = function(screenshot, path) vim.fn.writefile(vim.split(tostring(screenshot), "\n"), path) end

--- Read a screenshot reference file written by `H.screenshot_write`.
---@param path string
---@return table MiniTestScreenshot
H.screenshot_read = function(path)
  -- General structure of screenshot with `n` lines:
  -- 1: ruler-separator
  -- 2, n+1: `prefix`|`text`
  -- n+2: empty line
  -- n+3: ruler-separator
  -- n+4, 2n+3: `prefix`|`attr`
  local lines = vim.fn.readfile(path)
  local n = 0.5 * (#lines - 3)
  local text_lines, attr_lines = vim.list_slice(lines, 2, n + 1), vim.list_slice(lines, n + 4, 2 * n + 3)

  local f = function(x) return H.string_to_screenchars(x:gsub("^%d+|", "")) end
  return H.screenshot_new({ text = vim.tbl_map(f, text_lines), attr = vim.tbl_map(f, attr_lines) })
end

return H
