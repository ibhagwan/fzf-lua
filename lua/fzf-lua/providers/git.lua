if not pcall(require, "fzf") then
  return
end

local fzf = require "fzf"
local fzf_helpers = require("fzf.helpers")
local core = require "fzf-lua.core"
local utils = require "fzf-lua.utils"
local config = require "fzf-lua.config"
local actions = require "fzf-lua.actions"

local M = {}

local function git_status()
  local output = vim.fn.systemlist("git status")
  if utils.shell_error() then
    utils.info(unpack(output))
    return false
  end
  return true
end

M.files = function(opts)
  if not git_status() then return end
  opts = config.normalize_opts(opts, config.globals.git.files)
  opts.fzf_fn = fzf_helpers.cmd_line_transformer(opts.cmd,
    function(x)
      return core.make_entry_file(opts, x)
    end)
  return core.fzf_files(opts)
end

M.status = function(opts)
  if not git_status() then return end
  opts = config.normalize_opts(opts, config.globals.git.status)
  if opts.preview then opts.preview = vim.fn.shellescape(opts.preview) end
  opts.fzf_fn = fzf_helpers.cmd_line_transformer(opts.cmd,
    function(x)
      -- greedy match anything after last space
      x = x:match("[^ ]*$")
      return core.make_entry_file(opts, x)
    end)
  return core.fzf_files(opts)
end

local function git_cmd(opts)
  if not git_status() then return end
  coroutine.wrap(function ()
    opts.fzf_fn = fzf_helpers.cmd_line_transformer(opts.cmd,
      function(x) return x end)
    local selected = fzf.fzf(opts.fzf_fn,
      core.build_fzf_cli(opts, false),
      config.winopts(opts))
    if not selected then return end
    actions.act(opts.actions, selected)
  end)()
end

M.commits = function(opts)
  opts = config.normalize_opts(opts, config.globals.git.commits)
  opts.preview = vim.fn.shellescape(opts.preview)
  return git_cmd(opts)
end

M.bcommits = function(opts)
  opts = config.normalize_opts(opts, config.globals.git.bcommits)
  local file = vim.fn.shellescape(vim.fn.expand("%"))
  opts.cmd = opts.cmd .. " " .. file
  opts.preview = opts.preview .. " --rotate-to=" .. file
  opts.preview = vim.fn.shellescape(opts.preview)
  return git_cmd(opts)
end

M.branches = function(opts)
  opts = config.normalize_opts(opts, config.globals.git.branches)
  opts._preview = opts.preview
  opts.preview = fzf_helpers.choices_to_shell_cmd_previewer(function(items)
    local branch = items[1]:gsub("%*", "")  -- remove the * from current branch
    if branch:find("%)") ~= nil then
      -- (HEAD detached at origin/master)
      branch = branch:match(".* ([^%)]+)") or ""
    else
      -- remove anything past space
      branch = branch:match("[^ ]+")
    end
    return opts._preview:gsub("{.*}", branch)
    -- return "echo " .. branch
  end)
  return git_cmd(opts)
end

return M
