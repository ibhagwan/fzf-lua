-- help to inspect results, e.g.:
-- ':lua _G.dump(vim.fn.getwininfo())'
-- use ':messages' to see the dump
function _G.dump(...)
  local objects = vim.tbl_map(vim.inspect, { ... })
  print(unpack(objects))
end

local M = {}

M.__HAS_NVIM_07 = vim.fn.has("nvim-0.7") == 1
M.__HAS_NVIM_08 = vim.fn.has("nvim-0.8") == 1
M.__HAS_NVIM_09 = vim.fn.has("nvim-0.9") == 1
M.__HAS_NVIM_010 = vim.fn.has("nvim-0.10") == 1


-- limit devicons support to nvim >=0.8, although official support is >=0.7
-- running setup on 0.7 errs with "W18: Invalid character in group name"
if M.__HAS_NVIM_08 then
  M.__HAS_DEVICONS = pcall(require, "nvim-web-devicons")
end

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

-- DO NOT USE '\u{}' escape, it will fail with
-- "invalid escape sequence" if Lua < 5.3
-- '\x' escape sequence requires Lua 5.2
-- M.nbsp = "\xc2\xa0"    -- "\u{00a0}"
M.nbsp = "\xe2\x80\x82" -- "\u{2002}"

-- Lua 5.1 compatibility, not sure if required since we're running LuaJIT
-- but it's harmless anyways since if the '\x' escape worked it will do nothing
-- https://stackoverflow.com/questions/29966782/\
--    how-to-embed-hex-values-in-a-lua-string-literal-i-e-x-equivalent
if _VERSION and type(_VERSION) == "string" then
  local ver = tonumber(_VERSION:match("%d+.%d+"))
  if ver < 5.2 then
    M.nbsp = M.nbsp:gsub("\\x(%x%x)",
      function(x)
        return string.char(tonumber(x, 16))
      end)
  end
end

M._if = function(bool, a, b)
  if bool then
    return a
  else
    return b
  end
end

M.strsplit = function(inputstr, sep)
  local t = {}
  for str in string.gmatch(inputstr, "([^" .. sep .. "]+)") do
    table.insert(t, str)
  end
  return t
end

local string_byte = string.byte

M.find_last_char = function(str, c)
  for i = #str, 1, -1 do
    if string_byte(str, i) == c then
      return i
    end
  end
end

M.find_next_char = function(str, c, start_idx)
  for i = start_idx or 1, #str do
    if string_byte(str, i) == c then
      return i
    end
  end
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
  return vim.loop.os_uname().sysname == "Darwin"
end

function M.rg_escape(str)
  if not str then return str end
  --  [(~'"\/$?'`*&&||;[]<>)]
  --  escape "\~$?*|[()^-."
  return str:gsub("[\\~$?*|{\\[()^%-%.%+]", function(x)
    return "\\" .. x
  end)
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

function M.lua_regex_escape(str)
  -- escape all lua special chars
  -- ( ) % . + - * [ ? ^ $
  if not str then return nil end
  return str:gsub("[%(%)%.%+%-%*%[%?%^%$%%]", function(x)
    return "%" .. x
  end)
end

function M.glob_escape(str)
  if not str then return str end
  return str:gsub("[\\%{}[%]]", function(x)
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
      not vim.loop.fs_stat(filepath) then
    return false
  end
  local out = M.io_system({ "file", "--dereference", "--mime", filepath })
  return out:match("charset=binary") ~= nil
end

local S_IFMT = 0xF000  -- filetype mask
local S_IFIFO = 0x1000 -- fifo

M.file_is_fifo = function(filepath)
  local stat = vim.loop.fs_stat(filepath)
  if stat and bit.band(stat.mode, S_IFMT) == S_IFIFO then
    return true
  end
  return false
end

M.file_is_readable = function(filepath)
  local fd = vim.loop.fs_open(filepath, "r", 438)
  if fd then
    vim.loop.fs_close(fd)
    return true
  end
  return false
end

M.perl_file_is_binary = function(filepath)
  filepath = M.pcall_expand(filepath)
  if vim.fn.executable("perl") ~= 1 or
      not vim.loop.fs_stat(filepath) then
    return false
  end
  -- can also use '-T' to test for text files
  -- `perldoc -f -x` to learn more about '-B|-T'
  local _, rc = M.io_system({ "perl", "-E", "exit((-B $ARGV[0])?0:1);", filepath })
  return rc == 0
end

M.read_file = function(filepath)
  local fd = vim.loop.fs_open(filepath, "r", 438)
  if fd == nil then return "" end
  local stat = assert(vim.loop.fs_fstat(fd))
  if stat.type ~= "file" then return "" end
  local data = assert(vim.loop.fs_read(fd, stat.size, 0))
  assert(vim.loop.fs_close(fd))
  return data
end

M.read_file_async = function(filepath, callback)
  vim.loop.fs_open(filepath, "r", 438, function(err_open, fd)
    if err_open then
      -- we must schedule this or we get
      -- E5560: nvim_exec must not be called in a lua loop callback
      vim.schedule(function()
        M.warn(("Unable to open file '%s', error: %s"):format(filepath, err_open))
      end)
      return
    end
    vim.loop.fs_fstat(fd, function(err_fstat, stat)
      assert(not err_fstat, err_fstat)
      if stat.type ~= "file" then return callback("") end
      vim.loop.fs_read(fd, stat.size, 0, function(err_read, data)
        assert(not err_read, err_read)
        vim.loop.fs_close(fd, function(err_close)
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

function M.tbl_length(T)
  local count = 0
  for _ in pairs(T) do count = count + 1 end
  return count
end

function M.tbl_isempty(T)
  if not T or not next(T) then return true end
  return false
end

function M.tbl_extend(t1, t2)
  return table.move(t2, 1, #t2, #t1 + 1, t1)
end

-- Get map value from string key
-- e.g. `map_get(m, "key.sub1.sub2")`
function M.map_get(m, k)
  if not m then return end
  if not k then return m end
  local keys = M.strsplit(k, ".")
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
-- if need be, build map tree as we go along
function M.map_set(m, k, v)
  m = m or {}
  local keys = M.strsplit(k, ".")
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

function M.map_tolower(m)
  if not m then
    return
  end
  local ret = {}
  for k, v in pairs(m) do
    ret[k:lower()] = v
  end
  return ret
end

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

local function hex2rgb(hexcol)
  local r, g, b = hexcol:match("#(..)(..)(..)")
  if not r or not g or not b then return end
  r, g, b = tonumber(r, 16), tonumber(g, 16), tonumber(b, 16)
  return r, g, b
end

-- Helper func to test for invalid (cleared) highlights
function M.is_hl_cleared(hl)
  -- `vim.api.nvim_get_hl_by_name` is deprecated since v0.9.0
  if vim.api.nvim_get_hl then
    local ok, hl_def = pcall(vim.api.nvim_get_hl, 0, { name = hl, link = false })
    if not ok or vim.tbl_isempty(hl_def) then
      return true
    end
  else
    local ok, hl_def = pcall(vim.api.nvim_get_hl_by_name, hl, true)
    -- Not sure if this is the right way but it seems that cleared
    -- highlights return 'hl_def[true] == 6' (?) and 'hl_def[true]'
    -- does not exist at all otherwise
    if not ok or hl_def[true] then
      return true
    end
  end
end

function M.COLORMAP()
  if not M.__COLORMAP then
    M.__COLORMAP = vim.api.nvim_get_color_map()
  end
  return M.__COLORMAP
end

local function synIDattr(hl, w)
  return vim.fn.synIDattr(vim.fn.synIDtrans(vim.fn.hlID(hl)), w)
end

function M.hexcol_from_hl(hlgroup, what)
  if not hlgroup or not what then return end
  local hexcol = synIDattr(hlgroup, what)
  if hexcol and not hexcol:match("^#") then
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
    return string.format("[38;2;%d;%d;%dm%s%s", r, g, b, s, M.ansi_escseq.clear)
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
  return str:gsub("%[[%d;]-m", "")
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
    -- exit visual mode
    vim.api.nvim_feedkeys(
      vim.api.nvim_replace_termcodes("<Esc>",
        true, false, true), "n", true)
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
  local n = M.tbl_length(lines)
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
  -- when no results are found or when `jump_to_single_result` is used, when
  -- the latter is used in "sync" mode we also need to make sure core.__CTX
  -- is cleared or we'll have the wrong cursor coordiantes (#928)
  return loadstring([[
    require('fzf-lua').core.__CTX = nil
    require('fzf-lua').win.win_leave()
  ]])()
end

function M.fzf_winobj()
  -- use 'loadstring' to prevent circular require
  return loadstring("return require'fzf-lua'.win.__SELF()")()
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

function M.setup_highlights()
  pcall(loadstring("require'fzf-lua'.setup_highlights()"))
end

function M.setup_devicon_term_hls()
  pcall(loadstring("require'fzf-lua.make_entry'.setup_devicon_term_hls()"))
end

function M.load_profile(fname, name, silent)
  local profile = name or fname:match("([^%p]+)%.lua$") or "<unknown>"
  local ok, res = pcall(dofile, fname)
  if ok and type(res) == "table" then
    -- success
    if not silent then
      M.info(string.format("Succefully loaded profile '%s'", profile))
    end
    return res
  elseif silent then
    return
  end
  if not ok then
    M.warn(string.format("Unable to load profile '%s': %s", profile, res:match("[^\n]+")))
  elseif type(res) ~= "table" then
    M.warn(string.format("Unable to load profile '%s': wrong type %s", profile, type(res)))
  end
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
    return vim.fn.getwininfo(winid)[1].terminal == 1
  end
  local bufname = vim.api.nvim_buf_is_valid(bufnr) and vim.api.nvim_buf_get_name(bufnr)
  return M.is_term_bufname(bufname)
end

function M.buffer_is_dirty(bufnr, warn, only_if_last_buffer)
  bufnr = tonumber(bufnr) or vim.api.nvim_get_current_buf()
  local info = bufnr and vim.fn.getbufinfo(bufnr)[1]
  if info and info.changed ~= 0 then
    if only_if_last_buffer and 1 < M.tbl_length(vim.fn.win_findbuf(bufnr)) then
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
  local info = bufnr and vim.fn.getbufinfo(bufnr)[1]
  if not info.name or #info.name == 0 then
    -- unnamed buffers can't be saved
    M.warn(string.format("buffer %d has unsaved changes", bufnr))
    return false
  end
  local res = vim.fn.confirm(string.format([[Save changes to "%s"?]], info.name),
    "&Yes\n&No\n&Cancel")
  if res == 3 then
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
  wininfo = wininfo or
      (vim.api.nvim_win_is_valid(winid) and vim.fn.getwininfo(winid)[1])
  if wininfo and wininfo.quickfix == 1 then
    return wininfo.loclist == 1 and 2 or 1
  end
  return false
end

function M.buf_is_qf(bufnr, bufinfo)
  bufinfo = bufinfo or
      (vim.api.nvim_buf_is_valid(bufnr) and vim.fn.getbufinfo(bufnr)[1])
  if bufinfo and bufinfo.variables and
      bufinfo.variables.current_syntax == "qf" and
      not vim.tbl_isempty(bufinfo.windows) then
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

-- Set buffer for window without an autocmd
function M.win_set_buf_noautocmd(win, buf)
  local save_ei = vim.o.eventignore
  vim.o.eventignore = "all"
  vim.api.nvim_win_set_buf(win, buf)
  vim.o.eventignore = save_ei
end

-- Open a window without triggering an autocmd
function M.nvim_open_win(bufnr, enter, config)
  local save_ei = vim.o.eventignore
  vim.o.eventignore = "all"
  local winid = vim.api.nvim_open_win(bufnr, enter, config)
  vim.o.eventignore = save_ei
  return winid
end

-- Close a window without triggering an autocmd
function M.nvim_win_close(win, opts)
  local save_ei = vim.o.eventignore
  vim.o.eventignore = "all"
  vim.api.nvim_win_close(win, opts)
  vim.o.eventignore = save_ei
end

-- Close a buffer without triggering an autocmd
function M.nvim_buf_delete(bufnr, opts)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  local save_ei = vim.o.eventignore
  vim.o.eventignore = "all"
  vim.api.nvim_buf_delete(bufnr, opts)
  vim.o.eventignore = save_ei
end

-- Backward compat 'vim.keymap.set', will probably be deprecated soon
function M.keymap_set(mode, lhs, rhs, opts)
  if vim.keymap then
    vim.keymap.set(mode, lhs, rhs, opts)
  else
    assert(type(mode) == "string" and type(rhs) == "string")
    opts = opts or {}
    -- `noremap` is the inverse of the new API `remap`
    opts.noremap = not opts.remap
    if opts.buffer then
      -- when `buffer` is true replace with `0` for local buffer
      -- mapping and remove from options
      local bufnr = type(opts.buffer) == "number" and opts.buffer or 0
      opts.buffer = nil
      vim.api.nvim_buf_set_keymap(bufnr, mode, lhs, rhs, opts)
    else
      vim.api.nvim_set_keymap(mode, lhs, rhs, opts)
    end
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
function M.input(prompt)
  local ok, res
  -- NOTE: do not use `vim.ui` yet, a conflcit with `dressing.nvim`
  -- causes the return value to appear as cancellation
  -- if vim.ui then
  if false then
    ok, _ = pcall(vim.ui.input, { prompt = prompt },
      function(input)
        res = input
      end)
  else
    ok, res = pcall(vim.fn.input, { prompt = prompt, cancelreturn = 3 })
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

function M.fzf_version(opts)
  opts = opts or {}
  -- temp unset "FZF_DEFAULT_OPTS" as it might fail `--version`
  -- if it contains options aren't compatible with fzf's version
  local FZF_DEFAULT_OPTS = vim.env.FZF_DEFAULT_OPTS
  vim.env.FZF_DEFAULT_OPTS = nil
  local out, rc = M.io_system({ opts.fzf_bin or "fzf", "--version" })
  vim.env.FZF_DEFAULT_OPTS = FZF_DEFAULT_OPTS
  if out:match("HEAD") then return 4 end
  return tonumber(out:match("(%d+.%d+).")), rc, out
end

function M.git_version()
  local out = M.io_system({ "git", "--version" })
  return tonumber(out:match("(%d+.%d+)."))
end

function M.find_version()
  local out, rc = M.io_systemlist({ "find", "--version" })
  return rc == 0 and tonumber(out[1]:match("(%d+.%d+)")) or nil
end

return M
