local utils = require "fzf-lua.utils"
local actions = require "fzf-lua.actions"
local previewers = require "fzf-lua.previewer"

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
    hl_border           = 'Normal',
    --[[ window_on_create = function()
      -- Set popup background same as normal windows
      vim.cmd("set winhl=Normal:Normal,FloatBorder:FloatBorder")
    end, ]]
  },
  fzf_bin             = nil,
  fzf_opts = {
    ['--ansi']        = '',
    ['--prompt']      = ' >',
    ['--info']        = 'inline',
    ['--height']      = '100%',
    ['--layout']      = 'reverse',
  },
  fzf_binds = {
    -- <F2>        toggle preview
    -- <F3>        toggle preview text wrap
    -- <C-f>|<C-b> half page down|up
    -- <S-d>|<S-u> preview page down|up
    -- <C-u>       clear query
    -- <A-a>       toggle select-all
    -- <A-q>       send selected to quickfix
    ["f2"]            = "toggle-preview",
    ["f3"]            = "toggle-preview-wrap",
    ["shift-down"]    = "preview-page-down",
    ["shift-up"]      = "preview-page-up",
    ["ctrl-u"]        = "unix-line-discard",
    ["ctrl-f"]        = "half-page-down",
    ["ctrl-b"]        = "half-page-up",
    ["ctrl-a"]        = "beginning-of-line",
    ["ctrl-e"]        = "end-of-line",
    ["alt-a"]         = "toggle-all",
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
    cat = {
      cmd             = "cat",
      args            = "--number",
      _ctor           = previewers.fzf.cmd_async,
    },
    bat = {
      cmd             = "bat",
      args            = "--italic-text=always --style=numbers,changes --color always",
      theme           = nil,
      config          = nil,
      _ctor           = previewers.fzf.bat_async,
    },
    bat_native = {
      cmd             = "bat",
      args            = "--italic-text=always --style=numbers,changes --color always",
      _ctor           = previewers.fzf.bat,
    },
    head = {
      cmd             = "head",
      args            = nil,
      _ctor           = previewers.fzf.head,
    },
    git_diff = {
      cmd             = "git diff",
      args            = "--color",
      _ctor           = previewers.fzf.git_diff,
    },
    builtin = {
      title           = true,
      scrollbar       = true,
      scrollchar      = '█',
      wrap            = false,
      syntax          = true,
      syntax_delay    = 0,
      syntax_limit_l  = 0,
      syntax_limit_b  = 1024*1024,
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
      _ctor           = previewers.builtin.buffer_or_file,
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
    git_status_cmd      = "git status -s",
    find_opts           = [[-type f -not -path '*/\.git/*' -printf '%P\n']],
    fd_opts             =
      [[--color never --type f --hidden --follow ]] ..
      [[--exclude .git --exclude node_modules --exclude '*.pyc']],
    actions = {
      ["default"]       = actions.file_edit,
      ["ctrl-s"]        = actions.file_split,
      ["ctrl-v"]        = actions.file_vsplit,
      ["ctrl-t"]        = actions.file_tabedit,
      ["alt-q"]         = actions.file_sel_to_qf,
      ["ctrl-q"]        = function()
        utils.info("'ctrl-q|ctrl-a' has been deprecated in favor of 'alt-q|alt-a'")
      end
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
      cmd           = "git log --pretty=oneline --abbrev-commit --color --reflog",
      preview       = "git show --pretty='%Cred%H%n%Cblue%an%n%Cgreen%s' --color {1}",
      actions = {
        ["default"] = actions.git_checkout,
      },
    },
    bcommits = {
      prompt        = 'BCommits> ',
      cmd           = "git log --pretty=oneline --abbrev-commit --color --reflog",
      preview       = "git show --pretty='%Cred%H%n%Cblue%an%n%Cgreen%s' --color {1}",
      actions = {
        ["default"] = actions.git_buf_edit,
        ["ctrl-s"]  = actions.git_buf_split,
        ["ctrl-v"]  = actions.git_buf_vsplit,
        ["ctrl-t"]  = actions.git_buf_tabedit,
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
      ["R"]         = { icon = "R", color = "yellow" },
      ["C"]         = { icon = "C", color = "yellow" },
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
    grep_opts           = "--line-number --recursive --color=auto --perl-regexp",
    rg_opts             = "--column --line-number --no-heading --color=always --smart-case",
    actions             = M.globals.files.actions,
  }
M.globals.oldfiles = {
    previewer           = function() return M.globals.default_previewer end,
    prompt              = 'History> ',
    file_icons          = true and M._has_devicons,
    color_icons         = true,
    git_icons           = false,
    actions             = M.globals.files.actions,
  }
M.globals.quickfix = {
    previewer           = function() return M.globals.default_previewer end,
    prompt              = 'Quickfix> ',
    separator           = '▏',
    file_icons          = true and M._has_devicons,
    color_icons         = true,
    git_icons           = false,
    actions             = M.globals.files.actions,
  }
M.globals.loclist = {
    previewer           = function() return M.globals.default_previewer end,
    prompt              = 'Locations> ',
    separator           = '▏',
    file_icons          = true and M._has_devicons,
    color_icons         = true,
    git_icons           = false,
    actions             = M.globals.files.actions,
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
M.globals.tabs = {
    previewer             = "builtin",
    prompt                = 'Tabs> ',
    tab_title             = "Tab",
    tab_marker            = "<<",
    file_icons            = true and M._has_devicons,
    color_icons           = true,
    actions = {
        ["default"]       = actions.buf_switch,
        ["ctrl-s"]        = actions.buf_split,
        ["ctrl-v"]        = actions.buf_vsplit,
        ["ctrl-t"]        = actions.buf_tabedit,
        ["ctrl-x"]        = actions.buf_del,
    },
  }
M.globals.lines = {
    previewer             = "builtin",
    prompt                = 'Lines> ',
    file_icons            = true and M._has_devicons,
    color_icons           = true,
    actions = {
        ["default"]       = actions.buf_edit,
        ["ctrl-s"]        = actions.buf_split,
        ["ctrl-v"]        = actions.buf_vsplit,
        ["ctrl-t"]        = actions.buf_tabedit,
    },
  }
M.globals.blines = {
    previewer             = "builtin",
    prompt                = 'BLines> ',
    file_icons            = true and M._has_devicons,
    color_icons           = true,
    actions = {
        ["default"]       = actions.buf_edit,
        ["ctrl-s"]        = actions.buf_split,
        ["ctrl-v"]        = actions.buf_vsplit,
        ["ctrl-t"]        = actions.buf_tabedit,
    },
  }
M.globals.tags = {
    previewer             = function() return M.globals.default_previewer end,
    prompt                = 'Tags> ',
    ctags_file            = "tags",
    file_icons            = true and M._has_devicons,
    git_icons             = true,
    color_icons           = true,
    actions             = M.globals.files.actions,
  }
M.globals.btags = {
    previewer             = function() return M.globals.default_previewer end,
    prompt                = 'BTags> ',
    ctags_file            = "tags",
    file_icons            = true and M._has_devicons,
    git_icons             = true,
    color_icons           = true,
    actions             = M.globals.files.actions,
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
      previewer = {
        _ctor             = previewers.builtin.help_tags,
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
      previewer = {
        _ctor             = previewers.builtin.man_pages,
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
      previewer = {
        _ctor             = previewers.builtin.marks,
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
        ["default"]       = actions.ex_run_cr,
        ["ctrl-e"]        = actions.ex_run,
      },
    },
    search_history = {
      prompt              = 'Search History> ',
      actions = {
        ["default"]       = actions.search_cr,
        ["ctrl-e"]        = actions.search,
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
    filetypes = {
      prompt              = 'Filetypes> ',
      actions = {
        ["default"]       = actions.set_filetype,
      },
    },
    packadd = {
      prompt              = 'packadd> ',
      actions = {
        ["default"]       = actions.packadd,
      },
    },
  }

M.globals.file_icon_padding = ''

if M._has_devicons then
  M.globals.file_icon_colors = {}

  local function hex(hex)
    local r,g,b = hex:match('.(..)(..)(..)')
    r, g, b = tonumber(r, 16), tonumber(g, 16), tonumber(b, 16)
    return r, g, b
  end

  for ext, info in pairs(M._devicons.get_icons()) do
    local r, g, b = hex(info.color)
    utils.add_ansi_code('DevIcon' .. info.name, string.format('[38;2;%s;%s;%sm', r, g, b))
  end
else
  M.globals.file_icon_colors = {
    ["lua"]       = "blue",
    ["rockspec"]  = "magenta",
    ["vim"]       = "green",
    ["vifm"]      = "green",
    ["sh"]        = "cyan",
    ["zsh"]       = "cyan",
    ["bash"]      = "cyan",
    ["bat"]       = "cyan",
    ["term"]      = "green",
    ["py"]        = "green",
    ["md"]        = "yellow",
    ["go"]        = "magenta",
    ["c"]         = "blue",
    ["cpp"]       = "blue",
    ["h"]         = "magenta",
    ["hpp"]       = "magenta",
    ["sol"]       = "magenta",
    ["abi"]       = "yellow",
    ["js"]        = "blue",
    ["ts"]        = "cyan",
    ["tsx"]       = "cyan",
    ["css"]       = "magenta",
    ["hs"]        = "blue",
    ["rs"]        = "blue",
    ["rst"]       = "yellow",
    ["xml"]       = "yellow",
    ["yml"]       = "yellow",
    ["yaml"]      = "yellow",
    ["json"]      = "yellow",
    ["toml"]      = "yellow",
    ["ini"]       = "red",
    ["conf"]      = "red",
    ["config"]    = "red",
    ["plist"]     = "red",
    ["local"]     = "red",
    ["build"]     = "red",
    ["patch"]     = "red",
    ["diff"]      = "red",
    ["service"]   = "red",
    ["desktop"]   = "red",
    ["txt"]       = "white",
    ["ico"]       = "green",
    ["gif"]       = "green",
    ["jpg"]       = "green",
    ["png"]       = "green",
    ["svg"]       = "green",
    ["otf"]       = "green",
    ["ttf"]       = "green",
  }
end

function M.normalize_opts(opts, defaults)
  if not opts then opts = {} end
  if not opts.fzf_opts then opts.fzf_opts = {} end
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
  if type(opts.previewer) == 'table' then
    -- merge with the default builtin previewer
    opts.previewer = vim.tbl_deep_extend("keep",
      opts.previewer, M.globals.previewers.builtin)
  end

  if opts.cwd and #opts.cwd > 0 then
    opts.cwd = vim.fn.expand(opts.cwd)
  end

  local executable = function(binary, fncerr,  strerr)
    if binary and vim.fn.executable(binary) ~= 1 then
      fncerr(("'%s' is not a valid executable, %s"):format(binary, strerr))
      return false
    end
    return true
  end

  opts.fzf_bin = opts.fzf_bin or M.globals.fzf_bin
  if not opts.fzf_bin or
     not executable(opts.fzf_bin, utils.warn, "fallback to 'fzf'.") then
    -- default|fallback to fzf
    opts.fzf_bin = "fzf"
    if not executable(opts.fzf_bin, utils.err,
      "aborting. Please make sure 'fzf' is in installed.") then
      return nil
    end
  end

  -- are we using skim?
  opts._is_skim = opts.fzf_bin:find('sk') ~= nil

  return opts
end

return M
