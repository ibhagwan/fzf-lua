local fzf = require "fzf"
local path = require "fzf-lua.path"
local utils = require "fzf-lua.utils"
local config = require "fzf-lua.config"
local actions = require "fzf-lua.actions"

local M = {}

M.get_devicon = function(file, ext)
  local icon = ''
  if not file or #file == 0 then return icon end
  if config._has_devicons and config._devicons then
    local devicon = config._devicons.get_icon(file, ext)
    if devicon then icon = devicon end
  end
  return icon
end

M.build_fzf_cli = function(opts)
  opts.prompt = opts.prompt or config.globals.default_prompt
  opts.preview_offset = opts.preview_offset or ''
  opts.fzf_bin = opts.fzf_bin or config.globals.fzf_bin
  local cli = string.format(
    [[ %s --layout=%s --bind=%s --prompt=%s]] ..
    [[ --preview-window=%s%s --preview=%s]] ..
    [[ --height=100%% --ansi]] ..
    [[ %s %s %s %s %s]],
    opts.fzf_args or config.globals.fzf_args or '',
    opts.fzf_layout or config.globals.fzf_layout,
    utils._if(opts.fzf_binds, opts.fzf_binds,
      vim.fn.shellescape(table.concat(config.globals.fzf_binds, ','))),
    vim.fn.shellescape(opts.prompt),
    utils._if(opts.preview_window, opts.preview_window, config.preview_window()),
    utils._if(#opts.preview_offset>0, ":"..opts.preview_offset, ''),
    utils._if(opts.preview, vim.fn.shellescape(opts.preview), "''"),
    -- HACK: support skim (rust version of fzf)
    utils._if(opts.fzf_bin and opts.fzf_bin:find('sk')~=nil, "--inline-info", "--info=inline"),
    utils._if(actions.expect(opts.actions), actions.expect(opts.actions), ''),
    utils._if(opts.nomulti, '--no-multi', '--multi'),
    utils._if(opts.fzf_cli_args, opts.fzf_cli_args, ''),
    utils._if(opts._fzf_cli_args, opts._fzf_cli_args, '')
  )
  -- print(cli)
  return cli
end

local get_diff_files = function()
    local diff_files = {}
    local status = vim.fn.systemlist(config.globals.files.git_diff_cmd)
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
    local status = vim.fn.systemlist(config.globals.files.git_untracked_cmd)
    if vim.v.shell_error == 0 then
        for i = 1, #status do
            untracked_files[status[i]] = "?"
        end
    end

    return untracked_files
end

local get_git_indicator = function(file, diff_files, untracked_files)
    -- remove colors from `rg` output
    file = file:gsub("%[%d+m", "")
    if diff_files and diff_files[file] then
        return diff_files[file]
    end
    if untracked_files and untracked_files[file] then
        return untracked_files[file]
    end
    return utils.nbsp
end


M.make_entry_lcol = function(_, entry)
  if not entry then return nil end
  local filename = entry.filename or vim.api.nvim_buf_get_name(entry.bufnr)
  return string.format("%s:%s:%s:%s%s",
    filename, --utils.ansi_codes.magenta(filename),
    utils.ansi_codes.green(tostring(entry.lnum)),
    utils.ansi_codes.blue(tostring(entry.col)),
    utils._if(entry.text and entry.text:find("^\t"), "", "\t"),
    entry.text)
end

M.make_entry_file = function(opts, x)
  local icon
  local prefix = ''
  if opts.cwd and #opts.cwd > 0 then
    x = path.relative(x, opts.cwd)
  end
  if opts.file_icons then
    local ext = path.extension(x)
    icon = M.get_devicon(x, ext)
    if opts.color_icons then
      icon = utils.ansi_codes[config.globals.file_icon_colors[ext] or "dark_grey"](icon)
    end
    prefix = prefix .. icon
  end
  if opts.git_icons then
    local filepath = x:match("^[^:]+")
    local indicator = get_git_indicator(filepath, opts.diff_files, opts.untracked_files)
    icon = indicator
    if config.globals.git.icons[indicator] then
      icon = config.globals.git.icons[indicator].icon
      if opts.color_icons then
        icon = utils.ansi_codes[config.globals.git.icons[indicator].color or "dark_grey"](icon)
      end
    end
    prefix = prefix .. utils._if(#prefix>0, utils.nbsp, '') .. icon
  end
  if #prefix > 0 then
    x = prefix .. utils.nbsp .. x
  end
  return x
end

M.set_fzf_line_args = function(opts)
  opts._line_placeholder = 2
  -- delimiters are ':' and <tab>
  opts._fzf_cli_args = (opts._fzf_cli_args or '') .. " --delimiter='[:\\t]'"
  --[[
    #
    #   Explanation of the fzf preview offset options:
    #
    #   ~3    Top 3 lines as the fixed header
    #   +{2}  Base scroll offset extracted from the second field
    #   +3    Extra offset to compensate for the 3-line header
    #   /2    Put in the middle of the preview area
    #
    '--preview-window '~3:+{2}+3/2''
  ]]
  opts.preview_offset = string.format("+{%d}-/2", opts._line_placeholder)
  return opts
end

M.fzf_files = function(opts)

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

    local has_prefix = opts.file_icons or opts.git_icons or opts.lsp_icons
    if not opts.filespec then
      opts.filespec = utils._if(has_prefix, "{2}", "{1}")
    end


    local preview_opts = config.globals.previewers[opts.previewer]
    if preview_opts then
      local preview = preview_opts._new()(preview_opts, opts)
      opts.preview = preview:cmdline()
      -- opts.preview = preview:action()
    end

    local selected = fzf.fzf(opts.fzf_fn,
      M.build_fzf_cli(opts),
      config.winopts(opts))

    if opts.post_select_cb then
      opts.post_select_cb()
    end

    if not selected then return end

    if #selected > 1 then
      for i = 2, #selected do
        selected[i] = path.entry_to_file(selected[i], opts.cwd).noicons
        if opts.cb_selected then
          local cb_ret = opts.cb_selected(opts, selected[i])
          if cb_ret then selected[i] = cb_ret end
        end
      end
    end

    -- dump fails after fzf for some odd reason
    -- functions are still valid as can seen by pairs
    -- _G.dump(opts.actions)
    actions.act(opts.actions, selected)

  end)()

end

return M
