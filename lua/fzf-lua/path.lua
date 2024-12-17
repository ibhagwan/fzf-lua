local uv = vim.uv or vim.loop
local utils = require "fzf-lua.utils"
local libuv = require "fzf-lua.libuv"
local string_sub = string.sub
local string_byte = string.byte

local M = {}

M.dot_byte = string_byte(".")
M.colon_byte = string_byte(":")
M.fslash_byte = string_byte("/")
M.bslash_byte = string_byte([[\]])

---@param path string?
---@return string
M.separator = function(path)
  -- auto-detect separator from fully qualified paths, e.g. "C:\..." or "~/..."
  if utils.__IS_WINDOWS and path then
    local maybe_separators = { string_byte(path, 3), string_byte(path, 2) }
    for _, s in ipairs(maybe_separators) do
      if M.byte_is_separator(s) then
        return string.char(s)
      end
    end
  end
  return string.char(utils._if_win(M.bslash_byte, M.fslash_byte))
end

M.separator_byte = function(path)
  return string_byte(M.separator(path), 1)
end

---@param byte number
---@return boolean
M.byte_is_separator = function(byte)
  if utils.__IS_WINDOWS then
    -- path on windows can also be the result of `vim.fs.normalize`
    -- so we need to test for the presence of both slash types
    return byte == M.bslash_byte or byte == M.fslash_byte
  else
    return byte == M.fslash_byte
  end
end

M.is_separator = function(c)
  return M.byte_is_separator(string_byte(c, 1))
end

---@param path string
---@return boolean
M.ends_with_separator = function(path)
  return M.byte_is_separator(string_byte(path, #path))
end

---@param path string
---@return string
function M.add_trailing(path)
  if M.ends_with_separator(path) then
    return path
  end
  return path .. M.separator(path)
end

---@param path string
---@return string
function M.remove_trailing(path)
  while M.ends_with_separator(path) do
    path = path:sub(1, #path - 1)
  end
  return path
end

---@param path string
---@return boolean
M.is_absolute = function(path)
  return utils._if_win(
    string_byte(path, 2) == M.colon_byte,
    string_byte(path, 1) == M.fslash_byte)
end

---@param path string
---@return boolean
M.has_cwd_prefix = function(path)
  return #path > 1
      and string_byte(path, 1) == M.dot_byte
      and M.byte_is_separator(string_byte(path, 2))
end

---@param path string
---@return string
M.strip_cwd_prefix = function(path)
  if M.has_cwd_prefix(path) then
    return #path > 2 and path:sub(3) or ""
  else
    return path
  end
end

---Get the basename|tail of the given path.
---@param path string
---@return string
function M.tail(path)
  local end_idx = M.ends_with_separator(path) and #path - 1 or #path
  for i = end_idx, 1, -1 do
    if M.byte_is_separator(string_byte(path, i)) then
      return path:sub(i + 1)
    end
  end
  return path
end

M.basename = M.tail

---Get the path to the parent directory of the given path.
-- Returns `nil` if the path has no parent.
---@param path string
---@param remove_trailing boolean
---@return string?
function M.parent(path, remove_trailing)
  path = M.remove_trailing(path)
  for i = #path, 1, -1 do
    if M.byte_is_separator(string_byte(path, i)) then
      local parent = path:sub(1, i)
      if remove_trailing then
        parent = M.remove_trailing(parent)
      end
      return parent
    end
  end
end

---@param path string
---@return string
function M.normalize(path)
  local p = M.tilde_to_HOME(path)
  if utils.__IS_WINDOWS then
    p = p:gsub([[\]], [[/]])
  end
  return p
end

---@param p1 string
---@param p2 string
---@return boolean
function M.equals(p1, p2)
  p1 = M.normalize(M.remove_trailing(p1))
  p2 = M.normalize(M.remove_trailing(p2))
  if utils.__IS_WINDOWS then
    p1 = string.lower(p1)
    p2 = string.lower(p2)
  end
  return p1 == p2
end

---@param path string
---@param relative_to string
---@return boolean, string?
function M.is_relative_to(path, relative_to)
  -- make sure paths end with a separator
  local path_no_trailing = M.tilde_to_HOME(path)
  path = M.add_trailing(path_no_trailing)
  relative_to = M.add_trailing(M.tilde_to_HOME(relative_to))
  local pidx, ridx = 1, 1
  repeat
    local pbyte = string.byte(path, pidx)
    local rbyte = string.byte(relative_to, ridx)
    if M.byte_is_separator(pbyte) and M.byte_is_separator(rbyte) then
      -- both path and relative_to have a separator part
      -- which may differ in length if there are multiple
      -- separators, e.g. "/some/path" and "//some//path"
      repeat
        pidx = pidx + 1
      until not M.byte_is_separator(string.byte(path, pidx))
      repeat
        ridx = ridx + 1
      until not M.byte_is_separator(string.byte(relative_to, ridx))
    elseif utils.__IS_WINDOWS and pbyte and rbyte
        -- case insensitive matching on windows
        and string.char(pbyte):lower() == string.char(rbyte):lower()
        -- byte matching on Unix/BSD
        or pbyte == rbyte then
      -- character matches, move to next
      pidx = pidx + 1
      ridx = ridx + 1
    else
      -- characters don't match
      return false, nil
    end
  until ridx > #relative_to
  return true, pidx <= #path_no_trailing and path_no_trailing:sub(pidx) or "."
end

---Get a path relative to another path.
---@param path string
---@param relative_to string
---@return string
function M.relative_to(path, relative_to)
  local is_relative_to, relative_path = M.is_relative_to(path, relative_to)
  return is_relative_to and relative_path or path
end

---@param path string
---@return string?
function M.extension(path, no_tail)
  local file = no_tail and path or M.tail(path)
  for i = #file, 1, -1 do
    if string_byte(file, i) == M.dot_byte then
      return file:sub(i + 1)
    end
  end
end

---@param paths string[]
---@return string
function M.join(paths)
  -- Separator is always / (even on windows) unless we
  -- detect it from fully qualified paths, e.g. "C:\..."
  local separator = M.separator(paths[1])
  local ret = ""
  for i = 1, #paths do
    local p = paths[i]
    if p then
      if i < #paths and not M.ends_with_separator(p) then
        p = p .. separator
      end
      ret = ret .. p
    end
  end
  return ret
end

-- I'm not sure why this happens given that neovim is single threaded
-- but it seems that 'oldfiles' provider processing entries concurrently
-- crashes when trying to access `vim.env.HOME' from two different entries
-- at the same time due to being run in a coroutine (#447)
M.HOME = function()
  if not M.__HOME then
    -- use 'os.getenv' instead of 'vim.env' due to (#452):
    -- E5560: nvim_exec must not be called in a lua loop callback
    M.__HOME = utils._if_win(os.getenv("USERPROFILE"), os.getenv("HOME"))
  end
  return M.__HOME
end

---@param path string?
---@return string?
function M.tilde_to_HOME(path)
  return path and path:gsub("^~", M.HOME()) or nil
end

---@param path string?
---@return string?
function M.HOME_to_tilde(path)
  if not path then return end
  if utils.__IS_WINDOWS then
    local home = M.HOME()
    if path:sub(1, #home):lower() == home:lower() then
      path = "~" .. path:sub(#home + 1)
    end
  else
    path = path:gsub("^" .. utils.lua_regex_escape(M.HOME()), "~")
  end
  return path
end

local function find_next_separator(str, start_idx)
  local SEPARATOR_BYTES = utils._if_win(
    { M.fslash_byte, M.bslash_byte }, { M.fslash_byte })
  for i = start_idx or 1, #str do
    for _, byte in ipairs(SEPARATOR_BYTES) do
      if string_byte(str, i) == byte then
        return i
      end
    end
  end
end

local function utf8_char_len(s, i)
  -- Get byte count of unicode character (RFC 3629)
  local c = string_byte(s, i or 1)
  if not c then
    return
  elseif c > 0 and c <= 127 then
    return 1
  elseif c >= 194 and c <= 223 then
    return 2
  elseif c >= 224 and c <= 239 then
    return 3
  elseif c >= 240 and c <= 244 then
    return 4
  end
end

local function utf8_sub(s, from, to)
  local ret = ""
  -- NOTE: this function is called from shorten right after finding the next
  -- separaor that means `from` is a byte index and **NOT** a UTF8 char index
  -- Advance to first requested UTF8 character index
  -- local byte_i, utf8_i = 1, 1
  -- while byte_i <= #s and utf8_i < from do
  --   byte_i = byte_i + utf8_char_len(s, byte_i)
  --   utf8_i = utf8_i + 1
  -- end
  local byte_i, utf8_i = from, from
  -- Concat utf8 chars until "to" or end of string
  while byte_i <= #s and (not to or utf8_i <= to) do
    local c_len = utf8_char_len(s, byte_i)
    local c = string_sub(s, byte_i, byte_i + c_len - 1)
    ret = ret .. c
    byte_i = byte_i + c_len
    utf8_i = utf8_i + 1
  end
  return ret
end

function M.shorten(path, max_len, sep)
  -- caller can specify what separator to use
  sep = sep or M.separator(path)
  local parts = {}
  local start_idx = 1
  max_len = max_len and tonumber(max_len) > 0 and max_len or 1
  if utils.__IS_WINDOWS and M.is_absolute(path) then
    -- do not shorten "C:\" to "C", for glob to succeed
    -- we need the paths to start with a valid drive spec
    table.insert(parts, path:sub(1, 2))
    start_idx = 4
  end
  repeat
    local i = find_next_separator(path, start_idx)
    local end_idx = i and start_idx + math.min(i - start_idx, max_len) - 1 or nil
    local part = utf8_sub(path, start_idx, end_idx)
    if end_idx and part == "." and i - start_idx > 1 then
      part = utf8_sub(path, start_idx, end_idx + 1)
    end
    table.insert(parts, part)
    if i then start_idx = i + 1 end
  until not i
  return table.concat(parts, sep)
end

function M.lengthen(path)
  -- we use 'glob_escape' to escape \{} (#548)
  local separator = M.separator(path)
  local glob_expr = utils.glob_escape(path)
  local glob_expr_prefix = ""
  if M.is_absolute(path) then
    -- don't prefix with * the leading / on UNIX or C:\ on windows
    if utils.__IS_WINDOWS then
      glob_expr_prefix = glob_expr:sub(1, 3)
      glob_expr = glob_expr:sub(4)
    else
      glob_expr_prefix = glob_expr:sub(1, 1)
      glob_expr = glob_expr:sub(2)
    end
  end
  -- replace separator with wildcard + separator
  glob_expr = glob_expr_prefix .. glob_expr:gsub(separator, "%*" .. separator)
  return vim.fn.glob(glob_expr):match("[^\n]+")
      -- or string.format("<glob expand failed for '%s'>", path)
      or string.format("<glob expand failed for '%s'>", glob_expr)
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
  local ctag = entry:match("%:.-[/\\]^?\t?(.*)[/\\]")
  -- if tag name contains a slash we could
  -- have the wrong match, most tags start
  -- with ^ so try to match based on that
  ctag = ctag and ctag:match("[/\\]^(.*)") or ctag
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
  line = line and tonumber(line) > 0 and tonumber(line) or 1
  col = col and tonumber(col) > 0 and tonumber(col) or 1
  if opts.path_shorten and uri:match("file://") then
    uri = "file://" .. M.lengthen(uri:sub(8))
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
  if opts._fmt then
    if type(opts._fmt._from) == "function" then
      entry = opts._fmt._from(entry, opts)
    end
    if type(opts._fmt.from) == "function" then
      entry = opts._fmt.from(entry, opts)
    end
  end
  -- Remove ansi coloring and prefixed icons
  entry = utils.strip_ansi_coloring(entry)
  local stripped, idx = stripBeforeLastOccurrenceOf(entry, utils.nbsp)
  stripped = M.tilde_to_HOME(stripped)
  local isURI = stripped:match("^%a+://")
  -- Prepend cwd before constructing the URI (#341)
  if cwd and #cwd > 0 and not isURI and not M.is_absolute(stripped) then
    stripped = M.join({ cwd, stripped })
  end
  -- #336: force LSP jumps using 'vim.lsp.util.show_document'
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
    -- 'vim.lsp.util.show_document' or
    -- 'lua require('jdtls').open_jdt_link(vim.fn.expand('jdt://...'))'
    -- Convert to location item so we can use 'jump_to_location'
    -- This can also work with any 'file://' prefixes
    return M.entry_to_location(stripped, opts)
  end
  local s = utils.strsplit(stripped, ":")
  if not s[1] then return {} end
  if utils.__IS_WINDOWS and M.is_absolute(stripped) then
    -- adjust split for "C:\..."
    s[1] = s[1] .. ":" .. s[2]
    table.remove(s, 2)
  end
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
      if uv.fs_stat(newfile) then
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
  if opts.path_shorten and not stripped:match("^%a+://") then
    file = M.lengthen(file)
  end
  return {
    stripped = stripped,
    bufnr    = tonumber(bufnr),
    bufname  = bufnr and vim.api.nvim_buf_is_valid(tonumber(bufnr))
        and vim.api.nvim_buf_get_name(tonumber(bufnr)),
    terminal = terminal,
    path     = file,
    line     = tonumber(line) or 0,
    col      = tonumber(col) or 0,
    ctag     = opts._ctag and M.entry_to_ctag(stripped) or nil,
  }
end

function M.git_cwd(cmd, opts)
  -- backward compat, used to be single cwd param
  -- NOTE: we use deepcopy due to a bug with Windows network drives starting with "\\"
  -- as `vim.fn.expand` would reduce the double slash to a single slash modifying the
  -- original `opts.cwd` ref (#1429)
  local o = opts and utils.tbl_deep_clone(opts) or {}
  if type(o) == "string" then
    o = { cwd = o }
  end
  local git_args = {
    { "cwd",          "-C" },
    { "git_dir",      "--git-dir" },
    { "git_worktree", "--work-tree" },
    { "git_config",   "-c",         noexpand = true },
  }
  if type(cmd) == "string" then
    local args = ""
    for _, a in ipairs(git_args) do
      if o[a[1]] then
        o[a[1]] = a.noexpand and o[a[1]] or libuv.expand(o[a[1]])
        args = args .. ("%s %s "):format(a[2], libuv.shellescape(o[a[1]]))
      end
    end
    cmd = cmd:gsub("^git ", "git " .. args)
  else
    local idx = 2
    cmd = utils.tbl_deep_clone(cmd)
    for _, a in ipairs(git_args) do
      if o[a[1]] then
        o[a[1]] = a.noexpand and o[a[1]] or libuv.expand(o[a[1]])
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

function M.keymap_to_entry(str, opts)
  local valid_modes = {
    n = true,
    i = true,
    c = true,
    v = true,
    t = true,
  }
  local mode, keymap = string.match(str, "^(.-)│(.-)│")
  if not mode or not keymap then return {} end
  mode, keymap = vim.trim(mode), vim.trim(keymap)
  mode = valid_modes[mode] and mode or "" -- only valid modes
  local vmap = utils.strsplit(
    vim.fn.execute(string.format("verbose %smap %s", mode, keymap)), "\n")[1]
  local out = utils.strsplit(vmap, "\n")
  local entry
  for i = #out, 1, -1 do
    if out[i]:match(utils.lua_regex_escape(keymap)) then
      entry = out[i]:match("<.-:%s+(.*)>")
    end
  end
  return entry and M.entry_to_file(entry, opts) or { mode = mode, key = keymap, vmap = vmap } or {}
end

-- Minimal functionality so we can hijack during `vim.filetype.match`
-- As of neovim 0.10 we only need to implement mode ":t"
M._fnamemodify = function(fname, mods)
  if mods == ":t" then
    return M.tail(fname)
  end
  if mods == ":r" then
    local tail = M.tail(fname)
    return tail and tail[1] ~= "." and (fname:gsub("%.[^.]*$", "")) or tail
  end
  return fname
end

M._env = setmetatable({}, {
  __index = function(_, index)
    return os.getenv(index)
  end
})

M._nvim_buf_get_lines = function() return {} end
M._nvim_buf_line_count = function() return 0 end

function M.ft_match(args)
  if not args or not args.filename then
    error('At least "filename" needs to be specified')
  end

  -- NOTE: code for `vim.filetype.match` is in "runtime/lua/vim/filetype.lua"
  -- Hijack `vim.env` and `vim.fn.fnamemodify` in order to circumvent
  -- E5560: Vimscript function must not be called in a lua loop callback
  local _env = vim.env
  local _fnamemodify = vim.fn.fnamemodify
  local _nvim_buf_get_lines = vim.api.nvim_buf_get_lines
  local _nvim_buf_line_count = vim.api.nvim_buf_line_count
  vim.env = M._env
  vim.fn.fnamemodify = M._fnamemodify
  vim.api.nvim_buf_get_lines = M._nvim_buf_get_lines
  vim.api.nvim_buf_line_count = M._nvim_buf_line_count
  -- Normalize the path and replace "~" to prevent the internal
  -- `normalize_path` from having to call `vim.env` or `vim.pesc`
  local fname = M.normalize(M.tilde_to_HOME(args.filename))
  local ok, ft, on_detect = pcall(vim.filetype.match, { filename = fname, buf = 0 })
  vim.api.nvim_buf_get_lines = _nvim_buf_get_lines
  vim.api.nvim_buf_line_count = _nvim_buf_line_count
  vim.fn.fnamemodify = _fnamemodify
  vim.env = _env
  if ok then return ft, on_detect end
end

return M
