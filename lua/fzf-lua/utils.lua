-- help to inspect results, e.g.:
-- ':lua _G.dump(vim.fn.getwininfo())'
function _G.dump(...)
  local objects = vim.tbl_map(vim.inspect, { ... })
  print(unpack(objects))
end

local M = {}

-- invisible unicode char as icon|git separator
-- this way we can split our string by space
-- this causes "invalid escape sequence" error
-- local nbsp = "\u{00a0}"
M.nbsp = " "

M._if = function(bool, a, b)
    if bool then
        return a
    else
        return b
    end
end

function M._echo_multiline(msg)
  for _, s in ipairs(vim.fn.split(msg, "\n")) do
    vim.cmd("echom '" .. s:gsub("'", "''").."'")
  end
end

function M.info(msg)
  vim.cmd('echohl Directory')
  M._echo_multiline("[Fzf-lua] " .. msg)
  vim.cmd('echohl None')
end

function M.warn(msg)
  vim.cmd('echohl WarningMsg')
  M._echo_multiline("[Fzf-lua] " .. msg)
  vim.cmd('echohl None')
end

function M.err(msg)
  vim.cmd('echohl ErrorMsg')
  M._echo_multiline("[Fzf-lua] " .. msg)
  vim.cmd('echohl None')
end

function M.shell_error()
  return vim.v.shell_error ~= 0
end

function M.is_git_repo()
  -- can also use: "git rev-parse is-inside-work-tree"
  vim.fn.system("git rev-parse --git-dir")
  return M._if(M.shell_error(), false, true)
end

function M.rg_escape(str)
  if not str then return str end
  --  [(~'"\/$?'`*&&||;[]<>)]
  --  escape "\~$?*|[()"
  return str:gsub("[\\~$?*|{\\[()]", function(x)
    return '\\' .. x
  end)
end

M.read_file = function(filepath)
  local fd = vim.loop.fs_open(filepath, "r", 438)
  if fd == nil then return '' end
  local stat = assert(vim.loop.fs_fstat(fd))
  if stat.type ~= 'file' then return '' end
  local data = assert(vim.loop.fs_read(fd, stat.size, 0))
  assert(vim.loop.fs_close(fd))
  return data
end

M.read_file_async = function(filepath, callback)
  vim.loop.fs_open(filepath, "r", 438, function(err_open, fd)
    if err_open then
      M.warn("We tried to open this file but couldn't. We failed with following error message: " .. err_open)
      return
    end
    vim.loop.fs_fstat(fd, function(err_fstat, stat)
      assert(not err_fstat, err_fstat)
      if stat.type ~= 'file' then return callback('') end
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

function M.tbl_has(table, key)
  return table[key] ~= nil
end

function M.tbl_or(key, tbl1, tbl2)
  if tbl1[key] ~= nil then return tbl1[key]
  else return tbl2[key] end
end

function M.tbl_concat(...)
  local result = {}
  local n = 0

  for _, t in ipairs({...}) do
    for i, v in ipairs(t) do
      result[n + i] = v
    end
    n = n + #t
  end

  return result
end

function M.tbl_pack(...)
  return {n=select('#',...); ...}
end

function M.tbl_unpack(t, i, j)
  return unpack(t, i or 1, j or t.n or #t)
end

M.ansi_codes = {}
M.ansi_colors = {
    -- the "\x1b" esc sequence causes issues
    -- with older Lua versions
    -- clear    = "\x1b[0m",
    clear       = "[0m",
    bold        = "[1m",
    black       = "[0;30m",
    red         = "[0;31m",
    green       = "[0;32m",
    yellow      = "[0;33m",
    blue        = "[0;34m",
    magenta     = "[0;35m",
    cyan        = "[0;36m",
    grey        = "[0;90m",
    dark_grey   = "[0;97m",
    white       = "[0;98m",
}

for color, escseq in pairs(M.ansi_colors) do
    M.ansi_codes[color] = function(string)
        if string == nil or #string == 0 then return '' end
        return escseq .. string .. M.ansi_colors.clear
    end
end

function M.get_visual_selection()
    -- must exit visual mode or program croaks
    -- :visual leaves ex-mode back to normal mode
    -- use 'gv' to reselect the text
    vim.cmd[[visual]]
    local _, csrow, cscol, _ = unpack(vim.fn.getpos("'<"))
    local _, cerow, cecol, _ = unpack(vim.fn.getpos("'>"))
    local lines = vim.fn.getline(csrow, cerow)
    -- local n = cerow-csrow+1
    local n = M.tbl_length(lines)
    if n <= 0 then return '' end
    lines[n] = string.sub(lines[n], 1, cecol)
    lines[1] = string.sub(lines[1], cscol)
    return table.concat(lines, "\n")
end

function M.send_ctrl_c()
  vim.api.nvim_feedkeys(
    vim.api.nvim_replace_termcodes("<C-c>", true, false, true), 'n', true)
end

function M.feed_key(key)
  vim.api.nvim_feedkeys(
    vim.api.nvim_replace_termcodes(key, true, false, true), 'n', true)
end

function M.delayed_cb(cb, fn)
  -- HACK: slight delay to prevent missing results
  -- otherwise the input stream closes too fast
  -- sleep was causing all sorts of issues
  -- vim.cmd("sleep! 10m")
  if fn == nil then fn = function() end end
  vim.defer_fn(function()
    cb(nil, fn)
  end, 20)
end

return M
