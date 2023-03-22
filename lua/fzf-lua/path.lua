local utils = require "fzf-lua.utils"
local string_sub = string.sub
local string_byte = string.byte

local M = {}

M.separator = function()
  return "/"
end

M.dot_byte = string_byte(".")
M.separator_byte = string_byte(M.separator())

M.starts_with_separator = function(path)
  return string_byte(path, 1) == M.separator_byte
  -- return path:find("^"..M.separator()) == 1
end

M.ends_with_separator = function(path)
  return string_byte(path, #path) == M.separator_byte
end

M.starts_with_cwd = function(path)
  return #path > 1
      and string_byte(path, 1) == M.dot_byte
      and string_byte(path, 2) == M.separator_byte
  -- return path:match("^."..M.separator()) ~= nil
end

M.strip_cwd_prefix = function(path)
  return #path > 2 and path:sub(3)
end

function M.tail(path)
  local os_sep = string_byte(M.separator())

  for i = #path, 1, -1 do
    if string_byte(path, i) == os_sep then
      return path:sub(i + 1)
    end
  end
  return path
end

function M.extension(path)
  for i = #path, 1, -1 do
    if string_byte(path, i) == 46 then
      return path:sub(i + 1)
    end
  end
  return path
end

function M.to_matching_str(path)
  -- return path:gsub('(%-)', '(%%-)'):gsub('(%.)', '(%%.)'):gsub('(%_)', '(%%_)')
  -- above is missing other lua special chars like '+' etc (#315)
  return utils.lua_regex_escape(path)
end

function M.join(paths)
  -- gsub to remove double separator
  return table.concat(paths, M.separator()):gsub(
    M.separator() .. M.separator(), M.separator())
end

function M.split(path)
  return path:gmatch("[^" .. M.separator() .. "]+" .. M.separator() .. "?")
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

  return path .. M.separator()
end

function M.remove_trailing(path)
  local p, _ = path:gsub(M.separator() .. "$", "")
  return p
end

local function find_next(str, char, start_idx)
  local i_char = string_byte(char, 1)
  for i = start_idx or 1, #str do
    if string_byte(str, i) == i_char then
      return i
    end
  end
end

-- I'm not sure why this happens given that neovim is single threaded
-- but it seems that 'oldfiles' provider processing entries concurrently
-- crashes when trying to access `vim.env.HOME' from two differnt entries
-- at the same time due to being run in a coroutine (#447)
M.HOME = function()
  if not M.__HOME then
    -- use 'os.getenv' instead of 'vim.env' due to (#452):
    -- E5560: nvim_exec must not be called in a lua loop callback
    -- M.__HOME = vim.env.HOME
    M.__HOME = os.getenv("HOME")
  end
  return M.__HOME
end

function M.tilde_to_HOME(path)
  return path and path:gsub("^~", M.HOME()) or nil
end

function M.HOME_to_tilde(path)
  return path and path:gsub("^" .. utils.lua_regex_escape(M.HOME()), "~") or nil
end

function M.shorten(path, max_len)
  local sep = M.separator()
  local parts = {}
  local start_idx = 1
  max_len = max_len and tonumber(max_len) > 0 and max_len or 1
  repeat
    local i = find_next(path, sep, start_idx)
    local end_idx = i and start_idx + math.min(i - start_idx, max_len) - 1 or nil
    table.insert(parts, string_sub(path, start_idx, end_idx))
    if i then start_idx = i + 1 end
  until not i
  return table.concat(parts, sep)
end

function M.lengthen(path)
  -- we use 'glob_escape' to escape \{} (#548)
  path = utils.glob_escape(path)
  return vim.fn.glob(path:gsub(M.separator(), "%*" .. M.separator())
        -- remove the starting '*/' if any
        :gsub("^%*" .. M.separator(), M.separator())):match("[^\n]+")
      or string.format("<glob expand failed for '%s'>", path)
end

local function lastIndexOf(haystack, needle)
  local i = haystack:match(".*" .. needle .. "()")
  if i == nil then return nil else return i - 1 end
end

local function stripBeforeLastOccurrenceOf(str, sep)
  local idx = lastIndexOf(str, sep) or 0
  return str:sub(idx + 1), idx
end

function M.entry_to_ctag(entry, noesc)
  local ctag = entry:match("%:.-/^?\t?(.*)/")
  -- if tag name contains a slash we could
  -- have the wrong match, most tags start
  -- with ^ so try to match based on that
  ctag = ctag and ctag:match("/^(.*)") or ctag
  if ctag and not noesc then
    -- required escapes for vim.fn.search()
    -- \ ] ~ *
    ctag = ctag:gsub("[\\%]~*]",
      function(x)
        return "\\" .. x
      end)
  end
  return ctag
end

function M.entry_to_location(entry, opts)
  local uri, line, col = entry:match("^(.*://.*):(%d+):(%d+):")
  line = line and tonumber(line) or 1
  col = col and tonumber(col) or 1
  if opts and opts.path_shorten then
    uri = uri:match("^.*://") .. M.lengthen(uri:match("^.*://(.*)"))
  end
  return {
    stripped = entry,
    line = line,
    col = col,
    uri = uri,
    range = {
      start = {
        line = line - 1,
        character = col - 1,
      }
    }
  }
end

function M.entry_to_file(entry, opts, force_uri)
  opts = opts or {}
  local cwd = opts.cwd
  -- Remove ansi coloring and prefixed icons
  entry = utils.strip_ansi_coloring(entry)
  local stripped, idx = stripBeforeLastOccurrenceOf(entry, utils.nbsp)
  stripped = M.tilde_to_HOME(stripped)
  local isURI = stripped:match("^%a+://")
  -- Prepend cwd before constructing the URI (#341)
  if cwd and #cwd > 0 and not isURI and
      not M.starts_with_separator(stripped) then
    stripped = M.join({ cwd, stripped })
  end
  -- #336: force LSP jumps using 'vim.lsp.util.jump_to_location'
  -- so that LSP entries are added to the tag stack
  if not isURI and force_uri then
    isURI = true
    stripped = "file://" .. stripped
  end
  -- entries from 'buffers' contain '[<bufnr>]'
  -- buffer placeholder always comes before the nbsp
  local bufnr = idx > 1 and entry:sub(1, idx):match("%[(%d+)") or nil
  if isURI and not bufnr then
    -- Issue #195, when using nvim-jdtls
    -- https://github.com/mfussenegger/nvim-jdtls
    -- LSP entries inside .jar files appear as URIs
    -- 'jdt://' which can then be opened with
    -- 'vim.lsp.util.jump_to_location' or
    -- 'lua require('jdtls').open_jdt_link(vim.fn.expand('jdt://...'))'
    -- Convert to location item so we can use 'jump_to_location'
    -- This can also work with any 'file://' prefixes
    return M.entry_to_location(stripped, opts)
  end
  local s = utils.strsplit(stripped, ":")
  if not s[1] then return {} end
  local file = s[1]
  local line = tonumber(s[2])
  local col  = tonumber(s[3])
  -- if the filename contains ':' we will have the wrong filename.
  -- test for existence on the longest possible match on the file
  -- system so we can accept files that end with ':', for example:
  --   file.ext:1
  --   file.ext:1:2
  --   file.ext:1:2:3
  -- the only usecase where this would fail would be when grep'ing,
  -- if the contents of the file starts with '%d' without indents
  -- AND the match line:col+text would match an existing file.
  -- Probably not great for performance but this function only gets
  -- called within previews/actions so it's not that bad (#453)
  if #s > 1 then
    local newfile = file
    for i = 2, #s do
      newfile = ("%s:%s"):format(newfile, s[i])
      if vim.loop.fs_stat(newfile) then
        file = newfile
        line = s[i + 1]
        col = s[i + 2]
      end
    end
  end
  local terminal
  if bufnr then
    terminal = utils.is_term_buffer(bufnr)
    if terminal then
      file, line = stripped:match("([^:]+):(%d+)")
    end
  end
  if opts.path_shorten then
    file = M.lengthen(file)
  end
  return {
    stripped = stripped,
    bufnr    = tonumber(bufnr),
    bufname  = bufnr and vim.api.nvim_buf_is_valid(tonumber(bufnr))
        and vim.api.nvim_buf_get_name(tonumber(bufnr)),
    terminal = terminal,
    path     = file,
    line     = tonumber(line) or 1,
    col      = tonumber(col) or 1,
  }
end

function M.git_cwd(cmd, opts)
  -- backward compat, used to be single cwd param
  local o = opts or {}
  if type(o) == "string" then
    o = { cwd = o }
  end
  local git_args = {
    { "cwd",          "-C" },
    { "git_dir",      "--git-dir" },
    { "git_worktree", "--work-tree" },
  }
  if type(cmd) == "string" then
    local args = ""
    for _, a in ipairs(git_args) do
      if o[a[1]] then
        o[a[1]] = vim.fn.expand(o[a[1]])
        args = args .. ("%s %s "):format(a[2], vim.fn.shellescape(o[a[1]]))
      end
    end
    cmd = cmd:gsub("^git ", "git " .. args)
  else
    local idx = 2
    cmd = utils.tbl_deep_clone(cmd)
    for _, a in ipairs(git_args) do
      if o[a[1]] then
        o[a[1]] = vim.fn.expand(o[a[1]])
        table.insert(cmd, idx, a[2])
        table.insert(cmd, idx + 1, o[a[1]])
        idx = idx + 2
      end
    end
  end
  return cmd
end

function M.is_git_repo(opts, noerr)
  return not not M.git_root(opts, noerr)
end

function M.git_root(opts, noerr)
  local cmd = M.git_cwd({ "git", "rev-parse", "--show-toplevel" }, opts)
  local output, err = utils.io_systemlist(cmd)
  if err ~= 0 then
    if not noerr then utils.info(unpack(output)) end
    return nil
  end
  return output[1]
end

return M
