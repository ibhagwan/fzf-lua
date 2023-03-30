local utils = require "fzf-lua.utils"
local actions = require "fzf-lua.actions"
local previewers = require "fzf-lua.previewer"

local M = {}

M._has_devicons = pcall(require, "nvim-web-devicons")

function M._default_previewer_fn()
  local previewer = M.globals.default_previewer or M.globals.winopts.preview.default
  -- the setup function cannot have a custom previewer as deepcopy
  -- fails with stack overflow while trying to copy the custom class
  -- the workaround is to define the previewer as a function instead
  -- https://github.com/ibhagwan/fzf-lua/issues/677
  return type(previewer) == "function" and previewer() or previewer
end

M.defaults = {
  nbsp          = utils.nbsp,
  global_resume = true,
  winopts       = {
    height     = 0.85,
    width      = 0.80,
    row        = 0.35,
    col        = 0.55,
    border     = "rounded",
    fullscreen = false,
    --[[ hl = {
      normal            = 'Normal',
      border            = 'FloatBorder',
      help_normal       = 'Normal',
      help_border       = 'FloatBorder',
      -- builtin preview only
      cursor            = 'Cursor',
      cursorline        = 'CursorLine',
      cursorlinenr      = 'CursorLineNr',
      search            = 'IncSearch',
      title             = 'Normal',
      scrollfloat_e     = 'PmenuSbar',
      scrollfloat_f     = 'PmenuThumb',
      scrollborder_e    = 'FloatBorder',
      scrollborder_f    = 'FloatBorder',
    }, ]]
    preview      = {
      default      = "builtin",
      border       = "border",
      wrap         = "nowrap",
      hidden       = "nohidden",
      vertical     = "down:45%",
      horizontal   = "right:60%",
      layout       = "flex",
      flip_columns = 120,
      title        = true,
      title_align  = "left",
      scrollbar    = "border",
      scrolloff    = "-2",
      scrollchar   = "",
      scrollchars  = { "█", "" },
      -- default preview delay 100ms, same as native fzf preview
      -- https://github.com/junegunn/fzf/issues/2417#issuecomment-809886535
      delay        = 100,
      winopts      = {
        number         = true,
        relativenumber = false,
        cursorline     = true,
        cursorlineopt  = "both",
        cursorcolumn   = false,
        signcolumn     = "no",
        list           = false,
        foldenable     = false,
        foldmethod     = "manual",
        -- >0 to prevent scrolling issues (#500)
        scrolloff      = 1,
      },
    },
    _borderchars = {
      ["none"]    = { " ", " ", " ", " ", " ", " ", " ", " " },
      ["single"]  = { "┌", "─", "┐", "│", "┘", "─", "└", "│" },
      ["double"]  = { "╔", "═", "╗", "║", "╝", "═", "╚", "║" },
      ["rounded"] = { "╭", "─", "╮", "│", "╯", "─", "╰", "│" },
      ["thicc"]   = { "┏", "━", "┓", "┃", "┛", "━", "┗", "┃" },
    },
    on_create    = function()
      -- vim.cmd("set winhl=Normal:Normal,FloatBorder:Normal")
    end,
  },
  keymap        = {
    builtin = {
      ["<F1>"]     = "toggle-help",
      ["<F2>"]     = "toggle-fullscreen",
      -- Only valid with the 'builtin' previewer
      ["<F3>"]     = "toggle-preview-wrap",
      ["<F4>"]     = "toggle-preview",
      ["<F5>"]     = "toggle-preview-ccw",
      ["<F6>"]     = "toggle-preview-cw",
      ["<S-down>"] = "preview-page-down",
      ["<S-up>"]   = "preview-page-up",
      ["<S-left>"] = "preview-page-reset",
    },
    fzf = {
      ["ctrl-z"]     = "abort",
      ["ctrl-u"]     = "unix-line-discard",
      ["ctrl-f"]     = "half-page-down",
      ["ctrl-b"]     = "half-page-up",
      ["ctrl-a"]     = "beginning-of-line",
      ["ctrl-e"]     = "end-of-line",
      ["alt-a"]      = "toggle-all",
      -- Only valid with fzf previewers (bat/cat/git/etc)
      ["f3"]         = "toggle-preview-wrap",
      ["f4"]         = "toggle-preview",
      ["shift-down"] = "preview-page-down",
      ["shift-up"]   = "preview-page-up",
    },
  },
  actions       = {
    files = {
      ["default"] = actions.file_edit_or_qf,
      ["ctrl-s"]  = actions.file_split,
      ["ctrl-v"]  = actions.file_vsplit,
      ["ctrl-t"]  = actions.file_tabedit,
      ["alt-q"]   = actions.file_sel_to_qf,
      ["alt-l"]   = actions.file_sel_to_ll,
    },
    buffers = {
      ["default"] = actions.buf_edit,
      ["ctrl-s"]  = actions.buf_split,
      ["ctrl-v"]  = actions.buf_vsplit,
      ["ctrl-t"]  = actions.buf_tabedit,
    }
  },
  fzf_bin       = nil,
  fzf_opts      = {
    ["--ansi"]   = "",
    ["--info"]   = "inline",
    ["--height"] = "100%",
    ["--layout"] = "reverse",
    ["--border"] = "none",
  },
  fzf_tmux_opts = { ["-p"] = "80%,80%",["--margin"] = "0,0" },
  previewers    = {
    cat = {
      cmd   = "cat",
      args  = "-n",
      _ctor = previewers.fzf.cmd,
    },
    bat = {
      cmd    = "bat",
      args   = "--italic-text=always --style=numbers,changes --color always",
      theme  = nil,
      config = nil,
      _ctor  = previewers.fzf.bat_async,
    },
    bat_native = {
      cmd   = "bat",
      args  = "--italic-text=always --style=numbers,changes --color always",
      _ctor = previewers.fzf.bat,
    },
    bat_async = {
      cmd   = "bat",
      args  = "--italic-text=always --style=numbers,changes --color always",
      _ctor = previewers.fzf.bat_async,
    },
    head = {
      cmd   = "head",
      args  = nil,
      _ctor = previewers.fzf.head,
    },
    git_diff = {
      cmd_deleted   = "git diff --color HEAD --",
      cmd_modified  = "git diff --color HEAD",
      cmd_untracked = "git diff --color --no-index /dev/null",
      _fn_git_icons = function() return M.globals.git.icons end,
      _ctor         = previewers.fzf.git_diff,
    },
    man = {
      cmd   = utils.is_darwin() and "man -P cat %s | col -bx" or "man -c %s | col -bx",
      _ctor = previewers.builtin.man_pages,
    },
    man_native = {
      _ctor = previewers.fzf.man_pages,
    },
    help_tags = {
      split = "botright", -- "topleft"
      _ctor = previewers.builtin.help_tags,
    },
    help_file = {
      _ctor = previewers.builtin.help_file,
    },
    help_native = {
      _ctor = previewers.fzf.help_tags,
    },
    builtin = {
      syntax          = true,
      syntax_delay    = 0,
      syntax_limit_l  = 0,
      syntax_limit_b  = 1024 * 1024,      -- 1MB
      limit_b         = 1024 * 1024 * 10, -- 10MB
      treesitter      = { enable = true, disable = {} },
      ueberzug_scaler = "cover",
      _ctor           = previewers.builtin.buffer_or_file,
    },
  },
}

M.defaults.files = {
  previewer      = M._default_previewer_fn,
  prompt         = "> ",
  cmd            = nil, -- default: auto detect find|fd
  multiprocess   = true,
  file_icons     = true and M._has_devicons,
  color_icons    = true,
  git_icons      = true,
  git_status_cmd = { "git", "status", "-s" },
  find_opts      = [[-type f -not -path '*/\.git/*' -printf '%P\n']],
  rg_opts        = "--color=never --files --hidden --follow -g '!.git'",
  fd_opts        = "--color=never --type f --hidden --follow --exclude .git",
  _actions       = function() return M.globals.actions.files end,
}

-- Must construct our opts table in stages
-- so we can reference 'M.globals.files'
M.defaults.git = {
  files = {
    previewer    = M._default_previewer_fn,
    prompt       = "GitFiles> ",
    cmd          = "git ls-files --exclude-standard",
    multiprocess = true,
    file_icons   = true and M._has_devicons,
    color_icons  = true,
    git_icons    = true,
    _actions     = function() return M.globals.actions.files end,
  },
  status = {
    prompt      = "GitStatus> ",
    -- override `color.status=always`, techincally not required
    -- since we now also call `utils.strip_ansi_coloring` (#706)
    cmd         = "git -c color.status=false status -s",
    previewer   = "git_diff",
    file_icons  = true and M._has_devicons,
    color_icons = true,
    git_icons   = true,
    _actions    = function() return M.globals.actions.files end,
    actions     = {
      ["right"] = { actions.git_unstage, actions.resume },
      ["left"]  = { actions.git_stage, actions.resume },
    },
  },
  commits = {
    prompt  = "Commits> ",
    cmd     = "git log --color --pretty=format:'%C(yellow)%h%Creset %Cgreen(%><(12)%cr%><|(12))" ..
        "%Creset %s %C(blue)<%an>%Creset'",
    preview = "git show --pretty='%Cred%H%n%Cblue%an <%ae>%n%C(yellow)%cD%n%Cgreen%s' --color {1}",
    actions = {
      ["default"] = actions.git_checkout,
    },
  },
  bcommits = {
    prompt  = "BCommits> ",
    cmd     = "git log --color --pretty=format:'%C(yellow)%h%Creset %Cgreen(%><(12)%cr%><|(12))" ..
        "%Creset %s %C(blue)<%an>%Creset' <file>",
    preview = "git diff --color {1}~1 {1} -- <file>",
    actions = {
      ["default"] = actions.git_buf_edit,
      ["ctrl-s"]  = actions.git_buf_split,
      ["ctrl-v"]  = actions.git_buf_vsplit,
      ["ctrl-t"]  = actions.git_buf_tabedit,
    },
  },
  branches = {
    prompt  = "Branches> ",
    cmd     = "git branch --all --color",
    preview = "git log --graph --pretty=oneline --abbrev-commit --color {1}",
    actions = {
      ["default"] = actions.git_switch,
    },
  },
  stash = {
    prompt   = "Stash> ",
    cmd      = "git --no-pager stash list",
    preview  = "git --no-pager stash show --patch --color {1}",
    actions  = {
      ["default"] = actions.git_stash_apply,
      ["ctrl-x"]  = { actions.git_stash_drop, actions.resume },
    },
    fzf_opts = {
      -- TODO: multiselect requires more work as dropping
      -- a stash changes the stash index, causing an error
      -- when the next stash is attempted
      ["--no-multi"]  = "",
      ["--delimiter"] = "'[:]'",
    },
  },
  icons = {
    ["M"] = { icon = "M", color = "yellow" },
    ["D"] = { icon = "D", color = "red" },
    ["A"] = { icon = "A", color = "green" },
    ["R"] = { icon = "R", color = "yellow" },
    ["C"] = { icon = "C", color = "yellow" },
    ["T"] = { icon = "T", color = "magenta" },
    ["?"] = { icon = "?", color = "magenta" },
  },
}

M.defaults.grep = {
  previewer      = M._default_previewer_fn,
  prompt         = "Rg> ",
  input_prompt   = "Grep For> ",
  cmd            = nil, -- default: auto detect rg|grep
  multiprocess   = true,
  file_icons     = true and M._has_devicons,
  color_icons    = true,
  git_icons      = true,
  grep_opts      = utils.is_darwin()
      and "--binary-files=without-match --line-number --recursive --color=always --extended-regexp"
      or "--binary-files=without-match --line-number --recursive --color=always --perl-regexp",
  rg_opts        = "--column --line-number --no-heading --color=always --smart-case " ..
      "--max-columns=4096",
  _actions       = function() return M.globals.actions.files end,
  actions        = { ["ctrl-g"] = { actions.grep_lgrep } },
  -- live_grep_glob options
  glob_flag      = "--iglob", -- for case sensitive globs use '--glob'
  glob_separator = "%s%-%-",  -- query separator pattern (lua): ' --'
}

M.defaults.args = {
  previewer   = M._default_previewer_fn,
  prompt      = "Args> ",
  files_only  = true,
  file_icons  = true and M._has_devicons,
  color_icons = true,
  git_icons   = true,
  _actions    = function() return M.globals.actions.files end,
  actions     = {
    ["ctrl-x"] = { actions.arg_del, actions.resume }
  },
}

M.defaults.oldfiles = {
  previewer   = M._default_previewer_fn,
  prompt      = "History> ",
  file_icons  = true and M._has_devicons,
  color_icons = true,
  git_icons   = false,
  stat_file   = true,
  fzf_opts    = { ["--tiebreak"] = "index", },
  _actions    = function() return M.globals.actions.files end,
}

M.defaults.quickfix = {
  previewer   = M._default_previewer_fn,
  prompt      = "Quickfix> ",
  separator   = "▏",
  file_icons  = true and M._has_devicons,
  color_icons = true,
  git_icons   = false,
  _actions    = function() return M.globals.actions.files end,
}

M.defaults.quickfix_stack = {
  prompt    = "Quickfix Stack> ",
  marker    = ">",
  previewer = { _ctor = previewers.builtin.quickfix, },
  actions   = { ["default"] = actions.set_qflist, },
}

M.defaults.loclist = {
  previewer   = M._default_previewer_fn,
  prompt      = "Locations> ",
  separator   = "▏",
  file_icons  = true and M._has_devicons,
  color_icons = true,
  git_icons   = false,
  _actions    = function() return M.globals.actions.files end,
}

M.defaults.loclist_stack = {
  prompt    = "Locations Stack> ",
  marker    = ">",
  previewer = { _ctor = previewers.builtin.quickfix, },
  actions   = { ["default"] = actions.set_qflist, },
}

M.defaults.buffers = {
  previewer             = M._default_previewer_fn,
  prompt                = "Buffers> ",
  file_icons            = true and M._has_devicons,
  color_icons           = true,
  sort_lastused         = true,
  show_all_buffers      = true,
  ignore_current_buffer = false,
  no_action_set_cursor  = true,
  cwd_only              = false,
  cwd                   = nil,
  fzf_opts              = { ["--tiebreak"] = "index", },
  _actions              = function() return M.globals.actions.buffers end,
  actions               = {
    ["ctrl-x"] = { actions.buf_del, actions.resume },
  },
}

M.defaults.tabs = {
  previewer   = M._default_previewer_fn,
  prompt      = "Tabs> ",
  tab_title   = "Tab",
  tab_marker  = "<<",
  file_icons  = true and M._has_devicons,
  color_icons = true,
  _actions    = function() return M.globals.actions.buffers end,
  actions     = {
    ["default"] = actions.buf_switch,
    ["ctrl-x"]  = { actions.buf_del, actions.resume },
  },
  fzf_opts    = {
    ["--delimiter"] = "'[\\):]'",
    ["--with-nth"]  = "2..",
  },
}

M.defaults.lines = {
  previewer       = M._default_previewer_fn,
  prompt          = "Lines> ",
  file_icons      = true and M._has_devicons,
  color_icons     = true,
  show_unlisted   = false,
  no_term_buffers = true,
  fzf_opts        = {
    ["--delimiter"] = "'[\\]:]'",
    ["--nth"]       = "2..",
    ["--tiebreak"]  = "index",
    ["--tabstop"]   = "1",
  },
  _actions        = function() return M.globals.actions.buffers end,
  actions         = {
    ["default"] = actions.buf_edit_or_qf,
    ["alt-q"]   = actions.buf_sel_to_qf,
    ["alt-l"]   = actions.buf_sel_to_ll
  },
}

M.defaults.blines = {
  previewer       = M._default_previewer_fn,
  prompt          = "BLines> ",
  file_icons      = false,
  color_icons     = false,
  show_unlisted   = true,
  no_term_buffers = false,
  fzf_opts        = {
    ["--delimiter"] = "'[:]'",
    ["--with-nth"]  = "2..",
    ["--tiebreak"]  = "index",
    ["--tabstop"]   = "1",
  },
  _actions        = function() return M.globals.actions.buffers end,
  actions         = {
    ["default"] = actions.buf_edit_or_qf,
    ["alt-q"]   = actions.buf_sel_to_qf,
    ["alt-l"]   = actions.buf_sel_to_ll
  },
}

M.defaults.tags = {
  previewer    = { _ctor = previewers.builtin.tags },
  prompt       = "Tags> ",
  ctags_file   = nil, -- auto-detect
  rg_opts      = "--no-heading --color=always --smart-case",
  grep_opts    = "--color=auto --perl-regexp",
  multiprocess = true,
  file_icons   = true and M._has_devicons,
  git_icons    = true,
  color_icons  = true,
  _actions     = function() return M.globals.actions.files end,
  actions      = { ["ctrl-g"] = { actions.grep_lgrep } },
}

M.defaults.btags = {
  previewer    = { _ctor = previewers.builtin.tags },
  prompt       = "BTags> ",
  ctags_file   = nil, -- auto-detect
  rg_opts      = "--no-heading --color=always",
  grep_opts    = "--color=auto --perl-regexp",
  multiprocess = true,
  file_icons   = true and M._has_devicons,
  git_icons    = true,
  color_icons  = true,
  fzf_opts     = {
    ["--delimiter"] = "'[:]'",
    ["--with-nth"]  = "2..",
    ["--tiebreak"]  = "index",
  },
  _actions     = function() return M.globals.actions.files end,
  actions      = { ["ctrl-g"] = false },
}

M.defaults.colorschemes = {
  prompt       = "Colorschemes> ",
  live_preview = true,
  actions      = {
    ["default"] = actions.colorscheme,
  },
  winopts      = {
    height = 0.55,
    width  = 0.50,
  },
}

M.defaults.highlights = {
  prompt    = "highlights> ",
  previewer = { _ctor = previewers.builtin.highlights, },
}

M.defaults.helptags = {
  prompt    = "Help> ",
  actions   = {
    ["default"] = actions.help,
    ["ctrl-s"]  = actions.help,
    ["ctrl-v"]  = actions.help_vert,
    ["ctrl-t"]  = actions.help_tab,
  },
  fzf_opts  = {
    ["--delimiter"] = "'[ ]'",
    ["--with-nth"]  = "..-2",
  },
  previewer = {
    _ctor = previewers.builtin.help_file,
  },
}

M.defaults.manpages = {
  prompt    = "Man> ",
  cmd       = "man -k .",
  actions   = {
    ["default"] = actions.man,
    ["ctrl-s"]  = actions.man,
    ["ctrl-v"]  = actions.man_vert,
    ["ctrl-t"]  = actions.man_tab,
  },
  fzf_opts  = { ["--tiebreak"] = "begin" },
  previewer = "man",
}

M.defaults.lsp = {
  previewer        = M._default_previewer_fn,
  prompt_postfix   = "> ",
  file_icons       = true and M._has_devicons,
  color_icons      = true,
  git_icons        = false,
  cwd_only         = false,
  async_or_timeout = 5000,
  _actions         = function() return M.globals.actions.files end,
}

M.defaults.lsp.symbols = {
  previewer        = M._default_previewer_fn,
  prompt_postfix   = "> ",
  file_icons       = true and M._has_devicons,
  color_icons      = true,
  git_icons        = false,
  symbol_style     = 1,
  symbol_icons     = {
    File          = "",
    Module        = "",
    Namespace     = "󰦮",
    Package       = "",
    Class         = "",
    Method        = "",
    Property      = "",
    Field         = "",
    Constructor   = "",
    Enum          = "",
    Interface     = "",
    Function      = "",
    Variable      = "",
    Constant      = "",
    String        = "",
    Number        = "󰎠",
    Boolean       = "󰨙",
    Array         = "󱡠",
    Object        = "",
    Key           = "",
    Null          = "󰟢",
    EnumMember    = "",
    Struct        = "",
    Event         = "",
    Operator      = "",
    TypeParameter = "󰗴",
  },
  symbol_hl        = function(s) return "@" .. s:lower() end,
  symbol_fmt       = function(s, _) return "[" .. s .. "]" end,
  child_prefix     = true,
  async_or_timeout = true,
  _actions         = function() return M.globals.actions.files end,
  actions          = { ["ctrl-g"] = { actions.sym_lsym } },
}

M.defaults.lsp.finder = {
  previewer   = M._default_previewer_fn,
  prompt      = "LSP Finder> ",
  file_icons  = true and M._has_devicons,
  color_icons = true,
  git_icons   = false,
  async       = true,
  silent      = true,
  separator   = "| ",
  _actions    = function() return M.globals.actions.files end,
  -- currently supported providers, defined as map so we can query easily
  _providers  = {
    references      = true,
    definitions     = true,
    declarations    = true,
    typedefs        = true,
    implementations = true,
    incoming_calls  = true,
    outgoing_calls  = true,
  },
  -- by default display all supported providers
  providers   = {
    { "declarations",    prefix = utils.ansi_codes.magenta("decl") },
    { "implementations", prefix = utils.ansi_codes.green("impl") },
    { "definitions",     prefix = utils.ansi_codes.green("def ") },
    { "typedefs",        prefix = utils.ansi_codes.red("tdef") },
    { "references",      prefix = utils.ansi_codes.blue("ref ") },
    { "incoming_calls",  prefix = utils.ansi_codes.cyan("in  ") },
    { "outgoing_calls",  prefix = utils.ansi_codes.yellow("out ") },
  },
}

M.defaults.lsp.code_actions = {
  prompt           = "Code Actions> ",
  async_or_timeout = 5000,
  winopts          = {
    row    = 0.40,
    height = 0.35,
    width  = 0.60,
  },
}

M.defaults.diagnostics = {
  previewer   = M._default_previewer_fn,
  prompt      = "Diagnostics> ",
  file_icons  = true and M._has_devicons,
  color_icons = true,
  git_icons   = false,
  diag_icons  = true,
  _actions    = function() return M.globals.actions.files end,
  -- signs = {
  --   ["Error"] = { text = "e", texthl = "DiagnosticError" },
  --   ["Warn"]  = { text = "w", texthl = "DiagnosticWarn" },
  --   ["Info"]  = { text = "i", texthl = "DiagnosticInfo" },
  --   ["Hint"]  = { text = "h", texthl = "DiagnosticHint" },
  -- },
}

M.defaults.builtin = {
  prompt  = "Builtin> ",
  winopts = {
    height = 0.65,
    width  = 0.50,
  },
  actions = {
    ["default"] = actions.run_builtin,
  },
}

M.defaults.profiles = {
  previewer = M._default_previewer_fn,
  prompt    = "FzfLua profiles> ",
  fzf_opts  = {
    ["--delimiter"] = "'[:]'",
    ["--with-nth"]  = "2..",
  },
  actions   = {
    ["default"] = actions.apply_profile,
  },
}

M.defaults.marks = {
  prompt    = "Marks> ",
  actions   = {
    ["default"] = actions.goto_mark,
  },
  previewer = {
    _ctor = previewers.builtin.marks,
  },
}

M.defaults.jumps = {
  prompt    = "Jumps> ",
  cmd       = "jumps",
  actions   = {
    ["default"] = actions.goto_jump,
  },
  previewer = {
    _ctor = previewers.builtin.jumps,
  },
}

M.defaults.tagstack = {
  prompt      = "Tagstack> ",
  file_icons  = true and M._has_devicons,
  color_icons = true,
  git_icons   = true,
  previewer   = M._default_previewer_fn,
  _actions    = function() return M.globals.actions.files end,
}

M.defaults.commands = {
  prompt  = "Commands> ",
  actions = {
    ["default"] = actions.ex_run,
  },
}

M.defaults.autocmds = {
  prompt    = "Autocmds> ",
  previewer = { _ctor = previewers.builtin.autocmds },
  _actions  = function() return M.globals.actions.files end,
  fzf_opts  = {
    ["--delimiter"] = "'[:]'",
    ["--with-nth"]  = "3..",
  },
}

M.defaults.command_history = {
  prompt   = "Command History> ",
  fzf_opts = { ["--tiebreak"] = "index", },
  actions  = {
    ["default"] = actions.ex_run_cr,
    ["ctrl-e"]  = actions.ex_run,
  },
}

M.defaults.search_history = {
  prompt   = "Search History> ",
  fzf_opts = { ["--tiebreak"] = "index", },
  actions  = {
    ["default"] = actions.search_cr,
    ["ctrl-e"]  = actions.search,
  },
}

M.defaults.registers = {
  prompt       = "Registers> ",
  ignore_empty = true,
  actions      = {
    ["default"] = actions.paste_register,
  },
}

M.defaults.keymaps = {
  prompt = "Keymaps> ",
  fzf_opts = { ["--tiebreak"] = "index", },
  actions = {
    ["default"] = actions.keymap_apply,
  },
}

M.defaults.spell_suggest = {
  prompt  = "Spelling Suggestions> ",
  actions = {
    ["default"] = actions.spell_apply,
  },
}

M.defaults.filetypes = {
  prompt  = "Filetypes> ",
  actions = {
    ["default"] = actions.set_filetype,
  },
}

M.defaults.packadd = {
  prompt  = "packadd> ",
  actions = {
    ["default"] = actions.packadd,
  },
}

M.defaults.menus = {
  prompt  = "Menu> ",
  actions = {
    ["default"] = actions.exec_menu,
  },
}

M.defaults.tmux = {
  buffers = {
    prompt   = "Tmux Buffers> ",
    cmd      = "tmux list-buffers",
    register = [["]],
    actions  = {
      ["default"] = actions.tmux_buf_set_reg,
    },
  },
}

M.defaults.dap = {
  commands = {
    prompt = "DAP Commands> ",
  },
  configurations = {
    prompt = "DAP Configurations> ",
  },
  variables = {
    prompt = "DAP Variables> ",
  },
  frames = {
    prompt = "DAP Frames> ",
  },
  breakpoints = {
    prompt      = "DAP Breakpoints> ",
    file_icons  = true and M._has_devicons,
    color_icons = true,
    git_icons   = true,
    previewer   = M._default_previewer_fn,
    _actions    = function() return M.globals.actions.files end,
    fzf_opts    = {
      ["--delimiter"] = "'[\\]:]'",
      ["--with-nth"]  = "2..",
    },
  },
}

M.defaults.complete_path = {
  cmd     = nil, -- default: auto detect fd|rg|find
  actions = { ["default"] = actions.complete_insert },
}

M.defaults.complete_file = {
  cmd          = nil, -- default: auto detect rg|fd|find
  multiprocess = true,
  file_icons   = true and M._has_devicons,
  color_icons  = true,
  git_icons    = false,
  _actions     = function() return M.globals.actions.files end,
  actions      = { ["default"] = actions.complete_insert },
  previewer    = M._default_previewer_fn,
  winopts      = { preview = { hidden = "hidden" } },
}

M.defaults.complete_line = {}
M.defaults.complete_bline = {}

M.defaults.file_icon_padding = ""

M.defaults.file_icon_colors = {}

return M
