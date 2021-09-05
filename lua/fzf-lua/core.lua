local fzf = require "fzf"
local path = require "fzf-lua.path"
local utils = require "fzf-lua.utils"
local config = require "fzf-lua.config"
local actions = require "fzf-lua.actions"
local win = require "fzf-lua.win"

local M = {}

M.fzf = function(opts, contents, previewer)
  -- setup the fzf window and preview layout
  local fzf_win = win(opts)
  -- instantiate the previewer
  -- if not opts.preview and not previewer and
  if not previewer and
    opts.previewer and type(opts.previewer) == 'string' then
    local preview_opts = config.globals.previewers[opts.previewer]
    if preview_opts then
      previewer = preview_opts._new()(preview_opts, opts, fzf_win)
      opts.preview = previewer:cmdline()
      if type(previewer.override_fzf_preview_window) == 'function' then
        -- do we need to override the preview_window args?
        -- this can happen with the builtin previewer
        -- (1) when using a split we use the previewer as placeholder
        -- (2) we use 'right:0' to call the previewer function only
        if previewer:override_fzf_preview_window() then
          opts.preview_window = previewer:preview_window()
        end
      end
    end
  end
  fzf_win:attach_previewer(previewer)
  fzf_win:create()
  local selected = fzf.raw_fzf(contents, M.build_fzf_cli(opts),
    { fzf_binary = opts.fzf_bin })
  fzf_win:close()
  return selected
end

M.get_devicon = function(file, ext)
  local icon = ''
  if not file or #file == 0 then return icon end
  if config._has_devicons and config._devicons then
    local devicon = config._devicons.get_icon(file, ext)
    if devicon then icon = devicon end
  end
  return icon..config.globals.file_icon_padding
end

M.preview_window = function(opts)
  local o = vim.tbl_deep_extend("keep", opts, config.globals)
  local preview_vertical = string.format('%s:%s:%s:%s',
    o.preview_opts, o.preview_border, o.preview_wrap, o.preview_vertical)
  local preview_horizontal = string.format('%s:%s:%s:%s',
    o.preview_opts, o.preview_border, o.preview_wrap, o.preview_horizontal)
  if o.preview_layout == "vertical" then
    return preview_vertical
  elseif o.preview_layout == "flex" then
    return utils._if(vim.o.columns>o.flip_columns, preview_horizontal, preview_vertical)
  else
    return preview_horizontal
  end
end

M.build_fzf_cli = function(opts, debug_print)
  opts.prompt = opts.prompt or config.globals.default_prompt
  opts.preview_offset = opts.preview_offset or ''
  opts.fzf_info = opts.fzf_info or config.globals.fzf_info
  opts.fzf_ansi = opts.fzf_ansi or config.globals.fzf_ansi
  if not opts.fzf_info then
    -- skim (rust version of fzf) doesn't
    -- support the '--info=' flag
    opts.fzf_info = utils._if(opts._is_skim, "--inline-info", "--info=inline")
  end
  local cli = string.format(
    [[ %s --layout=%s --bind=%s --prompt=%s]] ..
    [[ --preview-window=%s%s --preview=%s]] ..
    [[ --height=100%%]] ..
    [[ %s %s %s %s %s %s]],
    opts.fzf_args or config.globals.fzf_args or '',
    opts.fzf_layout or config.globals.fzf_layout,
    utils._if(opts.fzf_binds, opts.fzf_binds,
      vim.fn.shellescape(table.concat(config.globals.fzf_binds, ','))),
    vim.fn.shellescape(opts.prompt),
    utils._if(opts.preview_window, opts.preview_window, M.preview_window(opts)),
    utils._if(#opts.preview_offset>0, ":"..opts.preview_offset, ''),
    utils._if(opts.preview and #opts.preview>0, opts.preview, "''"),
    opts.fzf_ansi or '--ansi', opts.fzf_info or '',
    utils._if(actions.expect(opts.actions), actions.expect(opts.actions), ''),
    utils._if(opts.nomulti, '--no-multi', '--multi'),
    utils._if(opts.fzf_cli_args, opts.fzf_cli_args, ''),
    utils._if(opts._fzf_cli_args, opts._fzf_cli_args, '')
  )
  if debug_print then print(cli) end
  return cli
end

local get_diff_files = function(opts)
    local diff_files = {}
    local status = vim.fn.systemlist(path.git_cwd(
      config.globals.files.git_diff_cmd, opts.cwd))
    if not utils.shell_error() then
        for i = 1, #status do
          local icon, file = status[i]:match("^([MUDAR])%s+(.*)")
          if icon and file then diff_files[file] = icon end
        end
    end

    return diff_files
end

local get_untracked_files = function(opts)
    local untracked_files = {}
    local status = vim.fn.systemlist(path.git_cwd(
      config.globals.files.git_untracked_cmd, opts.cwd))
    if vim.v.shell_error == 0 then
        for i = 1, #status do
            local file = status[i]
            untracked_files[file] = "?"
        end
    end

    return untracked_files
end

local get_git_indicator = function(file, diff_files, untracked_files)
    -- remove colors from `rg` output
    file = utils.strip_ansi_coloring(file)
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
  if opts.cwd_only and path.starts_with_separator(x) then
    local cwd = opts.cwd or vim.loop.cwd()
    if not path.is_relative(x, cwd) then
      return nil
    end
  end
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

  if not opts then return end

  -- reset git tracking
  opts.diff_files, opts.untracked_files = nil, nil
  if opts.git_icons and not path.is_git_repo(opts.cwd, true) then opts.git_icons = false end

  if opts.cwd and #opts.cwd > 0 then
    opts.cwd = vim.fn.expand(opts.cwd)
  end

  coroutine.wrap(function ()

    if opts.cwd_only and not opts.cwd then
      opts.cwd = vim.loop.cwd()
    end

    if opts.git_icons then
      opts.diff_files = get_diff_files(opts)
      opts.untracked_files = get_untracked_files(opts)
    end

    local has_prefix = opts.file_icons or opts.git_icons or opts.lsp_icons
    if not opts.filespec then
      opts.filespec = utils._if(has_prefix, "{2}", "{1}")
    end


    local selected = M.fzf(opts, opts.fzf_fn)

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

    actions.act(opts.actions, selected)

  end)()

end


M.fzf_files_interactive = function(opts)

  opts = opts or config.normalize_opts(opts, config.globals.files)
  if not opts then return end

  -- cannot be nil
  local query = opts._live_query or ''
  local placeholder = utils._if(opts._is_skim, '"{}"', '{q}')

  local uv = vim.loop
  local raw_async_act = require("fzf.actions").raw_async_action(function(pipe, args)
    local shell_cmd = opts._cb_live_cmd(args[1])
    local output_pipe = uv.new_pipe(false)
    local error_pipe = uv.new_pipe(false)

    local shell = vim.env.SHELL or "sh"

    uv.spawn(shell, {
      args = { "-c", shell_cmd },
      stdio = { nil, output_pipe, error_pipe }
    }, function(code, signal)

    end)

    local cleaned_up = false
    local cleanup = function()
      if not cleaned_up then
        cleaned_up = true
        uv.read_stop(output_pipe)
        uv.read_stop(error_pipe)
        uv.close(output_pipe)
        uv.close(error_pipe)
        uv.close(pipe)
      end
    end

    local read_cb = function(err, data)

      if err then
        cleanup()
        assert(not err)
      end
      if not data then
        cleanup()
        return
      end

      uv.write(pipe, data, function(err)
        if err then
          cleanup()
        end
      end)
    end

    output_pipe:read_start(read_cb)
    error_pipe:read_start(read_cb)
  end, placeholder)

  local act_cmd = raw_async_act

  if opts._is_skim then
    -- do not run an empty string query unless the user requested
    if not opts.exec_empty_query then
      act_cmd = "sh -c " .. vim.fn.shellescape(
        ("[ -z %s ] || %s"):format(placeholder, act_cmd))
    else
      act_cmd = vim.fn.shellescape(act_cmd)
    end
    -- skim interactive mode does not need a piped command
    opts.fzf_fn = nil
    opts._fzf_cli_args = string.format(
        "--prompt='*%s' --cmd-prompt='%s' --cmd-query='%s' -i -c %s",
        opts.prompt, opts.prompt, query, act_cmd)
  else
    -- fzf already adds single quotes
    -- around the place holder
    opts.fzf_fn = {}
    if opts.exec_empty_query or (query and #query>0) then
      opts.fzf_fn = require("fzf.helpers").cmd_line_transformer(
        act_cmd:gsub(placeholder, ('"%s"'):format(query)),
        function(x)
          return M.make_entry_file(opts, x)
        end)
    end
    opts._fzf_cli_args = string.format('--phony --query="%s" --bind=%s', query,
        vim.fn.shellescape(string.format("change:reload:%s || true", act_cmd)))
  end

  -- we cannot parse any entries as they're not getting called
  -- past the initial command, until I can find a solution for
  -- that icons must be disabled
  opts.git_icons = false
  opts.file_icons = false

  opts = M.set_fzf_line_args(opts)
  M.fzf_files(opts)
end

return M
