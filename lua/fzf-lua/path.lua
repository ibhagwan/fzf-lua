local utils = require "fzf-lua.utils"
local string_byte = string.byte

local M = {}

M.separator = function()
  return '/'
end

M.dot_byte = string_byte('.')
M.separator_byte = string_byte(M.separator())

M.starts_with_separator = function(path)
  return string_byte(path, 1) == M.separator_byte
  -- return path:find("^"..M.separator()) == 1
end

M.starts_with_cwd = function(path)
  return #path>1
    and string_byte(path, 1) == M.dot_byte
    and string_byte(path, 2) == M.separator_byte
  -- return path:match("^."..M.separator()) ~= nil
end

M.strip_cwd_prefix = function(path)
  return #path>2 and path:sub(3)
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

local function lastIndexOf(haystack, needle)
  local i=haystack:match(".*"..needle.."()")
  if i==nil then return nil else return i-1 end
end

local function stripBeforeLastOccurrenceOf(str, sep)
  local idx = lastIndexOf(str, sep) or 0
  return str:sub(idx+1), idx
end


function M.entry_to_ctag(entry)
  local scode = entry:match("%:.-/^?\t?(.*)/")
  if scode then
    -- scode = string.gsub(scode, "[$]$", "")
    scode = string.gsub(scode, [[\\]], [[\]])
    scode = string.gsub(scode, [[\/]], [[/]])
    scode = string.gsub(scode, "[*]", [[\*]])
  end
  return scode
end

function M.entry_to_location(entry)
  local uri, line, col = entry:match("^(.*://.*):(%d+):(%d+):")
  line = line and tonumber(line-1) or 0
  col = col and tonumber(col) or 1
  return {
    stripped = entry,
    line = line+1,
    col = col,
    uri = uri,
    range = {
      start = {
        line = line,
        character = col,
      }
    }
  }
end

function M.entry_to_file(entry, cwd)
  -- Remove ansi coloring and prefixed icons
  entry = utils.strip_ansi_coloring(entry)
  local stripped, idx = stripBeforeLastOccurrenceOf(entry, utils.nbsp)
  -- entries from 'buffers' contain '[<bufnr>]'
  -- buffer placeholder always comes before the nbsp
  local bufnr = idx>1 and entry:sub(1, idx):match("%[(%d+)") or nil
  if not bufnr and stripped:match("^%a+://") then
    -- Issue #195, when using nvim-jdtls
    -- https://github.com/mfussenegger/nvim-jdtls
    -- LSP entries inside .jar files appear as URIs
    -- 'jdt://' which can then be opened with
    -- 'vim.lsp.util.jump_to_location' or
    -- 'lua require('jdtls').open_jdt_link(vim.fn.expand('jdt://...'))'
    -- Convert to location item so we can use 'jump_to_location'
    -- This can also work with any 'file://' prefixes
    return M.entry_to_location(stripped)
  end
  local s = utils.strsplit(stripped, ":")
  if not s[1] then return {} end
  local file = s[1]
  local line = tonumber(s[2])
  local col  = tonumber(s[3])
  if cwd and #cwd>0 and not M.starts_with_separator(file) then
    file = M.join({cwd, file})
    stripped = M.join({cwd, stripped})
  end
  local terminal
  if bufnr then
    terminal = utils.is_term_buffer(bufnr)
    if terminal then
      file, line = stripped:match("([^:]+):(%d+)")
    end
  end
  return {
    stripped = stripped,
    bufnr = tonumber(bufnr),
    terminal = terminal,
    path = file,
    line = tonumber(line) or 1,
    col  = tonumber(col) or 1,
  }
end

function M.git_cwd(cmd, cwd)
  if not cwd then return cmd end
  cwd = vim.fn.expand(cwd)
  if type(cmd) == 'string' then
    local arg_cwd = ("-C %s "):format(vim.fn.shellescape(cwd))
    cmd = cmd:gsub("^git ", "git " ..  arg_cwd)
  else
    cmd = utils.tbl_deep_clone(cmd)
    table.insert(cmd, 2, "-C")
    table.insert(cmd, 3, cwd)
  end
  return cmd
end

function M.is_git_repo(cwd, noerr)
    return not not M.git_root(cwd, noerr)
end

function M.git_root(cwd, noerr)
    local cmd = M.git_cwd({"git", "rev-parse", "--show-toplevel"}, cwd)
    local output, err = utils.io_systemlist(cmd)
    if err ~= 0 then
        if not noerr then utils.info(unpack(output)) end
        return nil
    end
    return output[1]
end

return M
