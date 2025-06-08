-- help to inspect results, e.g.:
-- ':lua _G.dump(vim.fn.getwininfo())'
-- use ':messages' to see the dump
function _G.dump(...)
  local objects = vim.tbl_map(vim.inspect, { ... })
  print(unpack(objects))
end

local uv = vim.uv or vim.loop

local M = {}

M.__HAS_NVIM_010 = vim.fn.has("nvim-0.10") == 1
M.__HAS_NVIM_0102 = vim.fn.has("nvim-0.10.2") == 1
M.__HAS_NVIM_011 = vim.fn.has("nvim-0.11") == 1
M.__IS_WINDOWS = vim.fn.has("win32") == 1 or vim.fn.has("win64") == 1
-- `:help shellslash` (for more info see #1055)
M.__WIN_HAS_SHELLSLASH = M.__IS_WINDOWS and vim.fn.exists("+shellslash")

function M.__FILE__() return debug.getinfo(2, "S").source end

function M.__LINE__() return debug.getinfo(2, "l").currentline end

function M.__FNC__() return debug.getinfo(2, "n").name end

-- current function ref, since `M.__FNCREF__` is itself a function
-- we need to go backwards once in stack (i.e. "2")
function M.__FNCREF__() return debug.getinfo(2, "f").func end

-- calling function ref, go backwards in stack twice first
-- out of `utils.__FNCREF2__`, second out of calling function
function M.__FNCREF2__()
  local dbginfo = debug.getinfo(3, "f")
  return dbginfo and dbginfo.func
end

function M.__FNCREF3__()
  local dbginfo = debug.getinfo(4, "f")
  return dbginfo and dbginfo.func
end

-- sets an invisible unicode character as icon separator
-- the below was reached after many iterations, a short summary of everything
-- that was tried and why it failed:
--
-- nbsp, U+00a0: the original separator, fails with files that contain nbsp
-- nbsp + zero-width space (U+200b): works only with `sk` (`fzf` shows <200b>)
-- word joiner (U+2060): display works fine, messes up fuzzy search highlights
-- line separator (U+2028), paragraph separator (U+2029): created extra space
-- EN space (U+2002): seems to work well
--
-- For more unicode SPACE options see:
-- http://unicode-search.net/unicode-namesearch.pl?term=SPACE&.submit=Search

-- DO NOT USE "\u{}" escape, fails with "invalid escape sequence" if Lua < 5.3
-- "\x" escape sequence requires Lua 5.2/LuaJIT, for Lua 5.1 compatibility we
-- use a literal backslash with the long string format `[[\x]]` to be replaced
-- later with `string.char(tonumber(x, 16))`
-- https://stackoverflow.com/questions/29966782/\
--    how-to-embed-hex-values-in-a-lua-string-literal-i-e-x-equivalent
-- M.nbsp = [[\xc2\xa0]]  -- "\u{00a0}"
M.nbsp = [[\xe2\x80\x82]] -- "\u{2002}"

-- Lua 5.1 compatibility
if _VERSION and type(_VERSION) == "string" then
  local ver = tonumber(_VERSION:match("%d+.%d+"))
  if ver < 5.2 then
    M.nbsp = M.nbsp:gsub("\\x(%x%x)",
      function(x)
        return string.char(tonumber(x, 16))
      end)
  end
end

M._if_win = function(a, b)
  if M.__IS_WINDOWS then
    return a
  else
    return b
  end
end

-- Substitute unix style $VAR with
--   Style 1: %VAR%
--   Style 2: !VAR!
M._if_win_normalize_vars = function(cmd, style)
  if not M.__IS_WINDOWS then return cmd end
  local expander = style == 2 and "!" or "%"
  cmd = cmd:gsub("%$[^%s]+", function(x) return expander .. x:sub(2) .. expander end)
  if style == 2 then
    -- also sub %VAR% for !VAR!
    cmd = cmd:gsub("%%[^%s]+%%", function(x) return "!" .. x:sub(2, #x - 1) .. "!" end)
  end
  return cmd
end

M.shell_nop = function()
  return M._if_win("break", "true")
end

---@param vars table
---@return table
M.shell_setenv_str = function(vars)
  local ret = {}
  for k, v in pairs(vars or {}) do
    table.insert(ret, M._if_win(
      string.format([[set %s=%s&&]], tostring(k), tostring(v)),
      string.format("%s=%s;", tostring(k), tostring(v))
    ))
  end
  return ret
end

---@param inputstr string
---@param sep string
---@return string[]
M.strsplit = function(inputstr, sep)
  local t = {}
  local s, m, r = inputstr, nil, nil
  repeat
    m, r = s:match("^(.-)" .. sep .. "(.*)$")
    s = r and r or s
    table.insert(t, m or s)
  until not m
  return t
end

function M.round(num, limit)
  if not num then return nil end
  if not limit then limit = 0.5 end
  local fraction = num - math.floor(num)
  if fraction > limit then return math.ceil(num) end
  return math.floor(num)
end

function M.nvim_has_option(option)
  return vim.fn.exists("&" .. option) == 1
end

local fast_event_aware_notify = function(msg, level, opts)
  if vim.in_fast_event() then
    vim.schedule(function()
      vim.notify("[Fzf-lua] " .. msg, level, opts)
    end)
  else
    vim.notify("[Fzf-lua] " .. msg, level, opts)
  end
end

function M.info(msg)
  fast_event_aware_notify(msg, vim.log.levels.INFO, {})
end

function M.warn(msg)
  fast_event_aware_notify(msg, vim.log.levels.WARN, {})
end

function M.err(msg)
  fast_event_aware_notify(msg, vim.log.levels.ERROR, {})
end

function M.is_darwin()
  return uv.os_uname().sysname == "Darwin"
end

---@param str string
---@return string
function M.rg_escape(str)
  if not str then return str end
  -- [(~'"\/$?'`*&&||;[]<>)]
  -- escape "\~$?*|[()^-."
  local ret = str:gsub("[\\~$?*|{\\[()^%-%.%+]", function(x)
        return "\\" .. x
      end)
      -- Escape newline (#1203) at the end so we
      -- don't end up escaping the backslash twice
      :gsub("\n", "\\n")
  return ret
end

function M.regex_to_magic(str)
  -- Convert regex to "very magic" pattern, basically a regex
  -- with special meaning for "=&<>", `:help /magic`
  return [[\v]] .. str:gsub("[=&@<>]", function(x)
    return "\\" .. x
  end)
end

function M.ctag_to_magic(str)
  return [[\v]] .. str:gsub("[=&@<>{%(%)%.%[]", function(x) return [[\]] .. x end)
end

function M.sk_escape(str)
  if not str then return str end
  return str:gsub('["`]', function(x)
    return "\\" .. x
  end):gsub([[\\]], [[\\\\]]):gsub([[\%$]], [[\\\$]])
end

function M.lua_escape(str)
  if not str then return str end
  return str:gsub("[%%]", function(x)
    return "%" .. x
  end)
end

---@see vim.pesc
function M.lua_regex_escape(str)
  -- escape all lua special chars
  -- ( ) % . + - * [ ? ^ $
  if not str then return nil end
  -- gsub returns a tuple, return the string only or unexpected happens (#1257)
  return (str:gsub("[%(%)%.%%%+%-%*%?%[%]%^%$]", "%%%1"))
end

function M.glob_escape(str)
  if not str then return str end
  return str:gsub("[%{}[%]]", function(x)
    return [[\]] .. x
  end)
end

function M.pcall_expand(filepath)
  -- expand using pcall, this is a workaround to trying to
  -- expand certain special chars, more info in issue #285
  -- expanding the below fails with:
  -- "special[1][98f3a7e3-0d6e-f432-8a18-e1144b53633f][-1].xml"
  --  "Vim:E944: Reverse range in character class"
  -- this seems to fail with only a single hyphen:
  -- :lua print(vim.fn.expand("~/file[2-1].ext"))
  -- but not when escaping the hyphen:
  -- :lua print(vim.fn.expand("~/file[2\\-1].ext"))
  local ok, expanded = pcall(vim.fn.expand, filepath:gsub("%-", "\\-"))
  if ok and expanded and #expanded > 0 then
    return expanded
  else
    return filepath
  end
end

-- TODO: why does `file --dereference --mime` return
-- wrong result for some lua files ('charset=binary')?
M.file_is_binary = function(filepath)
  filepath = M.pcall_expand(filepath)
  if vim.fn.executable("file") ~= 1 or
      not uv.fs_stat(filepath) then
    return false
  end
  local out = M.io_system({ "file", "--dereference", "--mime", filepath })
  return out:match("charset=binary") ~= nil
end

local S_IFMT = 0xF000  -- filetype mask
local S_IFIFO = 0x1000 -- fifo
local S_IFDIR = 0x4000 -- directory

M.path_is_directory = function(filepath, stat)
  if stat == nil then
    stat = uv.fs_stat(filepath)
  end
  if stat and bit.band(stat.mode, S_IFMT) == S_IFDIR then
    return true
  end
  return false
end

M.file_is_fifo = function(filepath, stat)
  if stat == nil then
    stat = uv.fs_stat(filepath)
  end
  if stat and bit.band(stat.mode, S_IFMT) == S_IFIFO then
    return true
  end
  return false
end

M.file_is_readable = function(filepath)
  local fd = uv.fs_open(filepath, "r", 438)
  if fd then
    uv.fs_close(fd)
    return true
  end
  return false
end

M.perl_file_is_binary = function(filepath)
  filepath = M.pcall_expand(filepath)
  if vim.fn.executable("perl") ~= 1 or
      not uv.fs_stat(filepath) then
    return false
  end
  -- can also use '-T' to test for text files
  -- `perldoc -f -x` to learn more about '-B|-T'
  local _, rc = M.io_system({ "perl", "-E", "exit((-B $ARGV[0])?0:1);", filepath })
  return rc == 0
end

M.read_file = function(filepath)
  local fd = uv.fs_open(filepath, "r", 438)
  if fd == nil then return "" end
  local stat = assert(uv.fs_fstat(fd))
  if stat.type ~= "file" then return "" end
  local data = assert(uv.fs_read(fd, stat.size, 0))
  assert(uv.fs_close(fd))
  return data
end

M.read_file_async = function(filepath, callback)
  uv.fs_open(filepath, "r", 438, function(err_open, fd)
    if err_open then
      -- we must schedule this or we get
      -- E5560: nvim_exec must not be called in a lua loop callback
      vim.schedule(function()
        M.warn(("Unable to open file '%s', error: %s"):format(filepath, err_open))
      end)
      return
    end
    uv.fs_fstat(fd, function(err_fstat, stat)
      assert(not err_fstat, err_fstat)
      if stat.type ~= "file" then return callback("") end
      uv.fs_read(fd, stat.size, 0, function(err_read, data)
        assert(not err_read, err_read)
        uv.fs_close(fd, function(err_close)
          assert(not err_close, err_close)
          return callback(data)
        end)
      end)
    end)
  end)
end

-- deepcopy can fail with: "Cannot deepcopy object of type userdata" (#353)
-- this can happen when copying items/on_choice params of vim.ui.select
-- run in a pcall and fallback to our poor man's clone
function M.deepcopy(t)
  local ok, res = pcall(vim.deepcopy, t)
  if ok then
    return res
  else
    return M.tbl_deep_clone(t)
  end
end

function M.tbl_deep_clone(t)
  if not t then return end
  local clone = {}

  for k, v in pairs(t) do
    if type(v) == "table" then
      clone[k] = M.tbl_deep_clone(v)
    else
      clone[k] = v
    end
  end

  return clone
end

-- Similar to `vim.tbl_deep_extend`
-- Recursively merge two or more tables by extending
-- the first table and returning its original pointer
---@param behavior "keep"|"force"|"error"
---@rerurn table
function M.tbl_deep_extend(behavior, ...)
  local tbls = { ... }
  local ret = tbls[1]
  for i = 2, #tbls do
    local t = tbls[i]
    for k, v in pairs(t) do
      ret[k] = (function()
        if type(v) == table then
          return M.tbl_deep_extend(behavior, ret[k] or {}, v)
        elseif behavior == "force" then
          return v
        elseif behavior == "keep" then
          if ret[k] ~= nil then
            return ret[k]
          else
            return v
          end
        elseif behavior == "error" then
          error(string.format("key '%s' found in more than one map", k))
        else
          error(string.format("invalid behavior '%s'", behavior))
        end
      end)()
    end
  end
  return ret
end

---@diagnostic disable-next-line: deprecated
M.tbl_islist = vim.islist or vim.tbl_islist

function M.tbl_isempty(T)
  assert(type(T) == "table", string.format("Expected table, got %s", type(T)))
  return next(T) == nil
end

function M.tbl_count(T)
  local count = 0
  for _ in pairs(T) do count = count + 1 end
  return count
end

function M.tbl_join(t1, t2)
  for _, v in ipairs(t2) do
    table.insert(t1, v)
  end
  return t1
end

function M.tbl_contains(T, value)
  for _, v in ipairs(T) do
    if v == value then
      return true
    end
  end
  return false
end

function M.tbl_flatten(T)
  if vim.iter then
    return vim.iter(T):flatten(math.huge):totable()
  else
    ---@diagnostic disable-next-line: deprecated
    return vim.tbl_flatten(T)
  end
end

function M.tbl_get(T, ...)
  local keys = { ... }
  if #keys == 0 then
    return nil
  end
  return M.map_get(T, keys)
end

-- Get map value from string key
-- e.g. `map_get(m, "key.sub1.sub2")`
--      `map_get(m, { "key", "sub1", "sub2" })`
function M.map_get(m, k)
  if not m then return end
  if not k then return m end
  local keys = type(k) == "table" and k or M.strsplit(k, "%.")
  local iter = m
  for i = 1, #keys do
    iter = iter[keys[i]]
    if i == #keys then
      return iter
    elseif type(iter) ~= "table" then
      break
    end
  end
end

-- Set map value for string key
-- e.g. `map_set(m, "key.sub1.sub2", value)`
--      `map_set(m, { "key", "sub1", "sub2" }, value)`
-- if need be, build map tree as we go along
---@param m table?
---@param k string
---@param v unknown
---@return table<string, unknown>
function M.map_set(m, k, v)
  m = m or {}
  local keys = type(k) == "table" and k or M.strsplit(k, "%.")
  local map = m
  for i = 1, #keys do
    local key = keys[i]
    if i == #keys then
      map[key] = v
    else
      map[key] = type(map[key]) == "table" and map[key] or {}
      map = map[key]
    end
  end
  return m
end

---@param m table<string, unknown>?
---@return table<string, unknown>?
function M.map_tolower(m, exclude_patterns)
  -- We use "exclude_patterns" to filter "alt-{a|A}"
  -- as it's a valid and different fzf bind
  exclude_patterns = type(exclude_patterns) == "table" and exclude_patterns
      or type(exclude_patterns) == "string" and { exclude_patterns }
      or {}
  if not m then
    return
  end
  local ret = {}
  for k, v in pairs(m) do
    local lower_k = (function()
      for _, p in ipairs(exclude_patterns) do
        if k:match(p) then return k end
      end
      return k:lower()
    end)()
    ret[lower_k] = v
  end
  return ret
end

-- Flatten map's keys recursively
--   { a = { a1 = ..., a2 = ... } }
-- will be transformed to:
--   {
--     ["a.a1"] = ...,
--     ["a.a2"] = ...,
--   }
---@param m table<string, unknown>?
---@return table<string, unknown>?
function M.map_flatten(m, prefix)
  if M.tbl_isempty(m) then return {} end
  local ret = {}
  prefix = prefix and string.format("%s.", prefix) or ""
  for k, v in pairs(m) do
    if type(v) == "table" and not v[1] then
      local inner = M.map_flatten(v)
      for ki, vi in pairs(inner) do
        ret[prefix .. k .. "." .. ki] = vi
      end
    else
      ret[prefix .. k] = v
    end
  end
  return ret
end

local function hex2rgb(hexcol)
  local r, g, b = hexcol:match("#(%x%x)(%x%x)(%x%x)")
  if not r or not g or not b then return end
  r, g, b = tonumber(r, 16), tonumber(g, 16), tonumber(b, 16)
  return r, g, b
end

-- auto generate ansi escape sequence from RGB or neovim highlights
--[[ M.ansi_auto = setmetatable({}, {
  -- __index metamethod only gets called when the item does not exist
  -- we use this to auto-cache the ansi escape sequence
  __index = function(self, k)
    print("get", k)
    local escseq
    -- if not an existing highlight group lookup
    -- in the neovim colormap and convert to RGB
    if not k:match("^#") and vim.fn.hlexists(k) ~= 1 then
      local col = M.COLORMAP()[k:sub(1, 1):upper() .. k:sub(2):lower()]
      if col then
        -- format as 6 digit hex for hex2rgb()
        k = ("#%06x"):format(col)
      end
    end
    if k:match("#%x%x%x%x%x%x") then -- index is RGB
      -- cache the sequence as all lowercase
      k = k:lower()
      local v = rawget(self, k)
      if v then return v end
      local r, g, b = hex2rgb(k)
      escseq = string.format("[38;2;%d;%d;%dm", r, g, b)
    else -- index is neovim hl
      _, escseq = M.ansi_from_hl(k, "foo")
      print("esc", k, escseq)
    end
    -- We always set the item, if not RGB and hl isn't valid
    -- create a dummy function that returns the string instead
    local v = type(escseq) == "string" and #escseq > 0
        and function(s)
          if type(s) ~= "string" or #s == 0 then return "" end
          return escseq .. s .. M.ansi_escseq.clear
        end
        or function(s) return s end
    rawset(self, k, v)
    return v
  end,
  __newindex = function(self, k, v)
    assert(false,
      string.format("modifying the ansi cache directly isn't allowed [index: %s]", k))
    -- rawset doesn't trigger __new_index, otherwise stack overflow
    -- we never get here but this masks the "unused local" warnings
    rawset(self, k, v)
  end
}) ]]

M.ansi_codes = {}
M.ansi_escseq = {
  -- the "\x1b" esc sequence causes issues
  -- with older Lua versions
  -- clear    = "\x1b[0m",
  clear     = "[0m",
  bold      = "[1m",
  italic    = "[3m",
  underline = "[4m",
  black     = "[0;30m",
  red       = "[0;31m",
  green     = "[0;32m",
  yellow    = "[0;33m",
  blue      = "[0;34m",
  magenta   = "[0;35m",
  cyan      = "[0;36m",
  white     = "[0;37m",
  grey      = "[0;90m",
  dark_grey = "[0;97m",
}

M.cache_ansi_escseq = function(name, escseq)
  M.ansi_codes[name] = function(string)
    if string == nil or #string == 0 then return "" end
    if not escseq or #escseq == 0 then return string end
    return escseq .. string .. M.ansi_escseq.clear
  end
end

-- Generate a cached ansi sequence function for all basic colors
for color, escseq in pairs(M.ansi_escseq) do
  M.cache_ansi_escseq(color, escseq)
end

-- Helper func to test for invalid (cleared) highlights
function M.is_hl_cleared(hl)
  local ok, hl_def = pcall(vim.api.nvim_get_hl, 0, { name = hl, link = false })
  if not ok or M.tbl_isempty(hl_def) then
    return true
  end
end

function M.COLORMAP()
  if not M.__COLORMAP then
    M.__COLORMAP = vim.api.nvim_get_color_map()
  end
  return M.__COLORMAP
end

local function synIDattr(hl, w, mode)
  -- Although help specifies invalid mode returns the active hlgroups
  -- when sending `nil` for mode the return value for "fg" is also nil
  return mode == "cterm" or mode == "gui"
      and vim.fn.synIDattr(vim.fn.synIDtrans(vim.fn.hlID(hl)), w, mode)
      or vim.fn.synIDattr(vim.fn.synIDtrans(vim.fn.hlID(hl)), w)
end

function M.hexcol_from_hl(hlgroup, what, mode)
  if not hlgroup or not what then return end
  local hexcol = synIDattr(hlgroup, what, mode)
  -- Without termguicolors hexcol returns `{ctermfg|ctermbg}` which is
  -- a simple number representing the term ANSI color (e.g. 1-15, etc)
  -- in which case we return the number as is so it can be passed onto
  -- fzf's "--color" flag, this shouldn't be an issue for `ansi_from_hl`
  -- as the function validates the a 6-digit hex number (#1422)
  if hexcol and not hexcol:match("^#") and not tonumber(hexcol) then
    -- try to acquire the color from the map
    -- some schemes don't capitalize first letter?
    local col = M.COLORMAP()[hexcol:sub(1, 1):upper() .. hexcol:sub(2)]
    if col then
      -- format as 6 digit hex for hex2rgb()
      hexcol = ("#%06x"):format(col)
    else
      -- some colorschemes set fg=fg/bg or bg=fg/bg which have no value
      -- in the colormap, in this case reset `hexcol` to prevent fzf to
      -- err with "invalid color specification: bg:bg" (#976)
      -- TODO: should we extract `fg|bg` from `Normal` hlgroup?
      hexcol = ""
    end
  end
  return hexcol
end

function M.ansi_from_rgb(rgb, s)
  local r, g, b = hex2rgb(rgb)
  if r and g and b then
    return string.format("[38;2;%d;%d;%dm%s%s", r, g, b, s, "[0m")
  elseif tonumber(rgb) then
    -- No termguicolors, use the number as is
    return string.format("[38;5;%dm%s%s", rgb, s, "[0m")
  end
  return s
end

function M.ansi_from_hl(hl, s)
  if not hl or #hl == 0 or vim.fn.hlexists(hl) ~= 1 then
    return s, nil
  end
  -- https://gist.github.com/fnky/458719343aabd01cfb17a3a4f7296797#rgb-colors
  -- Set foreground color as RGB: 'ESC[38;2;{r};{g};{b}m'
  -- Set background color as RGB: 'ESC[48;2;{r};{g};{b}m'
  local what = {
    ["fg"]            = { rgb = true, code = 38 },
    ["bg"]            = { rgb = true, code = 48 },
    ["bold"]          = { code = 1 },
    ["italic"]        = { code = 3 },
    ["underline"]     = { code = 4 },
    ["inverse"]       = { code = 7 },
    ["reverse"]       = { code = 7 },
    ["strikethrough"] = { code = 9 },
  }
  -- List of ansi sequences to apply
  local escseqs = {}
  for w, p in pairs(what) do
    if p.rgb then
      local hexcol = M.hexcol_from_hl(hl, w)
      local r, g, b = hex2rgb(hexcol)
      if r and g and b then
        table.insert(escseqs, string.format("[%d;2;%d;%d;%dm", p.code, r, g, b))
        -- elseif #hexcol>0 then
        --   print("unresolved", hl, w, hexcol, M.COLORMAP()[synIDattr(hl, w)])
      elseif tonumber(hexcol) then
        -- No termguicolors, use the number as is
        table.insert(escseqs, string.format("[%d;5;%dm", p.code, tonumber(hexcol)))
      end
    else
      local value = synIDattr(hl, w)
      if value and tonumber(value) == 1 then
        table.insert(escseqs, string.format("[%dm", p.code))
      end
    end
  end
  local escseq = #escseqs > 0 and table.concat(escseqs) or nil
  local escfn = function(str)
    if escseq then
      str = string.format("%s%s%s", escseq, str or "", M.ansi_escseq.clear)
    end
    return str
  end
  return escfn(s), escseq, escfn
end

function M.has_ansi_coloring(str)
  return str:match("%[[%d;]-m")
end

function M.strip_ansi_coloring(str)
  if not str then return str end
  -- remove escape sequences of the following formats:
  -- 1. ^[[34m
  -- 2. ^[[0;34m
  -- 3. ^[[m
  -- NOTE: didn't work with grep's "^[[K"
  -- return str:gsub("%[[%d;]-m", "")
  -- https://stackoverflow.com/a/49209650/368691
  return str:gsub("[\27\155][][()#;?%d]*[A-PRZcf-ntqry=><~]", "")
end

function M.ansi_escseq_len(str)
  local stripped = M.strip_ansi_coloring(str)
  return #str - #stripped
end

function M.mode_is_visual()
  local visual_modes = {
    v   = true,
    vs  = true,
    V   = true,
    Vs  = true,
    nov = true,
    noV = true,
    niV = true,
    Rv  = true,
    Rvc = true,
    Rvx = true,
  }
  local mode = vim.api.nvim_get_mode()
  return visual_modes[mode.mode]
end

function M.get_visual_selection()
  -- this will exit visual mode
  -- use 'gv' to reselect the text
  local _, csrow, cscol, cerow, cecol
  local mode = vim.fn.mode()
  if mode == "v" or mode == "V" or mode == "" then
    -- if we are in visual mode use the live position
    _, csrow, cscol, _ = unpack(vim.fn.getpos("."))
    _, cerow, cecol, _ = unpack(vim.fn.getpos("v"))
    if mode == "V" then
      -- visual line doesn't provide columns
      cscol, cecol = 0, 999
    end
    -- NOTE: not required since commit: e8b2093
    -- exit visual mode
    -- vim.api.nvim_feedkeys(
    --   vim.api.nvim_replace_termcodes("<Esc>",
    --     true, false, true), "n", true)
  else
    -- otherwise, use the last known visual position
    _, csrow, cscol, _ = unpack(vim.fn.getpos("'<"))
    _, cerow, cecol, _ = unpack(vim.fn.getpos("'>"))
  end
  -- swap vars if needed
  if cerow < csrow then csrow, cerow = cerow, csrow end
  if cecol < cscol then cscol, cecol = cecol, cscol end
  local lines = vim.fn.getline(csrow, cerow)
  -- local n = cerow-csrow+1
  local n = #lines
  if n <= 0 then return "" end
  lines[n] = string.sub(lines[n], 1, cecol)
  lines[1] = string.sub(lines[1], cscol)
  return table.concat(lines, "\n"), {
    start   = { line = csrow, char = cscol },
    ["end"] = { line = cerow, char = cecol },
  }
end

function M.fzf_exit()
  -- Usually called from the LSP module to exit the interface on "async" mode
  -- when no results are found or when `jump1` is used, when the latter is used
  -- in "sync" mode we also need to make sure core.__CTX is cleared or we'll
  -- have the wrong cursor coordinates (#928)
  return loadstring([[
    require('fzf-lua').core.__CTX = nil
    require('fzf-lua').win.win_leave()
  ]])()
end

function M.fzf_winobj()
  -- use 'loadstring' to prevent circular require
  return loadstring("return require'fzf-lua'.win.__SELF()")()
end

function M.CTX(...)
  return loadstring("return require'fzf-lua'.core.CTX(...)")(...)
end

function M.__CTX()
  return loadstring("return require'fzf-lua'.core.__CTX")()
end

function M.resume_get(what, opts)
  local f = loadstring("return require'fzf-lua'.config.resume_get")()
  return f(what, opts)
end

M.resume_set = function(what, val, opts)
  local f = loadstring("return require'fzf-lua'.config.resume_set")()
  return f(what, val, opts)
end

function M.reset_info()
  pcall(loadstring("require'fzf-lua'.set_info(nil)"))
end

function M.setup_highlights(override)
  pcall(loadstring(string.format(
    "require'fzf-lua'.setup_highlights(%s)", override and "true" or "")))
end

---@param fname string
---@param name string|nil
---@param silent boolean|integer
function M.load_profile_fname(fname, name, silent)
  local profile = name or vim.fn.fnamemodify(fname, ":t:r") or "<unknown>"
  local ok, res = pcall(dofile, fname)
  if ok and type(res) == "table" then
    -- success
    if not silent then
      M.info(string.format("Successfully loaded profile '%s'", profile))
    end
    return res
  end
  -- If called from `setup` we set `silent=1` so we can alert the user on
  -- errors loading the requested profiles
  if silent ~= true and not ok then
    M.warn(string.format("Unable to load profile '%s': %s", profile, res:match("[^\n]+")))
  elseif type(res) ~= "table" then
    M.warn(string.format("Unable to load profile '%s': wrong type %s", profile, type(res)))
  end
end

---@param profiles table|string
---@param silent boolean|integer
---@return table
function M.load_profiles(profiles, silent)
  local ret = {}
  local path = require("fzf-lua").path
  profiles = type(profiles) == "table" and profiles
      or type(profiles) == "string" and { profiles }
      or {}
  -- If the use specified only the "hide" profile, inherit the defaults
  if #profiles == 1 and profiles[1] == "hide" then
    table.insert(profiles, 1, "default")
  end
  for _, profile in ipairs(profiles) do
    -- backward compat, renamed "borderless_full" > "borderless-full"
    if profile == "borderless_full" then profile = "borderless-full" end
    local fname = path.join({ vim.g.fzf_lua_directory, "profiles", profile .. ".lua" })
    local profile_opts = M.load_profile_fname(fname, nil, silent)
    if type(profile_opts) == "table" then
      if profile_opts[1] then
        -- profile requires loading base profile(s)
        -- silent = 1, only warn if failed to load
        profile_opts = vim.tbl_deep_extend("keep",
          profile_opts, M.load_profiles(profile_opts[1], 1))
      end
      if type(profile_opts.fn_load) == "function" then
        profile_opts.fn_load()
        profile_opts.fn_load = nil
      end
      ret = vim.tbl_deep_extend("force", ret, profile_opts)
    end
  end
  return ret
end

function M.send_ctrl_c()
  vim.api.nvim_feedkeys(
    vim.api.nvim_replace_termcodes("<C-c>", true, false, true), "n", true)
end

function M.feed_keys_termcodes(key)
  vim.api.nvim_feedkeys(
    vim.api.nvim_replace_termcodes(key, true, false, true), "n", true)
end

function M.is_term_bufname(bufname)
  if bufname and bufname:match("term://") then return true end
  return false
end

function M.is_term_buffer(bufnr)
  bufnr = tonumber(bufnr) or 0
  -- convert bufnr=0 to current buf so we can call 'bufwinid'
  bufnr = bufnr == 0 and vim.api.nvim_get_current_buf() or bufnr
  local winid = vim.fn.bufwinid(bufnr)
  if tonumber(winid) > 0 and vim.api.nvim_win_is_valid(winid) then
    return M.getwininfo(winid).terminal == 1
  end
  local bufname = vim.api.nvim_buf_is_valid(bufnr) and vim.api.nvim_buf_get_name(bufnr)
  return M.is_term_bufname(bufname)
end

function M.buffer_is_dirty(bufnr, warn, only_if_last_buffer)
  bufnr = tonumber(bufnr) or vim.api.nvim_get_current_buf()
  local info = bufnr and M.getbufinfo(bufnr)
  if info and info.changed ~= 0 then
    if only_if_last_buffer and 1 < #vim.fn.win_findbuf(bufnr) then
      return false
    end
    if warn then
      M.warn(("buffer %d:%s has unsaved changes"):format(bufnr,
        info.name and #info.name > 0 and info.name or "<unnamed>"))
    end
    return true
  end
  return false
end

function M.save_dialog(bufnr)
  bufnr = tonumber(bufnr) or vim.api.nvim_get_current_buf()
  local info = bufnr and M.getbufinfo(bufnr)
  if not info.name or #info.name == 0 then
    -- unnamed buffers can't be saved
    M.warn(string.format("buffer %d has unsaved changes", bufnr))
    return false
  end
  local res = vim.fn.confirm(string.format([[Save changes to "%s"?]], info.name),
    "&Yes\n&No\n&Cancel")
  if res == 0 or res == 3 then
    -- user cancelled
    return false
  end
  if res == 1 then
    -- user requested save
    local out = vim.api.nvim_cmd({ cmd = "update" }, { output = true })
    M.info(out)
  end
  return true
end

-- returns:
--   1 for qf list
--   2 for loc list
function M.win_is_qf(winid, wininfo)
  wininfo = wininfo or (vim.api.nvim_win_is_valid(winid) and M.getwininfo(winid))
  if wininfo and wininfo.quickfix == 1 then
    return wininfo.loclist == 1 and 2 or 1
  end
  return false
end

function M.buf_is_qf(bufnr, bufinfo)
  bufinfo = bufinfo or (vim.api.nvim_buf_is_valid(bufnr) and M.getbufinfo(bufnr))
  if bufinfo and bufinfo.variables and
      bufinfo.variables.current_syntax == "qf" and
      not M.tbl_isempty(bufinfo.windows) then
    return M.win_is_qf(bufinfo.windows[1])
  end
  return false
end

-- bufwinid from tab handle, different from tab idx (or "tabnr")
-- NOTE:  When tabs are reordered they still maintain the same
-- tab handle (also a number), example:
-- open two tabs and examine `vim.api.nvim_list_tabpages()`
-- the result should be { 1, 2 }
-- However, after moving the first tab with `:tabm` the result
-- is now { 2, 1 }
-- After closing the second tab with `:tabc` and opening a new
-- tab the result will be { 2, 3 } and after another `:tabm` on
-- the first tab the final result will be { 3, 2 }
-- At this point we have
--   * 1st visual tab: index:1 handle:3
--   * 2nd visual tab: index:2 handle:2
function M.winid_from_tabh(tabh, bufnr)
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(tabh)) do
    if bufnr == vim.api.nvim_win_get_buf(w) then
      return w
    end
  end
  return nil
end

-- bufwinid from visual tab index
function M.winid_from_tabi(tabi, bufnr)
  local tabh = vim.api.nvim_list_tabpages()[tabi]
  return M.winid_from_tabh(tabh, bufnr)
end

function M.nvim_buf_get_name(bufnr, bufinfo)
  assert(not vim.in_fast_event())
  if not vim.api.nvim_buf_is_valid(bufnr) then return end
  if bufinfo and bufinfo.name and #bufinfo.name > 0 then
    return bufinfo.name
  end
  local bufname = vim.api.nvim_buf_get_name(bufnr)
  if #bufname == 0 then
    local is_qf = M.buf_is_qf(bufnr, bufinfo)
    if is_qf then
      bufname = is_qf == 1 and "[Quickfix List]" or "[Location List]"
    else
      bufname = "[No Name]"
    end
  end
  assert(#bufname > 0)
  return bufname
end

-- correctly handle virtual text, conceal lines
function M.line_count(win, buf)
  if vim.api.nvim_win_text_height then
    return vim.api.nvim_win_text_height(win, {}).all
  else
    return vim.api.nvim_buf_line_count(buf)
  end
end

function M.zz()
  -- skip for terminal buffers
  if M.is_term_buffer() then return end
  local lnum1 = vim.api.nvim_win_get_cursor(0)[1]
  local lcount = vim.api.nvim_buf_line_count(0)
  local zb = "keepj norm! %dzb"
  if lnum1 == lcount then
    vim.fn.execute(zb:format(lnum1))
    return
  end
  vim.cmd("norm! zvzz")
  lnum1 = vim.api.nvim_win_get_cursor(0)[1]
  vim.cmd("norm! L")
  local lnum2 = vim.api.nvim_win_get_cursor(0)[1]
  if lnum2 + vim.fn.getwinvar(0, "&scrolloff") >= lcount then
    vim.fn.execute(zb:format(lnum2))
  end
  if lnum1 ~= lnum2 then
    vim.cmd("keepj norm! ``")
  end
end

---@param func function
---@param scope string?
---@param win integer
function M.eventignore(func, win, scope)
  if win and vim.fn.exists("+eventignorewin") == 1 then
    local save_ei = vim.wo[win][0].eventignorewin
    vim.wo[win][0].eventignorewin = scope or "all"
    local ret = { func() }
    vim.wo[win][0].eventignorewin = save_ei
    return unpack(ret)
  end
  local save_ei = vim.o.eventignore
  vim.o.eventignore = scope or "all"
  local ret = { func() }
  vim.o.eventignore = save_ei
  return unpack(ret)
end

-- Set buffer for window without an autocmd
function M.win_set_buf_noautocmd(win, buf)
  return M.eventignore(function() return vim.api.nvim_win_set_buf(win, buf) end)
end

-- Open a window without triggering an autocmd
function M.nvim_open_win(bufnr, enter, config)
  return M.eventignore(function() return vim.api.nvim_open_win(bufnr, enter, config) end)
end

function M.nvim_open_win0(bufnr, enter, config)
  local winid = M.CTX().winid
  if not vim.api.nvim_win_is_valid(winid) then
    return vim.api.nvim_open_win(bufnr, enter, config)
  end
  return vim.api.nvim_win_call(winid, function()
    return vim.api.nvim_open_win(bufnr, enter, config)
  end)
end

-- Close a window without triggering an autocmd
function M.nvim_win_close(win, opts)
  return M.eventignore(function() return vim.api.nvim_win_close(win, opts) end)
end

-- Close a buffer without triggering an autocmd
function M.nvim_buf_delete(bufnr, opts)
  return M.eventignore(function()
    if not vim.api.nvim_buf_is_valid(bufnr) then return end
    return vim.api.nvim_buf_delete(bufnr, opts)
  end)
end

---@param winid integer
---@param opts vim.api.keyset.win_config Map defining the window configuration,
function M.fast_win_set_config(winid, opts)
  -- win_set_config can be slow even later with `opts={}`
  -- win->w_config is reused, but style="minimal" always reset win option (slow for bigfile)
  -- https://github.com/neovim/neovim/blob/08c484f2ca4b58e9eda07e194e9d096565db7144/src/nvim/api/win_config.c#L406
  -- so don't set it if opts is the same
  local old_opts = vim.api.nvim_win_get_config(winid)
  -- nvim_win_get_config don't return style="minimal"
  -- opts.style is mainly for nvim_open_win only (we don't use it here)
  opts.style = nil
  for k, v in pairs(opts) do
    if not vim.deep_equal(old_opts[k], v) then
      vim.api.nvim_win_set_config(winid, opts)
      break
    end
  end
end

function M.upvfind(func, upval_name)
  -- Find the upvalue in a function
  local i = 1
  while true do
    local name, value = debug.getupvalue(func, i)
    if not name then break end
    if name == upval_name then return value end
    i = i + 1
  end
  return nil
end

function M.getbufinfo(bufnr)
  if M.__HAS_AUTOLOAD_FNS then
    return vim.fn["fzf_lua#getbufinfo"](bufnr)
  else
    local info = vim.fn.getbufinfo(bufnr)
    return info[1] or info
  end
end

function M.getwininfo(winid)
  if M.__HAS_AUTOLOAD_FNS then
    return vim.fn["fzf_lua#getwininfo"](winid)
  else
    local info = vim.fn.getwininfo(winid)
    return info[1] or info
  end
end

---@param cmd string[]
---@return string[] lines in the stdout or stderr, separated by '\n'
---@return integer exit_code (0: success)
function M.io_systemlist(cmd)
  if vim.system ~= nil then -- nvim 0.10+
    local proc = vim.system(cmd):wait()
    local output = (type(proc.stderr) == "string" and proc.stderr or "")
        .. (type(proc.stdout) == "string" and proc.stdout or "")
    return vim.split(output, "\n", { trimempty = true }), proc.code
  else
    return vim.fn.systemlist(cmd), vim.v.shell_error
  end
end

---@param cmd string[]
---@return string stdout or stderr
---@return integer exit_code (0: success)
function M.io_system(cmd)
  if vim.system ~= nil then -- nvim 0.10+
    local proc = vim.system(cmd):wait()
    local output = (type(proc.stderr) == "string" and proc.stderr or "")
        .. (type(proc.stdout) == "string" and proc.stdout or "")
    return output, proc.code
  else
    return vim.fn.system(cmd), vim.v.shell_error
  end
end

-- wrapper around |input()| to allow cancellation with `<C-c>`
-- without "E5108: Error executing lua Keyboard interrupt"
function M.input(prompt, default)
  default = default or ""
  local ok, res
  -- NOTE: do not use `vim.ui` yet, a conflict with `dressing.nvim`
  -- causes the return value to appear as cancellation
  -- if vim.ui then
  if false then
    ok, _ = pcall(vim.ui.input, { prompt = prompt, default = default },
      function(input)
        res = input
      end)
  else
    ok, res = pcall(vim.fn.input, { prompt = prompt, default = default, cancelreturn = 3 })
    if res == 3 then
      ok, res = false, nil
    end
  end
  return ok and res or nil
end

function M.fzf_bind_to_neovim(key)
  local conv_map = {
    ["alt"] = "A",
    ["ctrl"] = "C",
    ["shift"] = "S",
  }
  key            = key:lower()
  for k, v in pairs(conv_map) do
    key = key:gsub(k, v)
  end
  return ("<%s>"):format(key)
end

function M.neovim_bind_to_fzf(key)
  local conv_map = {
    ["a"] = "alt",
    ["c"] = "ctrl",
    ["s"] = "shift",
  }

  key            = key:lower():gsub("[<>]", "")
  for k, v in pairs(conv_map) do
    key = key:gsub(k .. "%-", v .. "-")
  end
  return key
end

function M.parse_verstr(str)
  if type(str) ~= "string" then return end
  local major, minor, patch = str:match("(%d+).(%d+)%.?(.*)")
  -- Fzf on HEAD edge case
  major = tonumber(major) or str:match("HEAD") and 100 or nil
  return major and { major, tonumber(minor) or 0, tonumber(patch) or 0 } or nil
end

function M.ver2str(v)
  if type(v) ~= "table" or not v[1] then return end
  return string.format("%d.%d.%d", tonumber(v[1]) or 0, tonumber(v[2]) or 0, tonumber(v[3]) or 0)
end

function M.has(opts, ...)
  assert(type(opts) == "table")
  local what = select(1, ...)
  if what == "fzf" or what == "sk" then
    local has_ver = select(2, ...)
    if not has_ver then
      if what == "sk" and opts.__SK_VERSION then return true end
      if what == "fzf" and opts.__FZF_VERSION then return true end
    else
      local curr_ver
      if what == "sk" then curr_ver = opts.__SK_VERSION end
      if what == "fzf" then curr_ver = opts.__FZF_VERSION end
      if type(has_ver) == "string" then has_ver = M.parse_verstr(has_ver) end
      if type(has_ver) == "table" and type(curr_ver) == "table" then
        has_ver[2] = tonumber(has_ver[2]) or 0
        has_ver[3] = tonumber(has_ver[3]) or 0
        curr_ver[2] = tonumber(curr_ver[2]) or 0
        curr_ver[3] = tonumber(curr_ver[3]) or 0
        if curr_ver[1] > has_ver[1]
            or curr_ver[1] == has_ver[1] and curr_ver[2] > has_ver[2]
            or curr_ver[1] == has_ver[1] and curr_ver[2] == has_ver[2] and curr_ver[3] >= has_ver[3]
        then
          return true
        end
      end
    end
  end
  return false
end

function M.fzf_version(opts)
  -- temp unset "FZF_DEFAULT_OPTS" as it might fail `--version`
  -- if it contains options aren't compatible with fzf's version
  local FZF_DEFAULT_OPTS = vim.env.FZF_DEFAULT_OPTS
  vim.env.FZF_DEFAULT_OPTS = nil
  local out, rc = M.io_system({ opts and opts.fzf_bin or "fzf", "--version" })
  vim.env.FZF_DEFAULT_OPTS = FZF_DEFAULT_OPTS
  return M.parse_verstr(out), rc, out
end

function M.sk_version(opts)
  -- temp unset "SKIM_DEFAULT_OPTIONS" as it might fail `--version`
  -- if it contains options aren't compatible with sk's version
  local SKIM_DEFAULT_OPTIONS = vim.env.SKIM_DEFAULT_OPTIONS
  vim.env.SKIM_DEFAULT_OPTIONS = nil
  local out, rc = M.io_system({ opts and opts.fzf_bin or "sk", "--version" })
  vim.env.SKIM_DEFAULT_OPTIONS = SKIM_DEFAULT_OPTIONS
  return M.parse_verstr(out), rc, out
end

function M.git_version()
  local out = M.io_system({ "git", "--version" })
  return tonumber(out:match("(%d+.%d+)."))
end

function M.find_version()
  local out, rc = M.io_systemlist({ "find", "--version" })
  return rc == 0 and tonumber(out[1]:match("(%d+.%d+)")) or nil
end

---@return string
function M.windows_pipename()
  local tmpname = vim.fn.tempname()
  tmpname = string.gsub(tmpname, "\\", "")
  return ([[\\.\pipe\%s]]):format(tmpname)
end

function M.create_user_command_callback(provider, arg, altmap)
  local function fzflua_opts(o)
    local ret = {}
    -- fzf.vim's bang version of the commands opens fullscreen
    if o.bang then ret.winopts = { fullscreen = true } end
    return ret
  end
  return function(o)
    local fzf_lua = require("fzf-lua")
    local prov = provider
    local opts = fzflua_opts(o) -- setup bang!
    if type(o.fargs[1]) == "string" then
      local farg = o.fargs[1]
      for c, p in pairs(altmap or {}) do
        -- fzf.vim hijacks the first character of the arg
        -- to setup special commands postfixed with `?:/`
        -- "GFiles?", "History:" and "History/"
        if farg:sub(1, 1) == c then
          prov = p
          -- we still allow using args with alt
          -- providers by removing the "?:/" prefix
          farg = #farg > 1 and vim.trim(farg:sub(2))
          break
        end
      end
      if arg and farg and #farg > 0 then
        opts[arg] = vim.trim(farg)
      end
    end
    fzf_lua[prov](opts)
  end
end

-- setmetatable wrapper, also enable `__gc`
function M.setmetatable__gc(t, mt)
  local prox = newproxy(true)
  getmetatable(prox).__gc = function() mt.__gc(t) end
  t[prox] = true
  return setmetatable(t, mt)
end

--- Checks if treesitter parser for language is installed
---@param lang string
function M.has_ts_parser(lang)
  if M.__HAS_NVIM_011 then
    return vim.treesitter.language.add(lang)
  else
    return pcall(vim.treesitter.language.add, lang)
  end
end

--- Wrapper around vim.lsp.jump_to_location which was deprecated in v0.11
---@param location lsp.Location|lsp.LocationLink
---@param offset_encoding 'utf-8'|'utf-16'|'utf-32'
---@param reuse_win boolean?
---@return boolean
function M.jump_to_location(location, offset_encoding, reuse_win)
  if M.__HAS_NVIM_011 then
    return vim.lsp.util.show_document(location, offset_encoding,
      { reuse_win = reuse_win, focus = true })
  else
    ---@diagnostic disable-next-line: deprecated
    return vim.lsp.util.jump_to_location(location, offset_encoding, reuse_win)
  end
end

--- Wrapper around vim.fn.termopen which was deprecated in v0.11
function M.termopen(cmd, opts)
  -- Workaround for #1732 (nightly builds prior to jobstart/term patch)
  if M.__HAS_NVIM_011 and M._JOBSTART_HAS_TERM == nil then
    local ok, err = pcall(vim.fn.jobstart, "", { term = 1 })
    M._JOBSTART_HAS_TERM = not ok
        and err:match [[Vim:E475: Invalid argument: 'term' must be Boolean]]
        and true or false
  end
  if M.__HAS_NVIM_011 and M._JOBSTART_HAS_TERM then
    opts = opts or {}
    opts.term = true
    return vim.fn.jobstart(cmd, opts)
  else
    ---@diagnostic disable-next-line: deprecated
    return vim.fn.termopen(cmd, opts)
  end
end

function M.toggle_cmd_flag(cmd, flag, enabled, append)
  if not flag then
    M.err("'toggle_flag' not set")
    return
  end

  -- flag must be preceded by whitespace
  if not flag:match("^%s") then flag = " " .. flag end

  -- auto-detect toggle when nil
  if enabled == nil then
    enabled = not cmd:match(M.lua_regex_escape(flag))
  end

  if not enabled then
    cmd = cmd:gsub(M.lua_regex_escape(flag), "")
  elseif not cmd:match(M.lua_regex_escape(flag)) then
    local bin, args = cmd:match("([^%s]+)(.*)$")
    if append then
      cmd = string.format("%s %s", cmd, flag)
    else
      cmd = string.format("%s%s%s", bin, flag, args)
    end
  end

  return cmd
end

function M.lsp_get_clients(opts)
  if M.__HAS_NVIM_011 then
    return vim.lsp.get_clients(opts)
  end
  ---@diagnostic disable-next-line: deprecated
  local get = vim.lsp.get_clients or vim.lsp.get_active_clients
  local clients = get(opts)
  return vim.tbl_map(function(client)
    return setmetatable({
      supports_method = function(_, ...) return client.supports_method(...) end,
      request = function(_, ...) return client.request(...) end,
      request_sync = function(_, ...) return client.request_sync(...) end,
    }, { __index = client })
  end, clients)
end

return M
