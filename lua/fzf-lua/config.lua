local utils = require "fzf-lua.utils"
local actions = require "fzf-lua.actions"

-- Clear the default command or it would interfere with our options
-- not needed anymore, we are pretty much overriding all options
-- with our cli args, in addition this could conflict with fzf.vim
-- vim.env.FZF_DEFAULT_OPTS = ''

local M = {}

M._has_devicons, M._devicons = pcall(require, "nvim-web-devicons")

-- if the caller has devicons lazy loaded
-- this will generate an error
--  nvim-web-devicons.lua:972: E5560:
--  nvim_command must not be called in a lua loop callback
if M._has_devicons and not M._devicons.has_loaded() then
  M._devicons.setup()
end

M.globals = {
  winopts = {
    win_height          = 0.85,
    win_width           = 0.80,
    win_row             = 0.30,
    win_col             = 0.50,
    win_border          = true,
    borderchars         = { '╭', '─', '╮', '│', '╯', '─', '╰', '│' },
    hl_normal           = 'Normal',
    hl_border           = 'FloatBorder',
    --[[ window_on_create = function()
      -- Set popup background same as normal windows
      vim.cmd("set winhl=Normal:Normal,FloatBorder:FloatBorder")
    end, ]]
  },
  default_prompt      = '> ',
  fzf_bin             = nil,
  fzf_layout          = 'reverse',
  fzf_binds = {
    -- <F2>        toggle preview
    -- <F3>        toggle preview text wrap
    -- <C-f>|<C-b> page down|up
    -- <C-d>|<C-u> half page down|up
    -- <S-d>|<S-u> preview page down|up
    -- <C-a>       toggle select-all
    -- <C-u>       clear query
    -- <C-q>       send selected to quicfix
    -- <A-q>       send all to quicfix
    'f2:toggle-preview',
    'f3:toggle-preview-wrap',
    'shift-down:preview-page-down',
    'shift-up:preview-page-up',
    'ctrl-d:half-page-down',
    'ctrl-u:half-page-up',
    'ctrl-f:page-down',
    'ctrl-b:page-up',
    'ctrl-a:toggle-all',
    'ctrl-l:clear-query',
  },
  preview_border      = 'border',
  preview_wrap        = 'nowrap',
  preview_opts        = 'nohidden',
  preview_vertical    = 'down:45%',
  preview_horizontal  = 'right:60%',
  preview_layout      = 'flex',
  flip_columns        = 120,
  default_previewer   = "builtin",
  previewers = {
    cmd = {
      -- custom previewer to be overidden by the user
      cmd             = "",
      args            = "",
                      -- we use function here instead of the object due to
                      -- vim.tbl_deep_extend not copying metatables and
                      -- metamethods (__index and __call)
      _new            = function() return require 'fzf-lua.previewer'.cmd_async end,
    },
    cat = {
      cmd             = "cat",
      args            = "--number",
      _new            = function() return require 'fzf-lua.previewer'.cmd_async end,
    },
    bat = {
      cmd             = "bat",
      args            = "--italic-text=always --style=numbers,changes --color always",
      theme           = nil,
      config          = nil,
      _new            = function() return require 'fzf-lua.previewer'.bat_async end,
    },
    bat_native = {
      cmd             = "bat",
      args            = "--italic-text=always --style=numbers,changes --color always",
      _new            = function() return require 'fzf-lua.previewer'.bat end,
    },
    head = {
      cmd             = "head",
      args            = nil,
      _new            = function() return require 'fzf-lua.previewer'.head end,
    },
    git_diff = {
      cmd             = "git diff",
      args            = "--color",
      _new            = function() return require 'fzf-lua.previewer'.cmd_async end,
    },
    builtin = {
      title           = true,
      scrollbar       = true,
      scrollchar      = '█',
      wrap            = false,
      syntax          = true,
      syntax_delay    = 0,
      expand          = false,
      hidden          = false,
      hl_cursor       = 'Cursor',
      hl_cursorline   = 'CursorLine',
      hl_range        = 'IncSearch',
      keymap = {
        toggle_full   = '<F2>',       -- toggle full screen
        toggle_wrap   = '<F3>',       -- toggle line wrap
        toggle_hide   = '<F4>',       -- toggle on/off (not yet in use)
        page_up       = '<S-up>',     -- preview scroll up
        page_down     = '<S-down>',   -- preview scroll down
        page_reset    = '<S-left>',   -- reset scroll to orig pos
      },
      _new            = function() return require 'fzf-lua.previewer.builtin' end,
    },
  },
}
M.globals.files = {
    previewer           = function() return M.globals.default_previewer end,
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
    },
  }
-- Must construct our opts table in stages
-- so we can reference 'M.globals.files'
M.globals.git = {
    files = {
      previewer     = function() return M.globals.default_previewer end,
      prompt        = 'GitFiles> ',
      cmd           = "git ls-files --exclude-standard",
      file_icons    = true and M._has_devicons,
      color_icons   = true,
      git_icons     = true,
      actions       = M.globals.files.actions,
    },
    status = {
      prompt        = 'GitStatus> ',
      cmd           = "git status -s",
      previewer     = "git_diff",
      file_icons    = true and M._has_devicons,
      color_icons   = true,
      git_icons     = true,
      actions       = M.globals.files.actions,
    },
    commits = {
      prompt        = 'Commits> ',
      cmd           = "git log --pretty=oneline --abbrev-commit --color",
      preview       = "git show --pretty='%Cred%H%n%Cblue%an%n%Cgreen%s' --color {1}",
      actions = {
        ["default"] = nil,
      },
    },
    bcommits = {
      prompt        = 'BCommits> ',
      cmd           = "git log --pretty=oneline --abbrev-commit --color --",
      preview       = "git show --pretty='%Cred%H%n%Cblue%an%n%Cgreen%s' --color {1}",
      actions = {
        ["default"] = nil,
      },
    },
    branches = {
      prompt        = 'Branches> ',
      cmd           = "git branch --all --color",
      preview       = "git log --graph --pretty=oneline --abbrev-commit --color {1}",
      actions = {
        ["default"] = actions.git_switch,
      },
    },
    icons = {
      ["M"]         = { icon = "M", color = "yellow" },
      ["D"]         = { icon = "D", color = "red" },
      ["A"]         = { icon = "A", color = "green" },
      ["?"]         = { icon = "?", color = "magenta" },
    },
  }
M.globals.grep = {
    previewer           = function() return M.globals.default_previewer end,
    prompt              = 'Rg> ',
    input_prompt        = 'Grep For> ',
    cmd                 = nil,  -- default: auto detect rg|grep
    file_icons          = true and M._has_devicons,
    color_icons         = true,
    git_icons           = true,
    git_diff_cmd        = M.globals.files.git_diff_cmd,
    git_untracked_cmd   = M.globals.files.git_untracked_cmd,
    grep_opts           = "--line-number --recursive --color=auto",
    rg_opts             = "--column --line-number --no-heading --color=always --smart-case",
    actions = {
      ["default"]       = actions.file_edit,
      ["ctrl-s"]        = actions.file_split,
      ["ctrl-v"]        = actions.file_vsplit,
      ["ctrl-t"]        = actions.file_tabedit,
      ["ctrl-q"]        = actions.file_sel_to_qf,
    },
  }
M.globals.oldfiles = {
    previewer           = function() return M.globals.default_previewer end,
    prompt              = 'History> ',
    file_icons          = true and M._has_devicons,
    color_icons         = true,
    git_icons           = false,
    git_diff_cmd        = M.globals.files.git_diff_cmd,
    git_untracked_cmd   = M.globals.files.git_untracked_cmd,
    actions = {
      ["default"]       = actions.file_edit,
      ["ctrl-s"]        = actions.file_split,
      ["ctrl-v"]        = actions.file_vsplit,
      ["ctrl-t"]        = actions.file_tabedit,
      ["ctrl-q"]        = actions.file_sel_to_qf,
    },
  }
M.globals.quickfix = {
    previewer           = function() return M.globals.default_previewer end,
    prompt              = 'Quickfix> ',
    separator           = '▏',
    file_icons          = true and M._has_devicons,
    color_icons         = true,
    git_icons           = false,
    git_diff_cmd        = M.globals.files.git_diff_cmd,
    git_untracked_cmd   = M.globals.files.git_untracked_cmd,
    actions = {
      ["default"]       = actions.file_edit,
      ["ctrl-s"]        = actions.file_split,
      ["ctrl-v"]        = actions.file_vsplit,
      ["ctrl-t"]        = actions.file_tabedit,
      ["ctrl-q"]        = actions.file_sel_to_qf,
    },
  }
M.globals.loclist = {
    previewer           = function() return M.globals.default_previewer end,
    prompt              = 'Locations> ',
    separator           = '▏',
    file_icons          = true and M._has_devicons,
    color_icons         = true,
    git_icons           = false,
    git_diff_cmd        = M.globals.files.git_diff_cmd,
    git_untracked_cmd   = M.globals.files.git_untracked_cmd,
    actions = {
      ["default"]       = actions.file_edit,
      ["ctrl-s"]        = actions.file_split,
      ["ctrl-v"]        = actions.file_vsplit,
      ["ctrl-t"]        = actions.file_tabedit,
      ["ctrl-q"]        = actions.file_sel_to_qf,
    },
  }
M.globals.buffers = {
    previewer             = "builtin",
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
    },
  }
M.globals.tags = {
    previewer             = function() return M.globals.default_previewer end,
    prompt                = 'Tags> ',
    ctags_file            = "tags",
    file_icons            = true and M._has_devicons,
    git_icons             = true,
    color_icons           = true,
    actions = {
        ["default"]       = actions.file_edit,
        ["ctrl-s"]        = actions.file_split,
        ["ctrl-v"]        = actions.file_vsplit,
        ["ctrl-t"]        = actions.file_tabedit,
        ["ctrl-q"]        = actions.file_sel_to_qf,
    },
  }
M.globals.btags = {
    previewer             = function() return M.globals.default_previewer end,
    prompt                = 'BTags> ',
    ctags_file            = "tags",
    file_icons            = true and M._has_devicons,
    git_icons             = true,
    color_icons           = true,
    actions = {
        ["default"]       = actions.file_edit,
        ["ctrl-s"]        = actions.file_split,
        ["ctrl-v"]        = actions.file_vsplit,
        ["ctrl-t"]        = actions.file_tabedit,
        ["ctrl-q"]        = actions.file_sel_to_qf,
    },
  }
M.globals.colorschemes = {
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
M.globals.helptags = {
      prompt              = 'Help> ',
      actions = {
        ["default"]       = actions.help,
        ["ctrl-s"]        = actions.help,
        ["ctrl-v"]        = actions.help_vert,
        ["ctrl-t"]        = actions.help_tab,
      },
  }
M.globals.manpages = {
      prompt              = 'Man> ',
      cmd                 = "man -k .",
      actions = {
        ["default"]       = actions.man,
        ["ctrl-s"]        = actions.man,
        ["ctrl-v"]        = actions.man_vert,
        ["ctrl-t"]        = actions.man_tab,
      },
  }
M.globals.lsp = {
      previewer           = function() return M.globals.default_previewer end,
      prompt              = '> ',
      file_icons          = true and M._has_devicons,
      color_icons         = true,
      git_icons           = false,
      lsp_icons           = true,
      severity            = "hint",
      cwd_only            = false,
      async_or_timeout    = true,
      actions             = M.globals.files.actions,
      icons = {
          ["Error"]       = { icon = "", color = "red" },       -- error
          ["Warning"]     = { icon = "", color = "yellow" },    -- warning
          ["Information"] = { icon = "", color = "blue" },      -- info
          ["Hint"]        = { icon = "", color = "magenta" },   -- hint
      },
  }
M.globals.builtin = {
      prompt              = 'Builtin> ',
      winopts = {
        win_height        = 0.65,
        win_width         = 0.50,
      },
      actions = {
        ["default"]       = actions.run_builtin,
      },
  }
M.globals.nvim = {
    marks = {
      prompt              = 'Marks> ',
      actions = {
        ["default"]       = actions.goto_mark,
      },
    },
    commands = {
      prompt              = 'Commands> ',
      actions = {
        ["default"]       = actions.ex_run,
      },
    },
    command_history = {
      prompt              = 'Command History> ',
      actions = {
        ["default"]       = actions.ex_run,
      },
    },
    search_history = {
      prompt              = 'Search History> ',
      actions = {
        ["default"]       = actions.search,
      },
    },
    registers = {
      prompt              = 'Registers> ',
      ignore_empty        = true,
    },
    keymaps = {
      prompt              = 'Keymaps> ',
    },
    spell_suggest = {
      prompt              = 'Spelling Suggestions> ',
      actions = {
        ["default"]       = actions.spell_apply,
      },
    },
  }
M.globals.file_icon_colors = {
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

function M.normalize_opts(opts, defaults)
  if not opts then opts = {} end
  opts = vim.tbl_deep_extend("keep", opts, defaults)
  if defaults.winopts then
    if not opts.winopts then opts.winopts = {} end
    opts.winopts = vim.tbl_deep_extend("keep", opts.winopts, defaults.winopts)
  end
  if type(opts.previewer) == 'function' then
    -- we use a function so the user can override
    -- globals.default_previewer
    opts.previewer = opts.previewer()
  end
  return opts
end

return M
