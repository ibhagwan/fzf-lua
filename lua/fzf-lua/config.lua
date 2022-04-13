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
  nbsp                  = utils.nbsp,
  global_resume         = true,
  global_resume_query   = true,
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
      ["<F1>"]      = "toggle-help",
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
  actions = {
    files = {
      ["default"]       = actions.file_edit_or_qf,
      ["ctrl-s"]        = actions.file_split,
      ["ctrl-v"]        = actions.file_vsplit,
      ["ctrl-t"]        = actions.file_tabedit,
      ["alt-q"]         = actions.file_sel_to_qf,
    },
    buffers = {
      ["default"]       = actions.buf_edit,
      ["ctrl-s"]        = actions.buf_split,
      ["ctrl-v"]        = actions.buf_vsplit,
      ["ctrl-t"]        = actions.buf_tabedit,
    }
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
      cmd_deleted     = "git diff --color HEAD --",
      cmd_modified    = "git diff --color HEAD",
      cmd_untracked   = "git diff --color --no-index /dev/null",
      _fn_git_icons   = function() return M.globals.git.icons end,
      _ctor           = previewers.fzf.git_diff,
    },
    man = {
      cmd             = "man -c %s | col -bx",
      _ctor           = previewers.builtin.man_pages,
    },
    man_native = {
      cmd             = "man",
      _ctor           = previewers.fzf.man_pages,
    },
    builtin = {
      syntax          = true,
      syntax_delay    = 0,
      syntax_limit_l  = 0,
      syntax_limit_b  = 1024*1024,    -- 1MB
      limit_b         = 1024*1024*10, -- 10MB
      ueberzug_scaler = "cover",
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
    _actions            = function() return M.globals.actions.files end,
  }
-- Must construct our opts table in stages
-- so we can reference 'M.globals.files'
M.globals.git = {
    files = {
      previewer     = M._default_previewer_fn,
      prompt        = 'GitFiles> ',
      cmd           = "git ls-files --exclude-standard",
      multiprocess  = true,
      file_icons    = true and M._has_devicons,
      color_icons   = true,
      git_icons     = true,
      _actions      = function() return M.globals.actions.files end,
    },
    status = {
      prompt        = 'GitStatus> ',
      cmd           = "git status -s",
      previewer     = "git_diff",
      file_icons    = true and M._has_devicons,
      color_icons   = true,
      git_icons     = true,
      _actions      = function() return M.globals.actions.files end,
      actions = {
        ["right"]   = { actions.git_unstage, actions.resume },
        ["left"]    = { actions.git_stage, actions.resume },
      },
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
    _actions            = function() return M.globals.actions.files end,
    actions = {
      ["ctrl-g"]        = { actions.grep_lgrep }
    },
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
    _actions            = function() return M.globals.actions.files end,
    actions = {
      ["ctrl-x"]        = { actions.arg_del, actions.resume }
    },
  }
M.globals.oldfiles = {
    previewer           = M._default_previewer_fn,
    prompt              = 'History> ',
    file_icons          = true and M._has_devicons,
    color_icons         = true,
    git_icons           = false,
    stat_file           = true,
    _actions            = function() return M.globals.actions.files end,
  }
M.globals.quickfix = {
    previewer           = M._default_previewer_fn,
    prompt              = 'Quickfix> ',
    separator           = '▏',
    file_icons          = true and M._has_devicons,
    color_icons         = true,
    git_icons           = false,
    _actions            = function() return M.globals.actions.files end,
  }
M.globals.loclist = {
    previewer           = M._default_previewer_fn,
    prompt              = 'Locations> ',
    separator           = '▏',
    file_icons          = true and M._has_devicons,
    color_icons         = true,
    git_icons           = false,
    _actions            = function() return M.globals.actions.files end,
  }
M.globals.buffers = {
    previewer             = M._default_previewer_fn,
    prompt                = 'Buffers> ',
    file_icons            = true and M._has_devicons,
    color_icons           = true,
    sort_lastused         = true,
    show_all_buffers      = true,
    ignore_current_buffer = false,
    cwd_only              = false,
    _actions              = function() return M.globals.actions.buffers end,
    actions = {
        ["ctrl-x"]        = { actions.buf_del, actions.resume },
    },
  }
M.globals.tabs = {
    previewer             = M._default_previewer_fn,
    prompt                = 'Tabs> ',
    tab_title             = "Tab",
    tab_marker            = "<<",
    file_icons            = true and M._has_devicons,
    color_icons           = true,
    _actions              = function() return M.globals.actions.buffers end,
    actions = {
        ["default"]       = actions.buf_switch,
        ["ctrl-x"]        = { actions.buf_del, actions.resume },
    },
    fzf_opts = {
        ['--delimiter']   = "'[\\):]'",
        ["--with-nth"]    = '2..',
    },
  }
M.globals.lines = {
    previewer             = M._default_previewer_fn,
    prompt                = 'Lines> ',
    file_icons            = true and M._has_devicons,
    color_icons           = true,
    show_unlisted         = false,
    no_term_buffers       = true,
    fzf_opts = {
        ['--delimiter']   = "'[\\]:]'",
        ["--nth"]         = '2..',
        ["--tiebreak"]    = 'index',
    },
    _actions              = function() return M.globals.actions.buffers end,
  }
M.globals.blines = {
    previewer             = M._default_previewer_fn,
    prompt                = 'BLines> ',
    file_icons            = true and M._has_devicons,
    color_icons           = true,
    show_unlisted         = true,
    no_term_buffers       = false,
    fzf_opts = {
        ['--delimiter']   = "'[:]'",
        ["--with-nth"]    = '2..',
        ["--tiebreak"]    = 'index',
    },
    _actions              = function() return M.globals.actions.buffers end,
  }
M.globals.tags = {
    previewer             = { _ctor = previewers.builtin.tags },
    prompt                = 'Tags> ',
    ctags_file            = "tags",
    rg_opts               = "--no-heading --color=always --smart-case",
    grep_opts             = "--color=auto --perl-regexp",
    multiprocess          = true,
    file_icons            = true and M._has_devicons,
    git_icons             = true,
    color_icons           = true,
    _actions              = function() return M.globals.actions.files end,
    actions = {
      ["ctrl-g"]          = { actions.grep_lgrep }
    },
  }
M.globals.btags = {
    previewer             = { _ctor = previewers.builtin.tags },
    prompt                = 'BTags> ',
    ctags_file            = "tags",
    rg_opts               = "--no-heading --color=always",
    grep_opts             = "--color=auto --perl-regexp",
    multiprocess          = true,
    file_icons            = true and M._has_devicons,
    git_icons             = true,
    color_icons           = true,
    fzf_opts = {
        ['--delimiter']   = "'[:]'",
        ["--with-nth"]    = '2..',
        ["--tiebreak"]    = 'index',
    },
    _actions              = function() return M.globals.actions.files end,
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
M.globals.highlights = {
      prompt              = 'highlights> ',
      previewer           = { _ctor = previewers.builtin.highlights, },
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
      prompt_postfix      = '> ',
      file_icons          = true and M._has_devicons,
      color_icons         = true,
      git_icons           = false,
      lsp_icons           = true,
      cwd_only            = false,
      ui_select           = true,
      async_or_timeout    = 5000,
      _actions            = function() return M.globals.actions.files end,
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
    tagstack = {
      prompt              = 'Tagstack> ',
      file_icons          = true and M._has_devicons,
      color_icons         = true,
      git_icons           = true,
      previewer           = M._default_previewer_fn,
      _actions            = function() return M.globals.actions.files end,
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

M.globals.dap = {
    commands = {
      prompt              = 'DAP Commands> ',
    },
    configurations = {
      prompt              = 'DAP Configurations> ',
    },
    variables = {
      prompt              = 'DAP Variables> ',
    },
    frames = {
      prompt              = 'DAP Frames> ',
    },
    breakpoints = {
      prompt              = 'DAP Breakpoints> ',
      file_icons          = true and M._has_devicons,
      color_icons         = true,
      git_icons           = true,
      previewer           = M._default_previewer_fn,
      _actions            = function() return M.globals.actions.files end,
      fzf_opts = {
        ['--delimiter']   = "'[\\]:]'",
        ["--with-nth"]    = '2..',
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

  -- opts can also be a function that returns an opts table
  if type(opts) == 'function' then
    opts = opts()
  end

  -- save the user's call parameters separately
  -- we reuse those with 'actions.grep_lgrep'
  opts.__call_opts = opts.__call_opts or utils.deepcopy(opts)

  -- inherit from globals.actions?
  if type(defaults._actions) == 'function' then
    defaults.actions = vim.tbl_deep_extend("keep",
      defaults.actions or {},
      defaults._actions())
  end

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

  local function get_opt(o, t1, t2)
    if t1[o] ~= nil then return t1[o]
    else return t2[o] end
  end

  -- Merge global resume options
  opts.global_resume = get_opt('global_resume', opts, M.globals)
  opts.global_resume_query = get_opt('global_resume_query', opts, M.globals)

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
    else
      -- relative paths in cwd are inaccessible when using multiprocess
      -- as the external process have no awareness of our current working
      -- directory so we must convert to full path (#375)
      if not path.starts_with_separator(opts.cwd) then
        opts.cwd = path.join({ vim.loop.cwd(), opts.cwd })
      end
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
    -- try fzf plugin if fzf is not installed globally
    if vim.fn.executable(opts.fzf_bin) ~= 1 then
      local ok, fzf_plug = pcall(vim.api.nvim_call_function, "fzf#exec", {})
      if ok and fzf_plug then
        opts.fzf_bin = fzf_plug
      end
    end
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

M.bytecode = function(s, datatype)
  local keys = utils.strsplit(s, '.')
  local iter = M
  for i=1,#keys do
    iter = iter[keys[i]]
    if not iter then break end
    if i == #keys and type(iter) == datatype then
      -- Not sure if second argument 'true' is needed
      -- can't find any references for it other than
      -- it being used in packer.nvim
      return string.dump(iter, true)
    end
  end
end

M.set_action_helpstr = function(fn, helpstr)
  assert(type(fn) == 'function')
  M._action_to_helpstr[fn] = helpstr
end

M.get_action_helpstr = function(fn)
  return M._action_to_helpstr[fn]
end

M._action_to_helpstr = {
  [actions.file_edit]             = "file-edit",
  [actions.file_edit_or_qf]       = "file-edit-or-qf",
  [actions.file_split]            = "file-split",
  [actions.file_vsplit]           = "file-vsplit",
  [actions.file_tabedit]          = "file-tabedit",
  [actions.file_sel_to_qf]        = "file-selection-to-qf",
  [actions.file_switch]           = "file-switch",
  [actions.file_switch_or_edit]   = "file-switch-or-edit",
  [actions.buf_edit]              = "buffer-edit",
  [actions.buf_split]             = "buffer-split",
  [actions.buf_vsplit]            = "buffer-vsplit",
  [actions.buf_tabedit]           = "buffer-tabedit",
  [actions.buf_del]               = "buffer-delete",
  [actions.buf_switch]            = "buffer-switch",
  [actions.buf_switch_or_edit]    = "buffer-switch-or-edit",
  [actions.colorscheme]           = "set-colorscheme",
  [actions.run_builtin]           = "run-builtin",
  [actions.ex_run]                = "edit-cmd",
  [actions.ex_run_cr]             = "exec-cmd",
  [actions.search]                = "edit-search",
  [actions.search_cr]             = "exec-search",
  [actions.goto_mark]             = "goto-mark",
  [actions.goto_jump]             = "goto-jump",
  [actions.spell_apply]           = "spell-apply",
  [actions.set_filetype]          = "set-filetype",
  [actions.packadd]               = "packadd",
  [actions.help]                  = "help-open",
  [actions.help_vert]             = "help-vertical",
  [actions.help_tab]              = "help-tab",
  [actions.man]                   = "man-open",
  [actions.man_vert]              = "man-vertical",
  [actions.man_tab]               = "man-tab",
  [actions.git_switch]            = "git-switch",
  [actions.git_checkout]          = "git-checkout",
  [actions.git_stage]             = "git-stage",
  [actions.git_unstage]           = "git-unstage",
  [actions.git_buf_edit]          = "git-buffer-edit",
  [actions.git_buf_tabedit]       = "git-buffer-tabedit",
  [actions.git_buf_split]         = "git-buffer-split",
  [actions.git_buf_vsplit]        = "git-buffer-vsplit",
  [actions.arg_add]               = "arg-list-add",
  [actions.arg_del]               = "arg-list-delete",
  [actions.grep_lgrep]            = "grep<->lgrep",
}

return M
