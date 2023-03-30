local core = require "fzf-lua.core"
local path = require "fzf-lua.path"
local utils = require "fzf-lua.utils"
local config = require "fzf-lua.config"
local libuv = require "fzf-lua.libuv"
local shell = require "fzf-lua.shell"
local make_entry = require "fzf-lua.make_entry"

local M = {}

local function set_git_cwd_args(opts)
  -- verify cwd is a git repo, override user supplied
  -- cwd if cwd isn't a git repo, error was already
  -- printed to `:messages` by 'path.git_root'
  local git_root = path.git_root(opts)
  if not opts.cwd or not git_root then
    opts.cwd = git_root
  end
  if opts.git_dir or opts.git_worktree then
    opts.cmd = path.git_cwd(opts.cmd, opts)
  end
  return opts
end

M.files = function(opts)
  opts = config.normalize_opts(opts, config.globals.git.files)
  if not opts then return end
  opts = set_git_cwd_args(opts)
  if not opts.cwd then return end
  local contents = core.mt_cmd_wrapper(opts)
  opts = core.set_header(opts, opts.headers or { "cwd" })
  return core.fzf_exec(contents, opts)
end

M.status = function(opts)
  opts = config.normalize_opts(opts, config.globals.git.status)
  if not opts then return end
  opts = set_git_cwd_args(opts)
  if not opts.cwd then return end
  if opts.preview then
    opts.preview = path.git_cwd(opts.preview, opts)
  end
  -- we don't need git icons since we get them
  -- as part of our `git status -s`
  opts.git_icons = false
  if not opts.no_header then
    local stage = utils.ansi_codes.yellow("<left>")
    local unstage = utils.ansi_codes.yellow("<right>")
    opts.fzf_opts["--header"] = vim.fn.shellescape(
      ("+ - :: %s to stage, %s to unstage"):format(stage, unstage))
  end
  local function git_iconify(x)
    local icon = x
    local git_icon = config.globals.git.icons[x]
    if git_icon then
      icon = git_icon.icon
      if opts.color_icons then
        icon = utils.ansi_codes[git_icon.color or "dark_grey"](icon)
      end
    end
    return icon
  end

  local contents = libuv.spawn_nvim_fzf_cmd(opts,
    function(x)
      -- unrecognizable format, return
      if not x or #x < 4 then return x end
      -- strip ansi coloring or the pattern matching fails
      -- when git config has `color.status=always` (#706)
      x = utils.strip_ansi_coloring(x)
      -- `man git-status`
      -- we are guaranteed format of: XY <text>
      -- spaced files are wrapped with quotes
      -- remove both git markers and quotes
      local f1, f2 = x:sub(4):gsub([["]], ""), nil
      -- renames separate files with '->'
      if f1:match("%s%->%s") then
        f1, f2 = f1:match("(.*)%s%->%s(.*)")
      end
      f1 = f1 and make_entry.file(f1, opts)
      -- accomodate 'file_ignore_patterns'
      if not f1 then return end
      f2 = f2 and make_entry.file(f2, opts)
      local staged = git_iconify(x:sub(1, 1):gsub("?", " "))
      local unstaged = git_iconify(x:sub(2, 2))
      local entry = ("%s%s%s%s%s"):format(
        staged, utils.nbsp, unstaged, utils.nbsp .. utils.nbsp,
        (f2 and ("%s -> %s"):format(f1, f2) or f1))
      return entry
    end,
    function(o)
      return make_entry.preprocess(o)
    end)
  opts = core.set_header(opts, opts.headers or { "cwd" })
  return core.fzf_exec(contents, opts)
end

local function git_cmd(opts)
  opts = set_git_cwd_args(opts)
  if not opts.cwd then return end
  opts = core.set_header(opts, opts.headers or { "cwd" })
  core.fzf_exec(opts.cmd, opts)
end

M.commits = function(opts)
  opts = config.normalize_opts(opts, config.globals.git.commits)
  if not opts then return end
  if opts.preview then
    opts.preview = path.git_cwd(opts.preview, opts)
    if opts.preview_pager then
      opts.preview = string.format("%s | %s", opts.preview, opts.preview_pager)
    end
  end
  return git_cmd(opts)
end

M.bcommits = function(opts)
  opts = config.normalize_opts(opts, config.globals.git.bcommits)
  if not opts then return end
  local bufname = vim.api.nvim_buf_get_name(0)
  if not bufname or #bufname == 0 then
    utils.info("'bcommits' is not available for unnamed buffers.")
    return
  end
  -- if caller did not specify cwd, we attempt to auto detect the
  -- file's git repo from its parent folder. Could be further
  -- optimized to prevent the duplicate call to `git rev-parse`
  -- but overall it's not a big deal as it's a pretty cheap call
  -- first 'git_root' call won't print a warning to ':messages'
  if not opts.cwd and not opts.git_dir then
    opts.cwd = path.git_root({ cwd = vim.fn.expand("%:p:h") }, true)
  end
  local git_root = path.git_root(opts)
  if not git_root then return end
  local file = path.relative(vim.fn.expand("%:p"), git_root)
  if opts.cmd:match("<file") then
    opts.cmd = opts.cmd:gsub("<file>", file)
  else
    opts.cmd = opts.cmd .. " " .. file
  end
  if type(opts.preview) == "string" then
    opts.preview = opts.preview:gsub("<file>", vim.fn.shellescape(file))
    opts.preview = path.git_cwd(opts.preview, opts)
    if opts.preview_pager then
      opts.preview = string.format("%s | %s", opts.preview, opts.preview_pager)
    end
  end
  return git_cmd(opts)
end

M.branches = function(opts)
  opts = config.normalize_opts(opts, config.globals.git.branches)
  if not opts then return end
  opts.fzf_opts["--no-multi"] = ""
  if opts.preview then
    opts.__preview = path.git_cwd(opts.preview, opts)
    opts.preview = shell.raw_preview_action_cmd(function(items)
      -- all possible options:
      --   branch
      -- * branch
      --   remotes/origin/branch
      --   (HEAD detached at origin/branch)
      local branch = items[1]:match("[^%s%*]*$"):gsub("%)$", "")
      return opts.__preview:gsub("{.*}", branch)
    end, nil, opts.debug)
  end
  return git_cmd(opts)
end

M.stash = function(opts)
  opts = config.normalize_opts(opts, config.globals.git.stash)
  if not opts then return end

  if opts.preview then
    opts.preview = path.git_cwd(opts.preview, opts)
  end

  if opts.fzf_opts["--header"] == nil then
    opts.fzf_opts["--header"] = vim.fn.shellescape((":: %s to drop selected stash(es)")
      :format(utils.ansi_codes.yellow("<Ctrl-x>")))
  end

  opts.cmd = libuv.spawn_nvim_fzf_cmd(
    { cmd = opts.cmd, cwd = opts.cwd },
    function(x)
      local stash, rest = x:match("([^:]+)(.*)")
      if stash then
        stash = utils.ansi_codes.yellow(stash)
        stash = stash:gsub("{%d+}", function(s)
          return ("%s"):format(utils.ansi_codes.green(tostring(s)))
        end)
      end
      return (not stash or not rest) and x or stash .. rest
    end)

  return git_cmd(opts)
end

return M
