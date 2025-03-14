local uv = vim.uv or vim.loop
local core = require "fzf-lua.core"
local path = require "fzf-lua.path"
local utils = require "fzf-lua.utils"
local config = require "fzf-lua.config"
local libuv = require "fzf-lua.libuv"

local M = {}

-- Given a path, attempt to find the first existing directory
-- returns a tuple:
--   display cwd: to be joined with the completed path, maintains
--                the original cwd format (i.e $HOME, ~, "./", etc)
--   fullpath cwd and postfix which will be used as fzf's "--query"
--   argument to be entered into the prompt automatically
local function find_toplevel_cwd(maybe_cwd, postfix, orig_cwd)
  -- expand can fail on open curly braces with:
  -- E5108: Error executing lua Vim:E220: Missing }.
  local ok, _ = pcall(libuv.expand, maybe_cwd)
  if not maybe_cwd or #maybe_cwd == 0 or not ok then
    return nil, nil, nil
  end
  if not orig_cwd then
    orig_cwd = maybe_cwd
  end
  if vim.fn.isdirectory(libuv.expand(maybe_cwd)) == 1 then
    local disp_cwd, cwd = maybe_cwd, libuv.expand(maybe_cwd)
    -- returned cwd must be full path
    if path.has_cwd_prefix(cwd) then
      cwd = uv.cwd() .. (#cwd > 1 and cwd:sub(2) or "")
      -- inject "./" only if original path started with it
      -- otherwise ignore the "." retval from fnamemodify
      if #orig_cwd > 0 and orig_cwd:sub(1, 1) ~= "." then
        disp_cwd = nil
      end
    elseif not path.is_absolute(cwd) then
      cwd = path.join({ uv.cwd(), cwd })
    end
    return disp_cwd, cwd, postfix
  end
  postfix = vim.fn.fnamemodify(maybe_cwd, ":t")
  maybe_cwd = vim.fn.fnamemodify(maybe_cwd, ":h")
  return find_toplevel_cwd(maybe_cwd, postfix, orig_cwd)
end

-- forward and reverse match spaces and single/double quotes
-- and attempt to find the top level existing directory
-- set the cwd and prompt top the top level directory and
-- the leftover match to the input query
local set_cmp_opts_path = function(opts)
  local match = opts.word_pattern or "[^%s\"']*"
  local line = vim.api.nvim_get_current_line()
  local col = vim.api.nvim_win_get_cursor(0)[2] + 1
  local before = col > 1 and line:sub(1, col - 1):reverse():match(match):reverse() or ""
  local after = line:sub(col):match(match) or ""
  -- special case when the cursor is on the left surrounding char
  if #before == 0 and #after == 0 and #line > col then
    col = col + 1
    after = line:sub(col):match(match) or ""
  end
  local cwd
  opts._cwd, cwd, opts.query = find_toplevel_cwd(before .. after, nil, nil)
  opts.prompt = path.add_trailing(opts._cwd or ".")
  opts.cwd = cwd or opts.cwd or uv.cwd()
  -- completion function rebuilds the line with the full path
  opts.complete = function(selected, o, l, _)
    -- query fuzzy matching is empty
    if #selected == 0 then return end
    local replace_at = col - #before
    local relpath = path.relative_to(path.entry_to_file(selected[1], o).path, opts.cwd)
    local before_path = replace_at > 1 and l:sub(1, replace_at - 1) or ""
    local rest_of_line = #l >= (col + #after) and l:sub(col + #after) or ""
    local resolved_path = opts._cwd and path.join({ opts._cwd, relpath }) or relpath
    return before_path .. resolved_path .. rest_of_line,
        -- this goes to `nvim_win_set_cursor` which is 0-based
        replace_at + #resolved_path - 2
  end
  return opts
end

M.path = function(opts)
  opts = config.normalize_opts(opts, "complete_path")
  if not opts then return end
  opts.cmd = opts.cmd or (function()
    if vim.fn.executable("fdfind") == 1 then
      return "fdfind --strip-cwd-prefix"
    elseif vim.fn.executable("fd") == 1 then
      return "fd --strip-cwd-prefix"
    elseif utils.__IS_WINDOWS then
      return "dir /s/b"
    else
      return [[find ! -path '.' ! -path '*/\.git/*' -printf '%P\n']]
    end
  end)()
  opts = set_cmp_opts_path(opts)
  local contents = core.mt_cmd_wrapper(opts)
  return core.fzf_exec(contents, opts)
end

M.file = function(opts)
  opts = config.normalize_opts(opts, "complete_file")
  if not opts then return end
  opts.cmp_is_file = true
  opts.cmd = opts.cmd or (function()
    if vim.fn.executable("fdfind") == 1 then
      return "fdfind --strip-cwd-prefix --type f --exclude .git"
    elseif vim.fn.executable("fd") == 1 then
      return "fd --strip-cwd-prefix --type f --exclude .git"
    elseif vim.fn.executable("rg") == 1 then
      return "rg --files"
    elseif utils.__IS_WINDOWS then
      return "dir /s/b"
    else
      return [[find -type f ! -path '*/\.git/*' -printf '%P\n']]
    end
  end)()
  opts = set_cmp_opts_path(opts)
  local contents = core.mt_cmd_wrapper(opts)
  return core.fzf_exec(contents, opts)
end

M.line = function(opts)
  opts = config.normalize_opts(opts, "complete_line")
  opts.query = (function()
    local col = vim.api.nvim_win_get_cursor(0)[2] + 1
    local line = vim.api.nvim_get_current_line()
    return vim.trim(line:sub(1, col))
  end)()
  opts.complete = function(selected, _, _, _)
    local newline = selected[1]:match(" (.-)$")
    return newline, #newline
  end
  return require "fzf-lua.providers.buffers".lines(opts)
end

M.bline = function(opts)
  opts = opts or {}
  opts.current_buffer_only = true
  return M.line(opts)
end

return M
