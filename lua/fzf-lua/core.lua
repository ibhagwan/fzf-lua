local fzf = require "fzf"
local path = require "fzf-lua.path"
local utils = require "fzf-lua.utils"
local config = require "fzf-lua.config"
local actions = require "fzf-lua.actions"

local M = {}

M.get_devicon = function(file, ext)
  local icon = nil
  if #file > 0 and pcall(require, "nvim-web-devicons") then
    icon = require'nvim-web-devicons'.get_icon(file, ext)
  end
  return utils._if(icon == nil, '', icon)
end

M.preview_cmd = function(opts, cfg)
  opts = opts or {}
  opts.filespec = opts.filespec or '{}'
  opts.preview_cmd = opts.preview_cmd or cfg.preview_cmd
  opts.preview_args = opts.preview_args or ''
  opts.bat_opts = opts.bat_opts or cfg.bat_opts
  local preview = nil
  if not opts.cwd then opts.cwd = ''
  elseif #opts.cwd > 0 then
    opts.cwd = path.add_trailing(opts.cwd)
  end
  if opts.preview_cmd and #opts.preview_cmd > 0 then
    preview = string.format("%s %s -- %s%s", opts.preview_cmd, opts.preview_args, opts.cwd, opts.filespec)
  elseif vim.fn.executable("bat") == 1 then
    preview = string.format("bat %s %s -- %s%s", opts.bat_opts, opts.preview_args, opts.cwd, opts.filespec)
  else
    preview = string.format("head -n $FZF_PREVIEW_LINES %s -- %s%s", opts.preview_args, opts.cwd, opts.filespec)
  end
  if preview ~= nil then
    -- We use bash to do math on the environment variable, so
    -- let's make sure this command runs in bash
    -- preview = "bash -c " .. vim.fn.shellescape(preview)
    preview = vim.fn.shellescape(preview)
  end
  return preview
end

M.build_fzf_cli = function(opts)
  local cfg = require'fzf-lua.config'
  opts.prompt = opts.prompt or cfg.default_prompt
  opts.preview_offset = opts.preview_offset or ''
  local cli = string.format(
    [[ --layout=%s --bind=%s --prompt=%s]] ..
    [[ --preview-window='%s%s' --preview=%s]] ..
    [[ --expect=%s --ansi --info=inline]] ..
    [[ %s %s]],
    cfg.fzf_layout,
    utils._if(opts.fzf_binds, opts.fzf_binds,
      vim.fn.shellescape(table.concat(cfg.fzf_binds, ','))),
    vim.fn.shellescape(opts.prompt),
    utils._if(opts.preview_window, opts.preview_window, cfg.preview_window()),
    utils._if(#opts.preview_offset>0, ":"..opts.preview_offset, ''),
    utils._if(opts.preview, opts.preview, M.preview_cmd(opts, cfg)),
    utils._if(opts.actions, actions.expect(opts.actions), 'ctrl-s,ctrl-v,ctrl-t'),
    utils._if(opts.nomulti, '--no-multi', '--multi'),
    utils._if(opts.cli_args, opts.cli_args, '')
  )
  -- print(cli)
  return cli
end

-- invisible unicode char as icon|git separator
-- this way we can split our string by space
local nbsp = "\u{00a0}"

local get_diff_files = function()
    local diff_files = {}
    local status = vim.fn.systemlist(config.files.git_diff_cmd)
    if not utils.shell_error() then
        for i = 1, #status do
            local split = vim.split(status[i], "	")
            diff_files[split[2]] = split[1]
        end
    end

    return diff_files
end

local get_untracked_files = function()
    local untracked_files = {}
    local status = vim.fn.systemlist(config.files.git_untracked_cmd)
    if vim.v.shell_error == 0 then
        for i = 1, #status do
            untracked_files[status[i]] = "?"
        end
    end

    return untracked_files
end

local color_icon = function(icon, ext)
  if ext then
    return utils.ansi_codes[config.file_icon_colors[ext] or "dark_grey"](icon)
  else
    return utils.ansi_codes[config.git_icon_colors[icon] or "green"](icon)
  end
end

local get_git_icon = function(file, diff_files, untracked_files)
    if diff_files and diff_files[file] then
        return config.git_icons[diff_files[file]]
    end
    if untracked_files and untracked_files[file] then
        return config.git_icons[untracked_files[file]]
    end
    return nbsp
end

M.make_entry_file = function(opts, x)
  local icon
  local prefix = ''
  if opts.cwd and #opts.cwd > 0 then
    x = path.relative(x, opts.cwd)
  end
  if opts.file_icons then
    local extension = path.extension(x)
    icon = M.get_devicon(x, extension)
    if opts.color_icons then icon = color_icon(icon, extension) end
    prefix = prefix .. icon
  end
  if opts.git_icons then
    icon = get_git_icon(x, opts.diff_files, opts.untracked_files)
    if opts.color_icons then icon = color_icon(icon) end
    prefix = prefix .. utils._if(#prefix>0, nbsp, '') .. icon
  end
  if #prefix > 0 then
    x = prefix .. " " .. x
  end
  return x
end

local function trim_entry(string)
  string = string:gsub("^[^ ]* ", "")
  return string
end

M.fzf_files = function(opts)

  if not opts or not opts.fzf_fn then
    utils.warn("Core.fzf_files(opts) cannot run without callback fn")
    return
  end

  -- reset git tracking
  opts.diff_files, opts.untracked_files = nil, nil
  if not utils.is_git_repo() then opts.git_icons = false end

  if opts.cwd and #opts.cwd > 0 then
    opts.cwd = vim.fn.expand(opts.cwd)
  end

  coroutine.wrap(function ()

    if opts.git_icons then
      opts.diff_files = get_diff_files()
      opts.untracked_files = get_untracked_files()
    end

    local has_prefix = opts.file_icons or opts.git_icons
    if not opts.filespec then
      opts.filespec = utils._if(has_prefix, "{2}", "{}")
    end

    local selected = fzf.fzf(opts.fzf_fn,
      M.build_fzf_cli(opts), config.winopts(opts.winopts))

    if not selected then return end

    if #selected > 1 then
      for i = 2, #selected do
        if has_prefix then
          selected[i] = trim_entry(selected[i])
        end
        if opts.cwd and #opts.cwd > 0 then
          selected[i] = path.join({opts.cwd, selected[i]})
        end
        if opts.cb_selected then
          local cb_ret = opts.cb_selected(opts, selected[i])
          if cb_ret then selected[i] = cb_ret end
        end
      end
    end

    -- dump fails after fzf for some odd reason
    -- functions are still valid as can seen by pairs
    -- _G.dump(opts.actions)
    actions.act(opts.actions, selected[1], selected)

  end)()

end

return M
