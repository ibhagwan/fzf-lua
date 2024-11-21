local core = require "fzf-lua.core"
local shell = require "fzf-lua.shell"
local utils = require "fzf-lua.utils"
local config = require "fzf-lua.config"
local make_entry = require "fzf-lua.make_entry"

local M = {}

M.buffers = function(opts)
  opts = config.normalize_opts(opts, "tmux.buffers")
  if not opts then return end

  opts.fn_transform = function(x)
    local buf, data = x:match([[^(.-):%s+%d+%s+bytes: "(.*)"$]])
    return string.format("[%s] %s", utils.ansi_codes.yellow(buf), data)
  end

  opts.fzf_opts["--preview"] = shell.raw_preview_action_cmd(function(items)
    local buf = items[1]:match("^%[(.-)%]")
    return string.format("tmux show-buffer -b %s", buf)
  end, opts.debug)

  core.fzf_exec(opts.cmd, opts)
end

local get_files_cmd = function(opts)
  local command = nil
  if vim.fn.executable("fdfind") == 1 then
    command = { "fdfind", "--color=never", "--type", "f", "--hidden", "--follow", "--exclude", ".git" }
  elseif vim.fn.executable("fd") == 1 then
    command = { "fd", "--color=never", "--type", "f", "--hidden", "--follow", "--exclude", ".git" }
  elseif vim.fn.executable("rg") == 1 then
    command = { "rg", "--color=never", "--files", "--hidden", "--follow", "-g", "!.git" }
  elseif utils.__IS_WINDOWS then
    command = { "dir", "/s/b/a:-d" }
  else
    POSIX_find_compat(opts.find_opts)
    command = { "find", "-L", ".", "-type", "f", "-not", "-path", "'*\\.git\\*'", "-printf", "'%P\\n'" }
  end
  return command
end

M.files = function(opts)
  opts = config.normalize_opts(opts, "tmux.files")
  if not opts then return end

  local project_files = {}
  if opts.project_only then
    local project_files_cmd = get_files_cmd(opts)
    local text = vim.system(project_files_cmd, { text = true }):wait().stdout
    for line in string.gmatch(text, "[^\n]+") do
      table.insert(project_files, line)
    end
  end

  opts.fn_transform = function(x)
    x = vim.trim(x)
    if opts.project_only then
      for _, v in ipairs(project_files) do
        local pattern = utils.lua_regex_escape(v)
        if string.match(x, pattern) then
          return make_entry.file(x, opts)
        end
      end
    else
      return make_entry.file(x, opts)
    end
  end

  opts = core.set_fzf_field_index(opts)
  core.fzf_exec(opts.cmd, opts)
end

return M
