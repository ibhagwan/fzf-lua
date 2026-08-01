--- Pure, stateless helpers for the fzf-lua test framework.
---
--- No shared runtime state lives here (see `state.lua`); every function is
--- deterministic given its inputs. Kept dependency-free so any other module
--- can require it without cycles.

-- ANSI codes for common cases
local ansi_codes = {
  fail = "\27[1;31m", -- Bold red
  pass = "\27[1;32m", -- Bold green
  emphasis = "\27[1m", -- Bold
  reset = "\27[0m",
}

-- Symbols used in reporter output
--stylua: ignore
local reporter_symbols = setmetatable({
  ["Pass"] = ansi_codes.pass .. "o" .. ansi_codes.reset,
  ["Pass with notes"] = ansi_codes.pass .. "O" .. ansi_codes.reset,
  ["Fail"] = ansi_codes.fail .. "x" .. ansi_codes.reset,
  ["Fail with notes"] = ansi_codes.fail .. "X" .. ansi_codes.reset,
}, {
  __index = function() return ansi_codes.emphasis .. "?" .. ansi_codes.reset end,
})

local M = {}

M.ansi_codes = ansi_codes
M.reporter_symbols = reporter_symbols

--- Raise an error with `(mini.test)` prefix.
---@param msg string
M.error = function(msg) error("(mini.test) " .. msg, 0) end

--- Print a non-error message with `(mini.test)` prefix.
---@param msg string|table
M.message = function(msg)
  msg = type(msg) == "string" and { { msg } } or msg
  table.insert(msg, 1, { "(mini.test) ", "WarningMsg" })
  vim.cmd([[echo '' | redraw]])
  vim.api.nvim_echo(msg, true, {})
end

--- Validate `val` has type `ref` (`'callable'` matches any callable).
M.check_type = function(name, val, ref, allow_nil)
  if type(val) == ref or (ref == "callable" and vim.is_callable(val)) or (allow_nil and val == nil) then return end
  M.error(string.format("`%s` should be %s, not %s", name, ref, type(val)))
end

--- Call `f` if it is callable, forwarding all arguments.
---@param f any
---@param ... any
---@return any result of `f(...)`, `nil` when `f` is not callable
M.exec_callable = function(f, ...)
  if not vim.is_callable(f) then return nil end
  return f(...)
end

--- Wrap a callable in a fresh function (gives hooks stable identities).
---@param f function|table
---@return function|nil
M.wrap_callable = function(f)
  if not vim.is_callable(f) then return end
  return function(...) return f(...) end
end

--- Prefix every line of each entry of `tbl` with `prefix`, trimming trailing
--- whitespace on the prefix when an entry starts with a newline.
M.add_prefix = function(tbl, prefix)
  return vim.tbl_map(function(x)
    local p = prefix
    if x:sub(1, 1) == "\n" then p = p:gsub("%s*$", "") end
    return ("%s%s"):format(p, x)
  end, tbl)
end

--- Wrap `x` in an ANSI color.
M.add_style = function(x, ansi_code) return string.format("%s%s%s", ansi_codes[ansi_code], x, ansi_codes.reset) end

--- Raise an expectation failure with an emphasised subject line. Always
--- throws; callers rely on this to terminate the failing path.
---@param msg string
---@param context string|nil
M.error_with_emphasis = function(msg, context)
  local lines = { "", M.add_style(msg, "emphasis"), context }
  error(table.concat(lines, "\n"), 0)
end

--- Flatten arbitrarily nested tables/iterables into a flat array.
M.tbl_flatten = function(x) return vim.iter(x):flatten(math.huge):totable() end

--- Whether `x` is an instance of a `new_set()`-created test set.
M.is_instance = function(x, class)
  local metatbl = getmetatable(x)
  return type(metatbl) == "table" and metatbl.class == class
end

--- Create a test set: a table tracking the order of added elements.
---@param opts table|nil set options (`hooks`, `parametrize`, `data`, `n_retry`)
---@param tbl table|nil initial members
---@return table
M.new_set = function(opts, tbl)
  opts = opts or {}
  tbl = tbl or {}

  -- Keep track of new elements order. This allows to iterate through elements
  -- in order they were added.
  local metatbl = { class = "testset", key_order = vim.tbl_keys(tbl), opts = opts }
  metatbl.__newindex = function(t, key, value)
    table.insert(metatbl.key_order, key)
    rawset(t, key, value)
  end

  return setmetatable(tbl, metatbl)
end

--- Traceback of the current call stack, excluding this module's own frames.
---@return string[] array of `file:line` strings
M.traceback = function()
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

--- Build a filename-safe string id for a test case.
---@param case table
---@return string
M.case_to_stringid = function(case)
  local desc = table.concat(case.desc, " | ")
  if #case.args == 0 then return desc end
  local args = vim.inspect(case.args, { newline = "", indent = "" })
  return ("%s + args %s"):format(desc, args)
end

--- Final reporter state of a case, e.g. `"Pass"` or `"Fail with notes"`.
---@param case table
---@return string
M.case_final_state = function(case)
  local pass_fail = #case.exec.fails == 0 and "Pass" or "Fail"
  local with_notes = #case.exec.notes == 0 and "" or " with notes"
  return string.format("%s%s", pass_fail, with_notes)
end

--- Whether any of `cases` has at least one fail.
---@param cases table[] Test cases, each with optional `exec` field
---@return boolean
M.has_fails = function(cases)
  for _, c in ipairs(cases) do
    local exec = c.exec or {}
    if #(exec.fails or {}) > 0 then return true end
  end
  return false
end

return M
