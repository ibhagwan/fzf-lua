local path = require "fzf-lua.path"
local utils = require "fzf-lua.utils"
local actions = require "fzf-lua.actions"
local previewers = require "fzf-lua.previewer"

-- Clear the default command or it would interfere with our options
-- not needed anymore, we are pretty much overriding all options
-- with our cli args, in addition this could conflict with fzf.vim
-- vim.env.FZF_DEFAULT_OPTS = ''

local M = {}

M._has_devicons, M._devicons = pcall(require, "nvim-web-devicons")

-- get the devicons module path
M._devicons_path = M._has_devicons and M._devicons and M._devicons.setup
  and debug.getinfo(M._devicons.setup, 'S').source:gsub("^@", "")

function M._default_previewer_fn()
  return M.globals.default_previewer or M.globals.winopts.preview.default
end

-- set this so that make_entry won't
-- get nil err when setting remotely
M.__resume_data = {}

M.globals = {
  global_resume         = true,
  winopts = {
    height              = 0.85,
    width               = 0.80,
    row                 = 0.35,
    col                 = 0.55,
    border              = 'rounded',
    fullscreen          = false,
    hl = {
      normal            = 'Normal',
      border            = 'Normal',
      -- builtin preview only
      cursor            = 'Cursor',
      cursorline        = 'CursorLine',
      search            = 'Search',
      -- title          = 'Normal',
      -- scrollbar_f    = 'PmenuThumb',
      -- scrollbar_e    = 'PmenuSbar',
    },
    preview = {
      default             = "builtin",
      border              = 'border',
      wrap                = 'nowrap',
      hidden              = 'nohidden',
      vertical            = 'down:45%',
      horizontal          = 'right:60%',
      layout              = 'flex',
      flip_columns        = 120,
      title               = true,
      scrollbar           = 'border',
      scrolloff           = '-2',
      scrollchar          = '',
      scrollchars         = {'█', '' },
      -- default preview delay 100ms, same as native fzf preview
      -- https://github.com/junegunn/fzf/issues/2417#issuecomment-809886535
      delay               = 100,
      winopts = {
        number            = true,
        relativenumber    = false,
        cursorline        = true,
        cursorlineopt     = 'both',
        cursorcolumn      = false,
        signcolumn        = 'no',
        list              = false,
        foldenable        = false,
        foldmethod        = 'manual',
      },
    },
    _borderchars          = {
      ["none"]            = {' ', ' ', ' ', ' ', ' ', ' ', ' ', ' ' },
      ["single"]          = {'┌', '─', '┐', '│', '┘', '─', '└', '│' },
      ["double"]          = {'╔', '═', '╗', '║', '╝', '═', '╚', '║' },
      ["rounded"]         = {'╭', '─', '╮', '│', '╯', '─', '╰', '│' },
    },
    on_create = function()
      -- vim.cmd("set winhl=Normal:Normal,FloatBorder:Normal")
    end,
  },
  keymap = {
    builtin = {
      ["<F2>"]      = "toggle-fullscreen",
      -- Only valid with the 'builtin' previewer
      ["<F3>"]      = "toggle-preview-wrap",
      ["<F4>"]      = "toggle-preview",
      ["<F5>"]      = "toggle-preview-ccw",
      ["<F6>"]      = "toggle-preview-cw",
      ["<S-down>"]  = "preview-page-down",
      ["<S-up>"]    = "preview-page-up",
      ["<S-left>"]  = "preview-page-reset",
    },
    fzf = {
      ["ctrl-z"]        = "abort",
      ["ctrl-u"]        = "unix-line-discard",
      ["ctrl-f"]        = "half-page-down",
      ["ctrl-b"]        = "half-page-up",
      ["ctrl-a"]        = "beginning-of-line",
      ["ctrl-e"]        = "end-of-line",
      ["alt-a"]         = "toggle-all",
      -- Only valid with fzf previewers (bat/cat/git/etc)
      ["f3"]            = "toggle-preview-wrap",
      ["f4"]            = "toggle-preview",
      ["shift-down"]    = "preview-page-down",
      ["shift-up"]      = "preview-page-up",
    },
  },
  fzf_bin             = nil,
  fzf_opts = {
    ['--ansi']        = '',
    ['--prompt']      = '> ',
    ['--info']        = 'inline',
    ['--height']      = '100%',
    ['--layout']      = 'reverse',
  },
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
    man = {
      cmd             = "man -c %s | col -bx",
      _ctor           = previewers.builtin.man_pages,
    },
    builtin = {
      syntax          = true,
      syntax_delay    = 0,
      syntax_limit_l  = 0,
      syntax_limit_b  = 1024*1024,
      _ctor           = previewers.builtin.buffer_or_file,
    },
  },
}
M.globals.files = {
    previewer           = M._default_previewer_fn,
    prompt              = '> ',
    cmd                 = nil,  -- default: auto detect find|fd
    multiprocess        = true,
    file_icons          = true and M._has_devicons,
    color_icons         = true,
    git_icons           = true,
    git_status_cmd      = {"git", "status", "-s"},
    find_opts           = [[-type f -not -path '*/\.git/*' -printf '%P\n']],
    rg_opts             = "--color=never --files --hidden --follow -g '!.git'",
    fd_opts             = "--color=never --type f --hidden --follow --exclude .git",
    actions = {
      ["default"]       = actions.file_edit_or_qf,
      ["ctrl-s"]        = actions.file_split,
      ["ctrl-v"]        = actions.file_vsplit,
      ["ctrl-t"]        = actions.file_tabedit,
      ["alt-q"]         = actions.file_sel_to_qf,
    },
  }
-- Must construct our opts table in stages
-- so we can reference 'M.globals.files'
M.globals.git = {
    files = {
      previewer     = M._default_previewer_fn,
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
        ["default"] = actions.git_checkout,
      },
    },
    bcommits = {
      prompt        = 'BCommits> ',
      cmd           = "git log --pretty=oneline --abbrev-commit --color",
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
    previewer           = M._default_previewer_fn,
    prompt              = 'Rg> ',
    input_prompt        = 'Grep For> ',
    cmd                 = nil,  -- default: auto detect rg|grep
    multiprocess        = true,
    file_icons          = true and M._has_devicons,
    color_icons         = true,
    git_icons           = true,
    grep_opts           = "--binary-files=without-match --line-number --recursive --color=auto --perl-regexp",
    rg_opts             = "--column --line-number --no-heading --color=always --smart-case --max-columns=512",
    actions             = M.globals.files.actions,
    -- live_grep_glob options
    glob_flag           = "--iglob",  -- for case sensitive globs use '--glob'
    glob_separator      = "%s%-%-",   -- query separator pattern (lua): ' --'
  }
M.globals.args = {
    previewer           = M._default_previewer_fn,
    prompt              = 'Args> ',
    files_only          = true,
    file_icons          = true and M._has_devicons,
    color_icons         = true,
    git_icons           = true,
    actions             = M.globals.files.actions,
  }
M.globals.args.actions["ctrl-x"] = actions.arg_del
M.globals.oldfiles = {
    previewer           = M._default_previewer_fn,
    prompt              = 'History> ',
    file_icons          = true and M._has_devicons,
    color_icons         = true,
    git_icons           = false,
    actions             = M.globals.files.actions,
  }
M.globals.quickfix = {
    previewer           = M._default_previewer_fn,
    prompt              = 'Quickfix> ',
    separator           = '▏',
    file_icons          = true and M._has_devicons,
    color_icons         = true,
    git_icons           = false,
    actions             = M.globals.files.actions,
  }
M.globals.loclist = {
    previewer           = M._default_previewer_fn,
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
        ["ctrl-x"]        = { actions.buf_del, actions.resume },
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
        ["ctrl-x"]        = { actions.buf_del, actions.resume },
    },
  }
M.globals.lines = {
    previewer             = "builtin",
    prompt                = 'Lines> ',
    file_icons            = true and M._has_devicons,
    color_icons           = true,
    show_unlisted         = false,
    no_term_buffers       = true,
    fzf_opts = {
        ['--delimiter']   = vim.fn.shellescape(']'),
        ["--nth"]         = '2..',
        ["--tiebreak"]    = 'index',
    },
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
    show_unlisted         = true,
    no_term_buffers       = false,
    fzf_opts = {
        ['--delimiter']   = vim.fn.shellescape('[:]'),
        ["--with-nth"]    = '2..',
        ["--tiebreak"]    = 'index',
    },
    actions = {
        ["default"]       = actions.buf_edit,
        ["ctrl-s"]        = actions.buf_split,
        ["ctrl-v"]        = actions.buf_vsplit,
        ["ctrl-t"]        = actions.buf_tabedit,
    },
  }
M.globals.tags = {
    previewer             = { _ctor = previewers.builtin.tags },
    prompt                = 'Tags> ',
    ctags_file            = "tags",
    file_icons            = true and M._has_devicons,
    git_icons             = true,
    color_icons           = true,
    actions               = M.globals.files.actions,
  }
M.globals.btags = {
    previewer             = { _ctor = previewers.builtin.tags },
    prompt                = 'BTags> ',
    ctags_file            = "tags",
    file_icons            = true and M._has_devicons,
    git_icons             = true,
    color_icons           = true,
    actions               = M.globals.files.actions,
  }
M.globals.colorschemes = {
      prompt              = 'Colorschemes> ',
      live_preview        = true,
      actions = {
        ["default"]       = actions.colorscheme,
      },
      winopts = {
        height            = 0.55,
        width             = 0.50,
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
      previewer           = "man",
  }
M.globals.lsp = {
      previewer           = M._default_previewer_fn,
      prompt              = '> ',
      file_icons          = true and M._has_devicons,
      color_icons         = true,
      git_icons           = false,
      lsp_icons           = true,
      severity            = "hint",
      cwd_only            = false,
      async_or_timeout    = 5000,
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
        height            = 0.65,
        width             = 0.50,
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
    jumps = {
      prompt              = 'Jumps> ',
      cmd                 = "jumps",
      actions = {
        ["default"]       = actions.goto_jump,
      },
      previewer = {
        _ctor             = previewers.builtin.jumps,
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
      fzf_opts            = { ["--tiebreak"] = 'index', },
      actions = {
        ["default"]       = actions.ex_run_cr,
        ["ctrl-e"]        = actions.ex_run,
      },
    },
    search_history = {
      prompt              = 'Search History> ',
      fzf_opts            = { ["--tiebreak"] = 'index', },
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

if not M._has_devicons then
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

  -- First, merge with provider defaults
  -- we must clone the 'defaults' tbl, otherwise 'opts.actions.default'
  -- overrides 'config.globals.lsp.actions.default' in neovim 6.0
  -- which then prevents the default action of all other LSP providers
  -- https://github.com/ibhagwan/fzf-lua/issues/197
  opts = vim.tbl_deep_extend("keep", opts, utils.tbl_deep_clone(defaults))

  -- Merge required tables from globals
  for _, k in ipairs({ 'winopts', 'keymap', 'fzf_opts', 'previewers' }) do
    opts[k] = vim.tbl_deep_extend("keep",
      -- must clone or map will be saved as reference
      -- and then overwritten if found in 'backward_compat'
      opts[k] or {}, utils.tbl_deep_clone(M.globals[k]) or {})
  end

  -- backward compatibility, rhs overrides lhs
  -- (rhs being the "old" option)
  local backward_compat = {
    ['winopts.row']                   = 'winopts.win_row',
    ['winopts.col']                   = 'winopts.win_col',
    ['winopts.width']                 = 'winopts.win_width',
    ['winopts.height']                = 'winopts.win_height',
    ['winopts.border']                = 'winopts.win_border',
    ['winopts.on_create']             = 'winopts.window_on_create',
    ['winopts.preview.wrap']          = 'preview_wrap',
    ['winopts.preview.border']        = 'preview_border',
    ['winopts.preview.hidden']        = 'preview_opts',
    ['winopts.preview.vertical']      = 'preview_vertical',
    ['winopts.preview.horizontal']    = 'preview_horizontal',
    ['winopts.preview.layout']        = 'preview_layout',
    ['winopts.preview.flip_columns']  = 'flip_columns',
    ['winopts.preview.default']       = 'default_previewer',
    ['winopts.hl.normal']             = 'winopts.hl_normal',
    ['winopts.hl.border']             = 'winopts.hl_border',
    ['winopts.hl.cursor']             = 'previewers.builtin.hl_cursor',
    ['winopts.hl.cursorline']         = 'previewers.builtin.hl_cursorline',
    ['winopts.preview.delay']         = 'previewers.builtin.delay',
    ['winopts.preview.title']         = 'previewers.builtin.title',
    ['winopts.preview.scrollbar']     = 'previewers.builtin.scrollbar',
    ['winopts.preview.scrollchar']    = 'previewers.builtin.scrollchar',
  }

  -- recursive key loopkup, can also set new value
  local map_recurse = function(m, s, v, w)
    local keys = utils.strsplit(s, '.')
    local val, map = m, nil
    for i=1,#keys do
      map = val
      val = val[keys[i]]
      if not val then break end
      if v~=nil and i==#keys then map[keys[i]] = v end
    end
    if v and w then utils.warn(w) end
    return val
  end

  -- interate backward compat map, retrieve values from opts or globals
  for k, v in pairs(backward_compat) do
    map_recurse(opts, k, map_recurse(opts, v) or map_recurse(M.globals, v))
     -- ,("'%s' is now defined under '%s'"):format(v, k))
  end

  -- Default prompt
  opts.prompt = opts.prompt or opts.fzf_opts["--prompt"]

  if type(opts.previewer) == 'function' then
    -- we use a function so the user can override
    -- globals.winopts.preview.default
    opts.previewer = opts.previewer()
  end
  if type(opts.previewer) == 'table' then
    -- merge with the default builtin previewer
    opts.previewer = vim.tbl_deep_extend("keep",
      opts.previewer, M.globals.previewers.builtin)
  end

  if opts.cwd and #opts.cwd > 0 then
    opts.cwd = vim.fn.expand(opts.cwd)
    if not vim.loop.fs_stat(opts.cwd) then
      utils.warn(("Unable to access '%s', removing 'cwd' option."):format(opts.cwd))
      opts.cwd = nil
    end
  end

  -- test for valid git_repo
  opts.git_icons = opts.git_icons and path.is_git_repo(opts.cwd, true)

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

  -- libuv.spawn_nvim_fzf_cmd() pid callback
  opts._pid_cb = function(pid) opts._pid = pid end

  -- mark as normalized
  opts._normalized = true

  return opts
end

return M
