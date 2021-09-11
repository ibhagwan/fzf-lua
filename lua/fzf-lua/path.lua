local utils = require "fzf-lua.utils"
local stdio = require "fzf-lua.stdio"
local string_byte = string.byte

local M = {}

M.separator = function()
  return '/'
end

M.starts_with_separator = function(path)
  return path:find(M.separator()) == 1
end

function M.tail(path)
  local os_sep = string_byte(M.separator())

  for i=#path,1,-1 do
    if string_byte(path, i) == os_sep then
      return path:sub(i+1)
    end
  end
  return path
end

function M.extension(path)
  for i=#path,1,-1 do
    if string_byte(path, i) == 46 then
      return path:sub(i+1)
    end
  end
  return path
end

function M.to_matching_str(path)
  return path:gsub('(%-)', '(%%-)'):gsub('(%.)', '(%%.)'):gsub('(%_)', '(%%_)')
end

function M.join(paths)
  -- gsub to remove double separator
  return table.concat(paths, M.separator()):gsub(
    M.separator()..M.separator(), M.separator())
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

function M.is_relative(path, relative_to)
  local p = path:match("^" .. M.to_matching_str(M.add_trailing(relative_to)))
  return p ~= nil
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

local function strsplit(inputstr, sep)
  local t={}
  for str in string.gmatch(inputstr, "([^"..sep.."]+)") do
    table.insert(t, str)
  end
  return t
end

--[[ local function lastIndexOf(haystack, needle)
    local i, j
    local k = 0
    repeat
        i = j
        j, k = string.find(haystack, needle, k + 1, true)
    until j == nil
    return i
end ]]

local function lastIndexOf(haystack, needle)
    local i=haystack:match(".*"..needle.."()")
    if i==nil then return nil else return i-1 end
end

function M.entry_to_file(entry, cwd)
  entry = utils.strip_ansi_coloring(entry)
  local sep = ":"
  local s = strsplit(entry, sep)
  local file = s[1]:match("[^"..utils.nbsp.."]*$")
  -- entries from 'buffers'
  local bufnr = s[1]:match("%[(%d+)")
  local idx = lastIndexOf(s[1], utils.nbsp) or 0
  local noicons = string.sub(entry, idx+1)
  local line = tonumber(s[2])
  local col  = tonumber(s[3])
  if cwd and #cwd>0 and not M.starts_with_separator(file) then
    file = M.join({cwd, file})
    noicons = M.join({cwd, noicons})
  end
  return {
    bufnr = bufnr,
    noicons = noicons,
    path = file,
    line = line or 1,
    col  = col or 1,
  }
end

function M.git_cwd(cmd, cwd)
  if not cwd then return cmd end
  cwd = vim.fn.expand(cwd)
  local arg_cwd = ("-C %s "):format(vim.fn.shellescape(cwd))
  cmd = cmd:gsub("^git ", "git " ..  arg_cwd)
  return cmd
end

function M.is_git_repo(cwd, noerr)
    return not not M.git_root(cwd, noerr)
end

function M.git_root(cwd, noerr)
    local cmd = M.git_cwd("git rev-parse --show-toplevel", cwd)
    local output, err = stdio.get_stdout(cmd)
    if err then
      if not noerr then utils.info(cmd) end
      return nil
    end
    return output[1]
end

return M
