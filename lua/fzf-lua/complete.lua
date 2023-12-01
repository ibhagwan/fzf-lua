local core = require "fzf-lua.core"
local config = require "fzf-lua.config"

local M = {}

local NAME_REGEX = '\\%([^/\\\\:\\*?<>\'"`\\|]\\)'
local PATH_REGEX = vim.regex(([[\%(\%(/PAT*[^/\\\\:\\*?<>\'"`\\| .~]\)\|\%(/\.\.\)\)*/\zePAT*$]]):gsub("PAT", NAME_REGEX))

local get_cwd = function(bufnr)
  return vim.fn.expand(("#%d:p:h"):format(bufnr))
end

local _is_slash_comment = function(_)
  local commentstring = vim.bo.commentstring or ""
  local no_filetype = vim.bo.filetype == ""
  local is_slash_comment = false
  is_slash_comment = is_slash_comment or commentstring:match("/%*")
  is_slash_comment = is_slash_comment or commentstring:match("//")
  return is_slash_comment and not no_filetype
end

local function find_file_path(cursor_before_line)
  local s = PATH_REGEX:match_str(cursor_before_line)
  if not s then
    return nil
  end

  local dirname = string.gsub(string.sub(cursor_before_line, s + 2), "%a*$", "") -- exclude '/'
  local prefix = string.sub(cursor_before_line, 1, s + 1) -- include '/'

  local buf_dirname = get_cwd(vim.fn.bufnr("%"))
  if vim.api.nvim_get_mode().mode == "c" then
    buf_dirname = vim.fn.getcwd()
  end
  if prefix:match("%.%./$") then
    return vim.fn.resolve(buf_dirname .. "/../" .. dirname)
  end
  if (prefix:match("%./$") or prefix:match('"$') or prefix:match("\'$")) then
    return vim.fn.resolve(buf_dirname .. "/" .. dirname)
  end
  if prefix:match("~/$") then
    return vim.fn.resolve(vim.fn.expand("~") .. "/" .. dirname)
  end
  local env_var_name = prefix:match("%$([%a_]+)/$")
  if env_var_name then
    local env_var_value = vim.fn.getenv(env_var_name)
    if env_var_value ~= vim.NIL then
      return vim.fn.resolve(env_var_value .. "/" .. dirname)
    end
  end
  if prefix:match("/$") then
    local accept = true
    -- Ignore URL components
    accept = accept and not prefix:match("%a/$")
    -- Ignore URL scheme
    accept = accept and not prefix:match("%a+:/$") and not prefix:match("%a+://$")
    -- Ignore HTML closing tags
    accept = accept and not prefix:match("</$")
    -- Ignore math calculation
    accept = accept and not prefix:match("[%d%)]%s*/$")
    -- Ignore / comment
    accept = accept and (not prefix:match("^[%s/]*$") or not _is_slash_comment())
    if accept then
      return vim.fn.resolve("/" .. dirname)
    end
  end
  return nil
end

-- get search prompt
local function get_prompt(filepath)
  local cwd = vim.fn.getcwd()
  -- if path include "-", replace it
  local pattern = cwd:gsub("-", "")
  local input_string = filepath:gsub("-", "")
  local relative_path = input_string:gsub(pattern, "")
  local prompt = relative_path:gsub(vim.env.HOME, "~")
  if prompt:sub(1, 1) == "/" then
    prompt = "~" .. prompt:sub(1)
  end
  return prompt
end

-- forward and reverse match spaces and single/double quotes
-- and attepmpt to find the top level existing directory
-- set the cwd and prompt top the top level directory and
-- the leftover match to the input query
local set_cmp_opts_path = function(opts)
  local match = "[^%s\"'()[]*"
  local line = vim.api.nvim_get_current_line()
  local col = vim.api.nvim_win_get_cursor(0)[2] + 1
  local before = col > 1 and line:sub(1, col - 1):reverse():match(match):reverse() or ""
  local after = line:sub(col):match(match) or ""
  -- special case when the cursor is on the left surrounding char
  if #before == 0 and #after == 0 and #line > col then
    col = col + 1
    after = line:sub(col):match(match) or ""
  end
  opts.cwd = find_file_path(before)
  opts.prompt = get_prompt(opts.cwd)
  opts.complete = function(selected, o, l, _)
    -- query fuzzy matching is empty
    if #selected == 0 then return end
    return line:sub(1, col - 1) .. selected[1] .. line:sub(col), col + #selected[1]
  end
  return opts
end

M.path = function(opts)
  opts = config.normalize_opts(opts, "complete_path")
  if not opts then return end
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
  local contents = core.mt_cmd_wrapper(opts)
  return core.fzf_exec(contents, opts)
end

M.file = function(opts)
  opts = config.normalize_opts(opts, "complete_file")
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
  opts = config.normalize_opts(opts, "complete_line")
  opts.query = (function()
    local col = vim.api.nvim_win_get_cursor(0)[2] + 1
    local line = vim.api.nvim_get_current_line()
    return #line > col and vim.trim(line:sub(1, col)) or nil
  end)()
  opts.complete = function(selected, _, _, _)
    local newline = selected[1]:match("^.*:%d+:%s(.*)")
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
