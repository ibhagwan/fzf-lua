local core = require "fzf-lua.core"
local path = require "fzf-lua.path"
local config = require "fzf-lua.config"
local actions = require "fzf-lua.actions"

local M = {}

-- get the completion string under the cursor, this is the string
-- that will be replaced by `actions.complete_insert` once the user
-- has made their selection
-- we match the string before and after using a lua pattern
-- by default, we use "[^%p%s]" which stop at spaces and punctuation marks
-- when scanning for files/paths we use "[^%s\"']*" which stops at spaces
-- and single/double quotes
local get_cmp_params = function(match)
  -- returns { row, col }, col is 0-index base
  -- i.e. first col of first line is  { 1, 0 }
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line = vim.api.nvim_get_current_line()
  if type(match) == "string" then
    local after = cursor[2] > 0 and line:sub(cursor[2] + 1):match(match) or nil
    local before = line:sub(1, cursor[2]):reverse():match(match)
    -- can be nil if cursor is at col 1
    before = before and before:reverse() or nil
    local str = before and before .. (after or "") or nil
    local col = cursor[2] - (before and #before or 0) + 1
    return str, col, cursor[1]
  else
    local str = cursor[2] > 0 and line:sub(1, cursor[2] + 1) or ""
    return str, 1, cursor[1]
  end
end

-- Given a path, attempt to find the first existing directory
-- returns a pair: the directory to be used as `cwd` and fzf's
-- "--query" argument to be entered into the prompt automatically
local function find_toplevel_cwd(maybe_cwd, postfix)
  if not maybe_cwd or #maybe_cwd == 0 then
    return "./", nil
  end
  if vim.fn.isdirectory(vim.fn.expand(maybe_cwd)) == 1 then
    return maybe_cwd, postfix
  end
  postfix = vim.fn.fnamemodify(maybe_cwd, ":t")
  maybe_cwd = vim.fn.fnamemodify(maybe_cwd, ":h")
  return find_toplevel_cwd(maybe_cwd, postfix)
end

-- Set generic options for completion functions
-- extracts the completion string to be substituted, row/col and mode
local set_cmp_opts = function(opts)
  opts = vim.tbl_deep_extend("keep", opts or {}, {
    cmp_match = "[^%p%s]*",
    actions = { default = actions.complete_insert }
  })
  -- NOTE: `__fn_pre_fzf` is called before (non-underscore) `fn_pre_fzf`
  -- so that `set_cmp_opts_path` can rely on `opts.cmp_string` being set
  opts.__fn_pre_fzf = function(o)
    o.cmp_mode = vim.api.nvim_get_mode().mode
    o.cmp_string, o.cmp_string_col, o.cmp_string_row = get_cmp_params(o.cmp_match)
  end
  return opts
end

-- Set specific options for path completions
-- splits the completion string to a valid cwd and postfix
-- which will then be sent to fzf as "--query"
local set_cmp_opts_path = function(opts)
  opts = opts or {}
  opts.cmp_match = opts.cmp_match or "[^%s\"']*"
  opts._fn_pre_fzf = function(o)
    o.cwd, o.query = find_toplevel_cwd(o.cmp_string, nil)
    o.prompt = o.cwd
    if not path.ends_with_separator(o.prompt) then
      o.prompt = o.prompt .. path.separator()
    end
    o.cwd = vim.fn.expand(o.cwd)
    o.cmp_prefix = o.prompt
  end
  -- set generic options after setting the above so `cmp_match`
  -- doesn't get ignored
  opts = set_cmp_opts(opts)
  return opts
end

local set_cmp_opts_line = function(opts)
  opts = opts or {}
  -- false tells `get_cmp_params` to replace col 1 to cursor
  opts.cmp_match = false
  opts.cmp_is_line = true
  opts._fn_pre_fzf = function(o)
    o.query = o.cmp_string
  end
  opts = set_cmp_opts(opts)
  return opts
end

M.fzf_complete = function(contents, opts)
  opts = set_cmp_opts(opts)
  return core.fzf_exec(contents, opts)
end

M.path = function(opts)
  opts = opts or {}
  opts.cmd = opts.cmd or (function()
    if vim.fn.executable("fdfind") == 1 then
      return "fdfind"
    elseif vim.fn.executable("fd") == 1 then
      return "fd"
    elseif vim.fn.executable("rg") == 1 then
      return "rg --files"
    else
      return [[find ! -path '.' ! -path '*/\.git/*' -printf '%P\n']]
    end
  end)()
  opts = set_cmp_opts_path(opts)
  return core.fzf_exec(opts.cmd, opts)
end

M.file = function(opts)
  opts = config.normalize_opts(opts, config.globals.complete_file)
  if not opts then return end
  opts.cmp_is_file = true
  opts.cmd = opts.cmd or (function()
    if vim.fn.executable("rg") == 1 then
      return "rg --files"
    elseif vim.fn.executable("fdfind") == 1 then
      return "fdfind --type f --exclude .git"
    elseif vim.fn.executable("fd") == 1 then
      return "fd --type f --exclude .git"
    else
      return [[find -type f ! -path '*/\.git/*' -printf '%P\n']]
    end
  end)()
  opts = set_cmp_opts_path(opts)
  local contents = core.mt_cmd_wrapper(opts)
  return core.fzf_exec(contents, opts)
end

M.line = function(opts)
  opts = config.normalize_opts(opts, config.globals.complete_line)
  opts = set_cmp_opts_line(opts)
  return require "fzf-lua.providers.buffers".lines(opts)
end

M.bline = function(opts)
  opts = config.normalize_opts(opts, config.globals.complete_bline)
  opts = set_cmp_opts_line(opts)
  return require "fzf-lua.providers.buffers".blines(opts)
end

return M
