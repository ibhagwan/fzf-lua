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

---@param opts fzf-lua.config.GitFiles|{}?
---@return thread?, string?, table?
M.files = function(opts)
  ---@type fzf-lua.config.GitFiles
  opts = config.normalize_opts(opts, "git.files")
  if not opts then return end
  opts = set_git_cwd_args(opts)
  if not opts.cwd then return end
  return core.fzf_exec(opts.cmd, opts)
end

---@param opts fzf-lua.config.GitStatus|{}?
---@return thread?, string?, table?
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
  -- Normalize the cwd passed to git_preview() so that it is the closest
  -- directory up the path that is a Git repo. git_diff() passes file
  -- paths relative to the Git repo root so to ensure the previewer
  -- can interpret the paths correctly, it must use the repo root as cwd.
  opts.cwd = path.git_root(opts)
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

---@param opts fzf-lua.config.GitBase|{}?
---@param ref string
---@return boolean
local git_validate_ref = function(opts, ref)
  local cmd = path.git_cwd({ "git", "rev-parse", "--verify", ref }, opts --[[@as table]])
  local _, exit_code = utils.io_systemlist(cmd --[[@as string[] ]])
  if exit_code ~= 0 then
    utils.warn("Invalid git ref %s", ref)
    return false
  end
  return true
end

---@param opts fzf-lua.config.GitDiff|fzf-lua.config.GitHunks
---@return table?
local normalize_diff_opts = function(opts)
  -- Backward compat `compare_against` -> `ref1`
  ---@diagnostic disable-next-line: undefined-field
  opts.ref1 = opts.compare_against or opts.ref1
  -- Convinience: ref as string array
  if type(opts.ref) == "table" then
    opts.ref, opts.ref1 = opts.ref[1], (opts.ref[2] or opts.ref1)
  end
  -- Ensure supplied refs are valid in this git repository.
  for _, r in ipairs({ "ref", "ref1" }) do
    if type(opts[r]) == "string" and #opts[r] > 0 and not git_validate_ref(opts, opts[r]) then
      return
    end
  end
  -- If no ref was supplied default to last commit, otherwise compare against the index
  if not opts.ref and not opts.ref1 then
    local cmd = path.git_cwd(
      { "git", "-c", "color.status=false", "--no-optional-locks", "status", "--porcelain=v1" },
      opts --[[@as table]])
    local out, exit_code = utils.io_systemlist(cmd --[[@as string[] ]])
    if exit_code == 0 and #out == 0 then
      opts.ref = "HEAD^"
    else
      opts.ref = "HEAD"
    end
  end
  opts.cmd = opts.cmd:gsub("[<{]ref[}>]", opts.ref or "")
  opts.cmd = opts.cmd:gsub("[<{]ref1[}>]", opts.ref1 or "")
  opts.cmd = opts.cmd:gsub("[<{]file[}>]", opts.file and libuv.shellescape(opts.file) or "")
  if type(opts.preview) == "string" then
    opts.preview = opts.preview:gsub("[<{]ref[}>]", opts.ref or "")
    opts.preview = opts.preview:gsub("[<{]ref1[}>]", opts.ref1 or "")
    opts.preview = git_preview(opts, "{-1}")
  end
  if type(opts._headers) == "table" then
    table.insert(opts._headers, "ref")
    table.insert(opts._headers, "ref1")
  end
  return set_git_cwd_args(opts)
end

---@param opts fzf-lua.config.GitDiff|{}?
---@return thread?, string?, table?
M.diff = function(opts)
  ---@type fzf-lua.config.GitDiff
  opts = config.normalize_opts(opts, "git.diff")
  if not opts then return end
  opts = normalize_diff_opts(opts)
  if not opts or not opts.cwd then return end
  return core.fzf_exec(opts.cmd, opts)
end


---@param opts fzf-lua.config.GitHunks|{}?
---@return thread?, string?, table?
M.hunks = function(opts)
  ---@type fzf-lua.config.GitHunks
  opts = config.normalize_opts(opts, "git.hunks")
  if not opts then return end
  opts = normalize_diff_opts(opts)
  if not opts or not opts.cwd then return end

  -- we don't need git icons since we get them
  -- as part of our `git status -s`
  opts.git_icons = false

  return core.fzf_exec(opts.cmd, opts)
end

---@param opts fzf-lua.config.GitCommits|{}?
---@return thread?, string?, table?
M.commits = function(opts)
  ---@type fzf-lua.config.GitCommits
  opts = config.normalize_opts(opts, "git.commits")
  if not opts then return end
  opts.preview = git_preview(opts)
  return git_cmd(opts)
end

---@param opts fzf-lua.config.GitReflog|{}?
---@return thread?, string?, table?
M.reflog = function(opts)
  ---@type fzf-lua.config.GitReflog
  opts = config.normalize_opts(opts, "git.reflog")
  if not opts then return end
  opts.preview = git_preview(opts)
  return git_cmd(opts)
end

---@param opts fzf-lua.config.GitBcommits|{}?
---@return thread?, string?, table?
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

---@param opts fzf-lua.config.GitBlame|{}?
---@return thread?, string?, table?
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

---@param line string
---@return string
local function highlight_branch_line(line)
  local u = FzfLua.utils
  local ansi = u.ansi_codes
  line = u.strip_ansi_coloring(line)
  local leader = line:sub(1, 2)
  local rest = line:sub(3)

  local detached_inner = rest:match("^%(([^)]+)%)")
  if detached_inner and
      (detached_inner:match("^HEAD detached") or detached_inner:match("^no branch")) then
    local head = ansi.grey("(") .. ansi.green(detached_inner) .. ansi.grey(")")
    local after = rest:sub(#detached_inner + 3)
    local ws, sha, subject_ws, subject = after:match("^(%s+)(%x%x%x%x%x%x%x+)(%s+)(.*)$")
    if ws and sha then
      return leader .. head .. ws .. ansi.yellow(sha) .. subject_ws .. subject
    end
    return leader .. head .. after
  end

  local branch_name, ws_after_name, after = rest:match("^(%S+)(%s+)(.*)$")
  if not branch_name then return line end

  local colored_branch
  if leader:sub(1, 1) == "*" then
    colored_branch = ansi.green(branch_name)
  elseif leader:sub(1, 1) == "+" then
    colored_branch = ansi.cyan(branch_name)
  elseif branch_name:match("^remotes/") then
    colored_branch = ansi.red(branch_name)
  else
    colored_branch = branch_name
  end

  if after:match("^%->") then
    return leader .. colored_branch .. ws_after_name .. after
  end

  local sha, body_ws, body = after:match("^(%x%x%x%x%x%x%x+)(%s+)(.*)$")
  if not sha then
    return leader .. colored_branch .. ws_after_name .. after
  end

  local function color_tracking(content)
    local ref, suffix = content:match("^([^:]+)(:.*)$")
    if ref and suffix then
      return ansi.grey("[") .. ansi.blue(ref) .. ansi.grey(suffix) .. ansi.grey("]")
    end
    return ansi.grey("[") .. ansi.blue(content) .. ansi.grey("]")
  end

  if leader:sub(1, 1) == "+" then
    local wt_paren, remainder = body:match("^(%b())(.*)$")
    if wt_paren then
      local colored_wt = ansi.grey("(") .. ansi.cyan(wt_paren:sub(2, -2)) .. ansi.grey(")")
      remainder = remainder:gsub("^(%s*)(%[)([^%]]+)(%])", function(ws, _, content, _)
        return ws .. color_tracking(content)
      end)
      body = colored_wt .. remainder
    end
  else
    body = body:gsub("^(%[)([^%]]+)(%])", function(_, content, _)
      return color_tracking(content)
    end)
  end

  return leader .. colored_branch .. ws_after_name .. ansi.yellow(sha) .. body_ws .. body
end

---@param line string
---@return string
local function highlight_worktree_line(line)
  local ansi = FzfLua.utils.ansi_codes
  local path_s, padding, rest = line:match("^(%S+)(%s+)(.*)$")
  if not path_s then return line end

  local sha, sha_ws, body = rest:match("^(%x%x%x%x%x%x%x+)(%s+)(.*)$")
  if not sha then
    body = rest
  end

  body = body:gsub("^(%[)([^%]]+)(%])", function(lb, name, rb)
    return ansi.grey(lb) .. ansi.green(name) .. ansi.grey(rb)
  end)
  body = body:gsub("^(%()(detached HEAD)(%))", function(lp, text, rp)
    return ansi.grey(lp) .. ansi.green(text) .. ansi.grey(rp)
  end)
  body = body:gsub("^(%()(bare)(%))", function(lp, text, rp)
    return ansi.grey(lp) .. ansi.grey(text) .. ansi.grey(rp)
  end)
  body = body:gsub("(%s)(locked)(%s*)$", function(s1, w, s2)
    return s1 .. ansi.magenta(w) .. s2
  end)
  body = body:gsub("(%s)(prunable)(%s*)$", function(s1, w, s2)
    return s1 .. ansi.red(w) .. s2
  end)

  local out = ansi.blue(path_s) .. padding
  if sha then
    out = out .. ansi.yellow(sha) .. sha_ws
  end
  return out .. body
end

---@param opts fzf-lua.config.GitBranches|{}?
---@return thread?, string?, table?
M.branches = function(opts)
  ---@type fzf-lua.config.GitBranches
  opts = config.normalize_opts(opts, "git.branches")
  if not opts then return end
  if opts.fn_transform == nil then opts.fn_transform = highlight_branch_line end
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
      if not items[1] then return utils.shell_nop() end
      -- git bisect detached preview (#2441)
      if items[1]:match("%(no branch, bisect") then
        items[1] = items[1]:gsub("%(no.-%)", " ")
      end
      local branch = assert(items[1]:match("^[%*+]*[%s]*[(]?([^%s)]+)"))
      return (preview:gsub("{.*}", branch))
    end, opts, "{}")
  end
  return git_cmd(opts)
end

---@param opts fzf-lua.config.GitWorktrees|{}?
---@return thread?, string?, table?
M.worktrees = function(opts)
  ---@type fzf-lua.config.GitWorktrees
  opts = config.normalize_opts(opts, "git.worktrees")
  if not opts then return end
  if opts.fn_transform == nil then opts.fn_transform = highlight_worktree_line end
  if opts.preview then
    local preview_cmd = opts.preview
    opts.preview = shell.stringify_cmd(function(items)
      if not items[1] then return utils.shell_nop() end
      local cwd = items[1]:match("^[^%s]+")
      local cmd = path.git_cwd(preview_cmd, { cwd = cwd })
      return cmd
    end, opts, "{}")
  end
  return git_cmd(opts)
end

---@param opts fzf-lua.config.GitTags|{}?
---@return thread?, string?, table?
M.tags = function(opts)
  ---@type fzf-lua.config.GitTags
  opts = config.normalize_opts(opts, "git.tags")
  if not opts then return end
  return git_cmd(opts)
end

---@param opts fzf-lua.config.GitStash|{}?
---@return thread?, string?, table?
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

return M
