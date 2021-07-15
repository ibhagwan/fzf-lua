local utils = require "fzf-lua.utils"
local actions = require "fzf-lua.actions"

-- Clear the default command or it would interfere with our options
vim.env.FZF_DEFAULT_OPTS = ''

local M = {}

M._has_devicons = pcall(require, "nvim-web-devicons")

M.win_height          = 0.85
M.win_width           = 0.80
M.win_row             = 0.30
M.win_col             = 0.50
M.win_border          = true
M.default_prompt      = '> '
M.fzf_layout          = 'reverse'
M.preview_cmd         = nil   -- auto detect head|bat
M.preview_border      = 'border'
M.preview_wrap        = 'nowrap'
M.preview_opts        = 'nohidden'
M.preview_vertical    = 'down:45%'
M.preview_horizontal  = 'right:60%'
M.preview_layout      = 'flex'
M.flip_columns        = 120
M.bat_theme           = nil
M.bat_opts            = "--italic-text=always --style=numbers,changes --color always"

M.files = {
  prompt              = '> ',
  cmd                 = nil,  -- default: auto detect find|fd
  file_icons          = true and M._has_devicons,
  color_icons         = true,
  git_icons           = true,
  git_diff_cmd        = "git diff --name-status --relative HEAD",
  git_untracked_cmd   = "git ls-files --exclude-standard --others",
  find_opts           = "-type f -printf '%P\n'",
  fd_opts             =
    [[--color never --type f --hidden --follow ]] ..
    [[--exclude .git --exclude node_modules --exclude '*.pyc']],
  actions = {
    ["default"]       = actions.file_edit,
    ["ctrl-s"]        = actions.file_split,
    ["ctrl-v"]        = actions.file_vsplit,
    ["ctrl-t"]        = actions.file_tabedit,
    ["ctrl-q"]        = actions.file_sel_to_qf,
  }
}

M.grep = {
  prompt              = 'Rg> ',
  input_prompt        = 'Grep For> ',
  cmd                 = nil,  -- default: auto detect rg|grep
  file_icons          = true and M._has_devicons,
  color_icons         = true,
  git_icons           = true,
  git_diff_cmd        = M.files.git_diff_cmd,
  git_untracked_cmd   = M.files.git_untracked_cmd,
  grep_opts           = "--line-number --recursive --color=auto",
  rg_opts             = "--column --line-number --no-heading --color=always --smart-case",
  actions = {
    ["default"]       = actions.file_edit,
    ["ctrl-s"]        = actions.file_split,
    ["ctrl-v"]        = actions.file_vsplit,
    ["ctrl-t"]        = actions.file_tabedit,
    ["ctrl-q"]        = actions.file_sel_to_qf,
  }
}

M.oldfiles = {
  prompt              = 'History> ',
  file_icons          = true and M._has_devicons,
  color_icons         = true,
  git_icons           = false,
  git_diff_cmd        = M.files.git_diff_cmd,
  git_untracked_cmd   = M.files.git_untracked_cmd,
  actions = {
    ["default"]       = actions.file_edit,
    ["ctrl-s"]        = actions.file_split,
    ["ctrl-v"]        = actions.file_vsplit,
    ["ctrl-t"]        = actions.file_tabedit,
    ["ctrl-q"]        = actions.file_sel_to_qf,
  }
}

M.quickfix = {
  prompt              = 'Quickfix> ',
  separator           = '▏',
  file_icons          = true and M._has_devicons,
  color_icons         = true,
  git_icons           = false,
  git_diff_cmd        = M.files.git_diff_cmd,
  git_untracked_cmd   = M.files.git_untracked_cmd,
  actions = {
    ["default"]       = actions.file_edit,
    ["ctrl-s"]        = actions.file_split,
    ["ctrl-v"]        = actions.file_vsplit,
    ["ctrl-t"]        = actions.file_tabedit,
    ["ctrl-q"]        = actions.file_sel_to_qf,
  }
}

M.loclist = {
  prompt              = 'Locations> ',
  separator           = '▏',
  file_icons          = true and M._has_devicons,
  color_icons         = true,
  git_icons           = false,
  git_diff_cmd        = M.files.git_diff_cmd,
  git_untracked_cmd   = M.files.git_untracked_cmd,
  actions = {
    ["default"]       = actions.file_edit,
    ["ctrl-s"]        = actions.file_split,
    ["ctrl-v"]        = actions.file_vsplit,
    ["ctrl-t"]        = actions.file_tabedit,
    ["ctrl-q"]        = actions.file_sel_to_qf,
  }
}

M.git = {
  prompt              = 'GitFiles> ',
  cmd                 = "git ls-files --exclude-standard",
  file_icons          = true and M._has_devicons,
  color_icons         = true,
  git_icons           = true,
  actions             = M.files.actions,
}

M.buffers = {
  prompt                = 'Buffers> ',
  file_icons            = true and M._has_devicons,
  color_icons           = true,
  sort_lastused         = true,
  show_all_buffers      = true,
  ignore_current_buffer = false,
  cwd_only              = false,
  actions = {
      ["default"]       = actions.buf_edit,
      ["ctrl-s"]        = actions.buf_split,
      ["ctrl-v"]        = actions.buf_vsplit,
      ["ctrl-t"]        = actions.buf_tabedit,
      ["ctrl-x"]        = actions.buf_del,
  }
}

M.colorschemes = {
    prompt              = 'Colorschemes> ',
    live_preview        = true,
    actions = {
      ["default"]       = actions.colorscheme,
    },
    winopts = {
      win_height       = 0.55,
      win_width        = 0.50,
    },
}

M.helptags = {
    prompt              = 'Help> ',
    actions = {
      ["default"]       = actions.help,
      ["ctrl-s"]        = actions.help,
      ["ctrl-v"]        = actions.help_vert,
      ["ctrl-t"]        = actions.help_tab,
    },
}

M.manpages = {
    prompt              = 'Man> ',
    cmd                 = "man -k .",
    actions = {
      ["default"]       = actions.man,
      ["ctrl-s"]        = actions.man,
      ["ctrl-v"]        = actions.man_vert,
      ["ctrl-t"]        = actions.man_tab,
    },
}

-- <F2>        toggle preview
-- <F3>        toggle preview text wrap
-- <C-f>|<C-b> page down|up
-- <C-d>|<C-u> half page down|up
-- <S-d>|<S-u> preview page down|up
-- <C-a>       toggle select-all
-- <C-u>       clear query
-- <C-q>       send selected to quicfix
-- <A-q>       send all to quicfix
M.fzf_binds = {
  'f2:toggle-preview',
  'f3:toggle-preview-wrap',
  'shift-down:preview-page-down',
  'shift-up:preview-page-up',
  'ctrl-d:half-page-down',
  'ctrl-u:half-page-up',
  'ctrl-f:page-down',
  'ctrl-b:page-up',
  'ctrl-a:toggle-all',
  'ctrl-u:clear-query',
}

M.file_icon_colors = {
  ["lua"]       = "blue",
  ["vim"]       = "green",
  ["sh"]        = "cyan",
  ["zsh"]       = "cyan",
  ["bash"]      = "cyan",
  ["py"]        = "green",
  ["md"]        = "yellow",
  ["c"]         = "blue",
  ["cpp"]       = "blue",
  ["h"]         = "magenta",
  ["hpp"]       = "magenta",
  ["js"]        = "blue",
  ["ts"]        = "cyan",
  ["tsx"]       = "cyan",
  ["css"]       = "magenta",
  ["yml"]       = "yellow",
  ["yaml"]      = "yellow",
  ["json"]      = "yellow",
  ["toml"]      = "yellow",
  ["conf"]      = "yellow",
  ["build"]     = "red",
  ["txt"]       = "white",
  ["gif"]       = "green",
  ["jpg"]       = "green",
  ["png"]       = "green",
  ["svg"]       = "green",
  ["sol"]       = "red",
  ["desktop"]   = "magenta",
}

M.git_icons = {
    ["M"]     = "M",
    ["D"]     = "D",
    ["A"]     = "A",
    ["?"]     = "?"
}

M.git_icon_colors = {
  ["M"]     = "yellow",
  ["D"]     = "red",
  ["A"]     = "green",
  ["?"]     = "magenta"
}

M.window_on_create = function()
  -- Set popup background same as normal windows
  vim.cmd("set winhl=Normal:Normal")
end

M.winopts = function(opts)

  opts = M.getopts(opts, M, {
    "win_height", "win_width",
    "win_row", "win_col", "win_border",
    "window_on_create",
    "winopts_raw",
  })

  if opts.winopts_raw and type(opts.winopts_raw) == "function" then
    return opts.winopts_raw()
  end

  local height = math.floor(vim.o.lines * opts.win_height)
  local width = math.floor(vim.o.columns * opts.win_width)
  local row = math.floor((vim.o.lines - height) * opts.win_row)
  local col = math.floor((vim.o.columns - width) * opts.win_col)

  return {
    -- style = 'minimal',
    height = height, width = width, row = row, col = col,
    border = opts.win_border,
    window_on_create = opts.window_on_create
  }
end

M.preview_window = function()
  local preview_veritcal = string.format('%s:%s:%s:%s',
    M.preview_opts, M.preview_border, M.preview_wrap, M.preview_vertical)
  local preview_horizontal = string.format('%s:%s:%s:%s',
    M.preview_opts, M.preview_border, M.preview_wrap, M.preview_horizontal)
  if M.preview_layout == "vertical" then
    return preview_veritcal
  elseif M.preview_layout == "flex" then
    return utils._if(vim.o.columns>M.flip_columns, preview_horizontal, preview_veritcal)
  else
    return preview_horizontal
  end
end


-- called to merge caller opts and default config
-- before calling a provider method
function M.getopts(opts, cfg, keys)
  if not opts then opts = {} end
  if keys then
    for _, k in ipairs(keys) do
      if opts[k] == nil then opts[k] = cfg[k] end
    end
  end
  return opts
end

return M
