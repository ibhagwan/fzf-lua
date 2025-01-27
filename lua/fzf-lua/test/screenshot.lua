-- Borrowed from grug-far.nvim
-- Used to compare screenshots without "attrs" (highlights)
local M = {}

---@class MiniTestScreenshot

--- copied over from mini.test
---@param t { text: string[], attr: string[] }
---@return MiniTestScreenshot
local function screenshot_new(t)
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
    __tostring = function(x)
      return string.format("%s\n\n%s", process_screen(x.text), process_screen(x.attr))
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
---@param attr_lines? string[]
---@return MiniTestScreenshot
function M.from_lines(text_lines, attr_lines, opts)
  if opts and opts.normalize_paths then
    text_lines = vim.tbl_map(function(x) return x:gsub([[\]], [[/]]) end, text_lines)
  end
  local attr_linez = attr_lines or {}
  for _ = 1, #text_lines do
    table.insert(attr_linez, " ")
  end

  local f = function(x)
    return string_to_chars(x)
  end
  return screenshot_new({ text = vim.tbl_map(f, text_lines), attr = vim.tbl_map(f, attr_linez) })
end

function M.fromChildBufLines(child, buf, opts)
  if opts and opts.redraw then child.cmd("redraw") end
  local lines = child.api.nvim_buf_get_lines(buf or 0, 0, -1, true)
  return M.from_lines(lines, {}, opts)
end

function M.fromChildScreen(child, opts)
  if opts and opts.redraw then child.cmd("redraw") end
  local lines = child.lua([[
      local lines = {}
      for i = 1, vim.o.lines do
        local line_text = {}
        for j = 1, vim.o.columns do
          table.insert(line_text, vim.fn.screenstring(i, j))
        end
        table.insert(lines, table.concat(line_text))
      end
      return lines
    ]])
  return M.from_lines(lines, {}, opts)
end

return M
