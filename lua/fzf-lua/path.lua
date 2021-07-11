local M = {}

M.separator = function()
  return '/'
end

M.tail = (function()
  local os_sep = M.separator()
  local match_string = '[^' .. os_sep .. ']*$'

  return function(path)
    return string.match(path, match_string)
  end
end)()

function M.to_matching_str(path)
  return path:gsub('(%-)', '(%%-)'):gsub('(%.)', '(%%.)'):gsub('(%_)', '(%%_)')
end

function M.join(paths)
  return table.concat(paths, M.separator())
end

function M.split(path)
  return path:gmatch('[^'..M.separator()..']+'..M.separator()..'?')
end

---Get the basename of the given path.
---@param path string
---@return string
function M.basename(path)
  path = M.remove_trailing(path)
  local i = path:match("^.*()" .. M.separator())
  if not i then return path end
  return path:sub(i + 1, #path)
end

function M.extension(path)
  -- path = M.basename(path)
  -- return path:match(".+%.(.*)")
  -- search for the first dotten string part up to space
  -- then match anything after the dot up to ':/\.'
  path = path:match("(%.[^ :\t\x1b]+)")
  if not path then return path end
  return path:match("^.*%.([^ :\\/]+)")
end

---Get the path to the parent directory of the given path. Returns `nil` if the
---path has no parent.
---@param path string
---@param remove_trailing boolean
---@return string|nil
function M.parent(path, remove_trailing)
  path = " " .. M.remove_trailing(path)
  local i = path:match("^.+()" .. M.separator())
  if not i then return nil end
  path = path:sub(2, i)
  if remove_trailing then
    path = M.remove_trailing(path)
  end
  return path
end

---Get a path relative to another path.
---@param path string
---@param relative_to string
---@return string
function M.relative(path, relative_to)
  local p, _ = path:gsub("^" .. M.to_matching_str(M.add_trailing(relative_to)), "")
  return p
end

function M.add_trailing(path)
  if path:sub(-1) == M.separator() then
    return path
  end

  return path..M.separator()
end

function M.remove_trailing(path)
  local p, _ = path:gsub(M.separator()..'$', '')
  return p
end

function M.shorten(path, max_length)
  if string.len(path) > max_length - 1 then
    path = path:sub(string.len(path) - max_length + 1, string.len(path))
    local i = path:match("()" .. M.separator())
    if not i then
      return "…" .. path
    end
    return "…" .. path:sub(i, -1)
  else
    return path
  end
end

return M
