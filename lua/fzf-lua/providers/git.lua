local core = require "fzf-lua.core"
local path = require "fzf-lua.path"
local libuv = require "fzf-lua.libuv"
local utils = require "fzf-lua.utils"
local config = require "fzf-lua.config"
local shell = require "fzf-lua.shell"

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
  ---@type fzf-lua.config.GitFiles
  opts = config.normalize_opts(opts, "git.files")
  if not opts then return end
  opts = set_git_cwd_args(opts)
  if not opts.cwd then return end
  return core.fzf_exec(opts.cmd, opts)
end

M.status = function(opts)
  ---@type fzf-lua.config.GitStatus
  opts = config.normalize_opts(opts, "git.status")
  if not opts then return end
  opts = set_git_cwd_args(opts)
  if not opts.cwd then return end
  if opts.preview then
    opts.preview = path.git_cwd(opts.preview --[[@as string]], opts)
  end
  -- we don't need git icons since we get them
  -- as part of our `git status -s`
  opts.git_icons = false

  -- git status does not require preprocessing if not loading devicons
  -- opts.fn_preprocess = opts.file_icons
  --     and [[return require("fzf-lua.devicons").load()]]
  --     or [[return true]]
  --

  opts.header_prefix = opts.header_prefix or "+ -  "
  opts.header_separator = opts.header_separator or "|"

  return core.fzf_exec(opts.cmd, opts)
end

local function git_cmd(opts)
  opts = set_git_cwd_args(opts)
  if not opts.cwd then return end
  return core.fzf_exec(opts.cmd, opts)
end

local function git_preview(opts, file)
  if type(opts.preview) ~= "string" then return end
  if file then
    opts.preview = opts.preview:gsub("[<{]file[}>]", file)
  end
  opts.preview = path.git_cwd(opts.preview, opts)
  if type(opts.preview_pager) == "function" then
    opts.preview_pager = opts.preview_pager()
  end
  if opts.preview_pager then
    opts.preview = string.format("%s | %s", opts.preview,
      utils._if_win_normalize_vars(opts.preview_pager))
  end
  if vim.o.shell and vim.o.shell:match("fish$") then
    -- TODO: why does fish shell refuse to pass along $COLUMNS
    -- to delta while the same exact commands works with bcommits?
    opts.preview = "sh -c " .. libuv.shellescape(opts.preview)
  end
  return opts.preview
end

M.diff = function(opts)
  ---@type fzf-lua.config.GitDiff
  opts = config.normalize_opts(opts, "git.diff")
  if not opts then return end
  local cmd = path.git_cwd({ "git", "rev-parse", "--verify", opts.ref }, opts)
  local _, err = utils.io_systemlist(cmd)
  if err ~= 0 then
    utils.warn("Invalid git ref %s", opts.ref)
    return
  end
  for _, k in ipairs({ "cmd", "preview" }) do
    opts[k] = opts[k]:gsub("[<{]ref[}>]", opts.ref)
  end
  opts = set_git_cwd_args(opts)
  if not opts.cwd then return end
  opts.preview = git_preview(opts, "{-1}")
  return core.fzf_exec(opts.cmd, opts)
end

M.commits = function(opts)
  ---@type fzf-lua.config.GitCommits
  opts = config.normalize_opts(opts, "git.commits")
  if not opts then return end
  opts.preview = git_preview(opts)
  return git_cmd(opts)
end

M.bcommits = function(opts)
  ---@type fzf-lua.config.GitBcommits
  opts = config.normalize_opts(opts, "git.bcommits")
  if not opts then return end
  local bufname = vim.api.nvim_buf_get_name(0)
  if #bufname == 0 then
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
  local file = libuv.shellescape(path.relative_to(vim.fn.expand("%:p"), git_root))
  local range
  if utils.mode_is_visual() then
    local _, sel = utils.get_visual_selection()
    if not sel then return end
    range = string.format("-L %d,%d:%s --no-patch", sel.start.line, sel["end"].line, file)
    -- when range is specified remove "end of options" marker (#2375)
    opts.cmd = opts.cmd:gsub("%s+%-%-%s-$", " "):gsub("%-%-%s+[<{]file[}>]", " {file}")
  end
  if opts.cmd:match("[<{]file") then
    opts.cmd = opts.cmd:gsub("[<{]file[}>]", range or file)
  else
    opts.cmd = opts.cmd .. " " .. (range or file)
  end
  opts.preview = git_preview(opts, file)
  return git_cmd(opts)
end

M.blame = function(opts)
  ---@type fzf-lua.config.GitBlame
  opts = config.normalize_opts(opts, "git.blame")
  if not opts then return end
  local bufname = vim.api.nvim_buf_get_name(0)
  if #bufname == 0 then
    utils.info("'blame' is not available for unnamed buffers.")
    return
  end
  -- See "bcommits" for comment
  if not opts.cwd and not opts.git_dir then
    opts.cwd = path.git_root({ cwd = vim.fn.expand("%:p:h") }, true)
  end
  local git_root = path.git_root(opts)
  if not git_root then return end
  local file = libuv.shellescape(path.relative_to(vim.fn.expand("%:p"), git_root))
  local range
  if utils.mode_is_visual() then
    local _, sel = utils.get_visual_selection()
    if not sel then return end
    range = string.format("-L %d,%d %s", sel.start.line, sel["end"].line, file)
  end
  if opts.cmd:match("[<{]file") then
    opts.cmd = opts.cmd:gsub("[<{]file[}>]", range or file)
  else
    opts.cmd = opts.cmd .. " " .. (range or file)
  end
  opts.preview = git_preview(opts, file)
  return git_cmd(opts)
end

M.branches = function(opts)
  ---@type fzf-lua.config.GitBranches
  opts = config.normalize_opts(opts, "git.branches")
  if not opts then return end
  if opts.preview then
    local preview = path.git_cwd(opts.preview, opts)
    opts.preview = shell.stringify_cmd(function(items)
      -- The beginning of the selected line looks like the below,
      -- but we only want the string containing the branch name,
      -- so match the first sequence not including spaces:
      --   branch
      -- * branch
      --   remotes/origin/branch
      --   (HEAD detached at origin/branch)
      local branch = items[1]:match("^[%*+]*[%s]*[(]?([^%s)]+)")
      return (preview:gsub("{.*}", branch))
    end, opts, "{}")
  end
  return git_cmd(opts)
end

M.worktrees = function(opts)
  ---@type fzf-lua.config.GitWorktrees
  opts = config.normalize_opts(opts, "git.worktrees")
  if not opts then return end
  if opts.preview then
    local preview_cmd = opts.preview
    opts.preview = shell.stringify_cmd(function(items)
      local cwd = items[1]:match("^[^%s]+")
      local cmd = path.git_cwd(preview_cmd, { cwd = cwd })
      return cmd
    end, opts, "{}")
  end
  return git_cmd(opts)
end

M.tags = function(opts)
  ---@type fzf-lua.config.GitTags
  opts = config.normalize_opts(opts, "git.tags")
  if not opts then return end
  return git_cmd(opts)
end

M.stash = function(opts)
  ---@type fzf-lua.config.GitStash
  opts = config.normalize_opts(opts, "git.stash")
  if not opts then return end
  opts = set_git_cwd_args(opts)
  if not opts.cwd then return end

  opts.preview = git_preview(opts)

  if opts.search and opts.search ~= "" then
    -- search by stash content, git stash -G<regex>
    assert(type(opts.search) == "string")
    opts.cmd = opts.cmd .. " -G " .. libuv.shellescape(opts.search)
  end

  opts.fn_transform = function(x)
    local stash, rest = x:match("([^:]+)(.*)")
    if stash then
      stash = FzfLua.utils.ansi_codes.yellow(stash)
      stash = stash:gsub("{%d+}", function(s)
        return ("%s"):format(FzfLua.utils.ansi_codes.green(tostring(s)))
      end)
    end
    return (not stash or not rest) and x or stash .. rest
  end

  return core.fzf_exec(opts.cmd, opts)
end

M.hunks = function(opts)
  ---@type fzf-lua.config.GitHunks
  opts = config.normalize_opts(opts, "git.hunks")
  if not opts then return end
  local cmd = path.git_cwd({ "git", "rev-parse", "--verify", opts.ref }, opts)
  local _, err = utils.io_systemlist(cmd)
  if err ~= 0 then
    utils.warn("Invalid git ref %s", opts.ref)
    return
  end
  opts.cmd = opts.cmd:gsub("[<{]ref[}>]", opts.ref)
  opts = set_git_cwd_args(opts)
  if not opts.cwd then return end

  -- we don't need git icons since we get them
  -- as part of our `git status -s`
  opts.git_icons = false

  opts.header_prefix = opts.header_prefix or "+ -  "
  opts.header_separator = opts.header_separator or "|"

  return core.fzf_exec(opts.cmd, opts)
end

return M
