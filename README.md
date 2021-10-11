<div align="center">

# fzf :heart: lua

![Neovim version](https://img.shields.io/badge/Neovim-0.5-57A143?style=flat-square&logo=neovim)

[Installation](#installation) • [Usage](#usage) • [Commands](#commands) • [Customization](#customization) • [Wiki](https://github.com/ibhagwan/fzf-lua/wiki)

![Demo](https://raw.githubusercontent.com/wiki/ibhagwan/fzf-lua/demo.gif)

[fzf](https://github.com/junegunn/fzf) changed my life, it can change yours too, if you allow it.

  </div>

## Rationale

What more can be said about [fzf](https://github.com/junegunn/fzf)? It is the
single most impactful tool for my command line workflow, once I started using
fzf I couldn’t see myself living without it.
> **To understand fzf properly I highly recommended [fzf
> screencast](https://www.youtube.com/watch?v=qgG5Jhi_Els) by
> [@samoshkin](https://github.com/samoshkin)**

This is my take on the original
[fzf.vim](https://github.com/junegunn/fzf.vim), written in lua for neovim 0.5,
it builds on the elegant
[nvim-fzf](https://github.com/vijaymarupudi/nvim-fzf) as an async interface to
create a performant and lightweight fzf client for neovim that rivals any of
the new shiny fuzzy finders for neovim.

## Why Fzf-Lua

... and not, to name a few,
[telescope](https://github.com/nvim-telescope/telescope.nvim) or
[vim-clap](https://github.com/liuchengxu/vim-clap)?

As [@junegunn](https://github.com/junegunn) himself put it, “because you can
and you love `fzf`”.

If you’re happy with your current setup there is absolutely no reason to switch.

That said, without taking anything away from the greatness of other plugins I
found it more efficient having a uniform experience between my shell and my
nvim. In addition `fzf` has been a rock for me since I started using it and
hadn’t failed me once, it never hangs and can handle almost anything you throw
at it. That, **and colorful file icons and git indicators!**.

## Dependencies

- `Linux` or `MacOS` only, see [nvim-fzf's How it
  works](https://github.com/vijaymarupudi/nvim-fzf#How-it-works)
- [`fzf`](https://github.com/junegunn/fzf) or
  [`skim`](https://github.com/lotabout/skim) binary installed
- [nvim-fzf](https://github.com/vijaymarupudi/nvim-fzf)
- [nvim-web-devicons](https://github.com/kyazdani42/nvim-web-devicons)
  (optional)

### Optional dependencies

Recommended optional utilities:

- [fd](https://github.com/sharkdp/fd) - better performance `find` utility
- [bat](https://github.com/sharkdp/bat) - for colorful syntax highlighted previews
- [ripgrep](https://github.com/BurntSushi/ripgrep) - for better grep-like searches

## Installation

Using [vim-plug](https://github.com/junegunn/vim-plug)

```vim
Plug 'ibhagwan/fzf-lua'
Plug 'vijaymarupudi/nvim-fzf'
Plug 'kyazdani42/nvim-web-devicons'
```

Using [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use { 'ibhagwan/fzf-lua',
  requires = {
    'vijaymarupudi/nvim-fzf',
    'kyazdani42/nvim-web-devicons' } -- optional for icons
}
```
> **Note:** if you already have fzf installed you do not need to install `fzf`
> or `fzf.vim`, however if you do not have it installed, **you only need** fzf
> which can be installed with (fzf.vim is not a requirement nor conflict):
> ```vim
> Plug 'junegunn/fzf', { 'do': { -> fzf#install() } }
> ```
> or with [packer.nvim](https://github.com/wbthomason/packer.nvim):
>```lua
>use = { 'junegunn/fzf', run = './install --bin', }
>```

## Usage

Fzf-lua aims to be as plug and play as possible with sane defaults, you can
run any fzf-lua command like this:

```lua
:lua require('fzf-lua').files()
-- or using the `FzfLua` vim command:
:FzfLua files
```

or with arguments:
```lua
:lua require('fzf-lua').files({ cwd = '~/.config' })
-- or using the `FzfLua` vim command:
:FzfLua files cwd=~/.config
```

which can be easily mapped to:
```vim
nnoremap <c-P> <cmd>lua require('fzf-lua').files()<CR>
```

or if using `init.lua`:
```lua
vim.api.nvim_set_keymap('n', '<c-P>',
    "<cmd>lua require('fzf-lua').files()<CR>",
    { noremap = true, silent = true })
```

## Commands

### Buffers and Files
| Command          | List                                       |
| ---------------- | ------------------------------------------ |
| `buffers`          | open buffers                               |
| `files`            | `find` or `fd` on a path                       |
| `files_resume`     | continious query find                      |
| `oldfiles`         | opened files history                       |
| `quickfix`         | quickfix list                              |
| `loclist`          | location list                              |
| `lines`            | open buffers lines                         |
| `blines`           | current buffer lines                       |
| `tabs`             | open tabs                                  |
| `args`             | argument list                              |

### Search
| Command          | List                                       |
| ---------------- | ------------------------------------------ |
| `grep`             | search for a pattern with `grep` or `rg`       |
| `grep_last`        | run search again with the last pattern     |
| `grep_cword`       | search word under cursor                   |
| `grep_cWORD`       | search WORD under cursor                   |
| `grep_visual`      | search visual selection                    |
| `grep_curbuf`      | live grep current buffer                   |
| `live_grep`        | live grep current project                  |
| `live_grep_resume` | live grep continue last search             |


### Git
| Command          | List                                       |
| ---------------- | ------------------------------------------ |
| `git_files`        | `git ls-files`                               |
| `git_status`       | `git status`                                 |
| `git_commits`      | git commit log (project)                   |
| `git_bcommits`     | git commit log (buffer)                    |
| `git_branches`     | git branches                               |

### LSP
| Command          | List                                       |
| ---------------- | ------------------------------------------ |
| `lsp_references`             | References                       |
| `lsp_definitions`            | Definitions                      |
| `lsp_declarations`           | Declarations                     |
| `lsp_typedefs`               | Type Definitions                 |
| `lsp_implementations`        | Implementations                  |
| `lsp_document_symbols`       | Document Symbols                 |
| `lsp_workspace_symbols`      | Workspace Symbols                |
| `lsp_live_workspace_symbols` | Workspace Symbols (live query)   |
| `lsp_code_actions`           | Code Actions                     |
| `lsp_document_diagnostics`   | Document Diagnostics             |
| `lsp_workspace_diagnostics`  | Workspace Diagnostics            |

### Misc
| Command          | List                                       |
| ---------------- | ------------------------------------------ |
| `builtin`          | fzf-lua builtin commands                   |
| `help_tags`        | help tags                                  |
| `man_pages`        | man pages                                  |
| `colorschemes`     | color schemes                              |
| `commands`         | neovim commands                            |
| `command_history`  | command history                            |
| `search_history`   | search history                             |
| `marks`            | :marks                                     |
| `registers`        | :registers                                 |
| `keymaps`          | key mappings                               |
| `spell_suggest`    | spelling suggestions                       |
| `tags`             | project tags                               |
| `btags`            | buffer tags                                |
| `filetypes`        | neovim filetypes                           |
| `packadd`          | :packadd <package>                         |


## Customization

I tried to make it as customizable as possible, if you find you need to change something that isn’t below, open an issue and I’ll do my best to add it.

customization can be achieved by calling the `setup()` function or individually sending parameters to a builtin command, for exmaple:
```lua
:lua require('fzf-lua').files({ fzf_opts = {['--layout'] = 'reverse-list'} })
```

Consult the list below for available settings:
```lua
local actions = require "fzf-lua.actions"
require'fzf-lua'.setup {
  winopts = {
    -- split         = "belowright new",-- open in a split instead?
                                        -- "belowright new"  : split below
                                        -- "aboveleft new"   : split above
                                        -- "belowright vnew" : split right
                                        -- "aboveleft vnew   : split left
    -- Only valid when using a float window
    -- (i.e. when 'split' is not defined)
    height           = 0.85,            -- window height
    width            = 0.80,            -- window width
    row              = 0.35,            -- window row position (0=top, 1=bottom)
    col              = 0.50,            -- window col position (0=left, 1=right)
    -- border argument passthrough to nvim_open_win(), also used
    -- to manually draw the border characters around the preview
    -- window, can be set to 'false' to remove all borders or to
    -- 'none', 'single', 'double' or 'rounded' (default)
    border           = { '╭', '─', '╮', '│', '╯', '─', '╰', '│' },
    fullscreen       = false,           -- start fullscreen?
    hl = {
      normal         = 'Normal',        -- window normal color (fg+bg)
      border         = 'Normal',        -- border color (try 'FloatBorder')
      -- Only valid with the builtin previewer:
      cursor         = 'Cursor',        -- cursor highlight (grep/LSP matches)
      cursorline     = 'CursorLine',    -- cursor line
      -- title       = 'Normal',        -- preview border title (file/buffer)
      -- scrollbar_f = 'PmenuThumb',    -- scrollbar "full" section highlight
      -- scrollbar_e = 'PmenuSbar',     -- scrollbar "empty" section highlight
    },
    preview = {
      -- default     = 'bat',           -- override the default previewer?
                                        -- default uses the 'builtin' previewer
      border         = 'border',        -- border|noborder, applies only to
                                        -- native fzf previewers (bat/cat/git/etc)
      wrap           = 'nowrap',        -- wrap|nowrap
      hidden         = 'nohidden',      -- hidden|nohidden
      vertical       = 'down:45%',      -- up|down:size
      horizontal     = 'right:60%',     -- right|left:size
      layout         = 'flex',          -- horizontal|vertical|flex
      flip_columns   = 120,             -- #cols to switch to horizontal on flex
      -- Only valid with the builtin previewer:
      title          = true,            -- preview border title (file/buf)?
      scrollbar      = 'float',         -- `false` or string:'float|border'
                                        -- float:  in-window floating border 
                                        -- border: in-border chars (see below)
      scrolloff      = '-2',            -- float scrollbar offset from right
                                        -- applies only when scrollbar = 'float'
      scrollchars    = {'█', '' },      -- scrollbar chars ({ <full>, <empty> }
                                        -- applies only when scrollbar = 'border'
    },
    on_create = function()
      -- called once upon creation of the fzf main window
      -- can be used to add custom fzf-lua mappings, e.g:
      --   vim.api.nvim_buf_set_keymap(0, "t", "<C-j>", "<Down>",
      --     { silent = true, noremap = true })
    end,
  },
  keymap = {
    -- These override the default tables completely
    -- no need to set to `false` to disable a bind
    -- delete or modify is sufficient
    builtin = {
      -- neovim `:tmap` mappings for the fzf win
      ["<F2>"]        = "toggle-fullscreen",
      -- Only valid with the 'builtin' previewer
      ["<F3>"]        = "toggle-preview-wrap",
      ["<F4>"]        = "toggle-preview",
      -- Rotate preview clockwise/counter-clockwise
      ["<F5>"]        = "toggle-preview-ccw",
      ["<F6>"]        = "toggle-preview-cw",
      ["<S-down>"]    = "preview-page-down",
      ["<S-up>"]      = "preview-page-up",
      ["<S-left>"]    = "preview-page-reset",
    },
    fzf = {
      -- fzf '--bind=' options
      ["ctrl-z"]      = "abort",
      ["ctrl-u"]      = "unix-line-discard",
      ["ctrl-f"]      = "half-page-down",
      ["ctrl-b"]      = "half-page-up",
      ["ctrl-a"]      = "beginning-of-line",
      ["ctrl-e"]      = "end-of-line",
      ["alt-a"]       = "toggle-all",
      -- Only valid with fzf previewers (bat/cat/git/etc)
      ["f3"]          = "toggle-preview-wrap",
      ["f4"]          = "toggle-preview",
      ["shift-down"]  = "preview-page-down",
      ["shift-up"]    = "preview-page-up",
    },
  }
  -- use skim instead of fzf?
  -- https://github.com/lotabout/skim
  -- fzf_bin          = 'sk',
  fzf_opts = {
    -- options are sent as `<left>=<right>`
    -- set to `false` to remove a flag
    -- set to '' for a non-value flag
    -- for raw args use `fzf_args` instead
    ['--ansi']        = '',
    ['--prompt']      = ' >',
    ['--info']        = 'inline',
    ['--height']      = '100%',
    ['--layout']      = 'reverse',
  },
  -- fzf '--color=' options (optional)
  --[[ fzf_colors = {
      ["fg"] = { "fg", "CursorLine" },
      ["bg"] = { "bg", "Normal" },
      ["hl"] = { "fg", "Comment" },
      ["fg+"] = { "fg", "Normal" },
      ["bg+"] = { "bg", "CursorLine" },
      ["hl+"] = { "fg", "Statement" },
      ["info"] = { "fg", "PreProc" },
      ["prompt"] = { "fg", "Conditional" },
      ["pointer"] = { "fg", "Exception" },
      ["marker"] = { "fg", "Keyword" },
      ["spinner"] = { "fg", "Label" },
      ["header"] = { "fg", "Comment" },
      ["gutter"] = { "bg", "Normal" },
  }, ]]
  previewers = {
    cat = {
      cmd             = "cat",
      args            = "--number",
    },
    bat = {
      cmd             = "bat",
      args            = "--style=numbers,changes --color always",
      theme           = 'Coldark-Dark', -- bat preview theme (bat --list-themes)
      config          = nil,            -- nil uses $BAT_CONFIG_PATH
    },
    head = {
      cmd             = "head",
      args            = nil,
    },
    git_diff = {
      cmd             = "git diff",
      args            = "--color",
    },
    man = {
      cmd             = "man -c %s | col -b",
    },
    builtin = {
      delay           = 100,          -- delay(ms) displaying the preview
                                      -- prevents lag on fast scrolling
      syntax          = true,         -- preview syntax highlight?
      syntax_limit_l  = 0,            -- syntax limit (lines), 0=nolimit
      syntax_limit_b  = 1024*1024,    -- syntax limit (bytes), 0=nolimit
    },
  },
  -- provider setup
  files = {
    -- previewer         = "cat",       -- uncomment to override previewer
    prompt            = 'Files❯ ',
    cmd               = '',             -- "find . -type f -printf '%P\n'",
    git_icons         = true,           -- show git icons?
    file_icons        = true,           -- show file icons?
    color_icons       = true,           -- colorize file|git icons
    actions = {
      -- set bind to 'false' to disable
      ["default"]     = actions.file_edit,
      ["ctrl-s"]      = actions.file_split,
      ["ctrl-v"]      = actions.file_vsplit,
      ["ctrl-t"]      = actions.file_tabedit,
      ["alt-q"]       = actions.file_sel_to_qf,
      -- custom actions are available too
      ["ctrl-y"]      = function(selected) print(selected[1]) end,
    }
  },
  git = {
    files = {
      prompt          = 'GitFiles❯ ',
      cmd             = 'git ls-files --exclude-standard',
      git_icons       = true,           -- show git icons?
      file_icons      = true,           -- show file icons?
      color_icons     = true,           -- colorize file|git icons
    },
    status = {
      prompt        = 'GitStatus❯ ',
      cmd           = "git status -s",
      previewer     = "git_diff",
      file_icons    = true,
      git_icons     = true,
      color_icons   = true,
    },
    commits = {
      prompt          = 'Commits❯ ',
      cmd             = "git log --pretty=oneline --abbrev-commit --color",
      preview         = "git show --pretty='%Cred%H%n%Cblue%an%n%Cgreen%s' --color {1}",
      actions = {
        ["default"] = actions.git_checkout,
      },
    },
    bcommits = {
      prompt          = 'BCommits❯ ',
      cmd             = "git log --pretty=oneline --abbrev-commit --color",
      preview         = "git show --pretty='%Cred%H%n%Cblue%an%n%Cgreen%s' --color {1}",
      actions = {
        ["default"] = actions.git_buf_edit,
        ["ctrl-s"]  = actions.git_buf_split,
        ["ctrl-v"]  = actions.git_buf_vsplit,
        ["ctrl-t"]  = actions.git_buf_tabedit,
      },
    },
    branches = {
      prompt          = 'Branches❯ ',
      cmd             = "git branch --all --color",
      preview         = "git log --graph --pretty=oneline --abbrev-commit --color {1}",
      actions = {
        ["default"] = actions.git_switch,
      },
    },
    icons = {
      ["M"]           = { icon = "M", color = "yellow" },
      ["D"]           = { icon = "D", color = "red" },
      ["A"]           = { icon = "A", color = "green" },
      ["?"]           = { icon = "?", color = "magenta" },
      -- ["M"]          = { icon = "★", color = "red" },
      -- ["D"]          = { icon = "✗", color = "red" },
      -- ["A"]          = { icon = "+", color = "green" },
    },
  },
  grep = {
    prompt            = 'Rg❯ ',
    input_prompt      = 'Grep For❯ ',
    -- cmd               = "rg --vimgrep",
    rg_opts           = "--hidden --column --line-number --no-heading " ..
                        "--color=always --smart-case -g '!{.git,node_modules}/*'",
    git_icons         = true,           -- show git icons?
    file_icons        = true,           -- show file icons?
    color_icons       = true,           -- colorize file|git icons
    -- 'true' enables file and git icons in 'live_grep'
    -- degrades performance in large datasets, YMMV
    experimental      = false,
    -- live_grep_glob options
    glob_flag         = "--iglob",  -- for case sensitive globs use '--glob'
    glob_separator    = "%s%-%-"    -- query separator pattern (lua): ' --'
  },
  args = {
    prompt            = 'Args❯ ',
    files_only        = true,
    actions = {
      -- added on top of regular file actions
      ["ctrl-x"]      = actions.arg_del,
    }
  },
  oldfiles = {
    prompt            = 'History❯ ',
    cwd_only          = false,
  },
  buffers = {
    -- previewer      = false,        -- disable the builtin previewer?
    prompt            = 'Buffers❯ ',
    file_icons        = true,         -- show file icons?
    color_icons       = true,         -- colorize file|git icons
    sort_lastused     = true,         -- sort buffers() by last used
    actions = {
      ["default"]     = actions.buf_edit,
      ["ctrl-s"]      = actions.buf_split,
      ["ctrl-v"]      = actions.buf_vsplit,
      ["ctrl-t"]      = actions.buf_tabedit,
      ["ctrl-x"]      = actions.buf_del,
    }
  },
  blines = {
    previewer         = "builtin",    -- set to 'false' to disable
    prompt            = 'BLines❯ ',
    actions = {
      ["default"]     = actions.buf_edit,
      ["ctrl-s"]      = actions.buf_split,
      ["ctrl-v"]      = actions.buf_vsplit,
      ["ctrl-t"]      = actions.buf_tabedit,
    }
  },
  colorschemes = {
    prompt            = 'Colorschemes❯ ',
    live_preview      = true,       -- apply the colorscheme on preview?
    actions = {
      ["default"]     = actions.colorscheme,
      ["ctrl-y"]      = function(selected) print(selected[1]) end,
    },
    winopts = {
      height          = 0.55,
      width           = 0.30,
    },
    post_reset_cb     = function()
      -- reset statusline highlights after
      -- a live_preview of the colorscheme
      -- require('feline').reset_highlights()
    end,
  },
  quickfix = {
    -- cwd               = vim.loop.cwd(),
    file_icons        = true,
    git_icons         = true,
  },
  lsp = {
    prompt            = '❯ ',
    -- cwd               = vim.loop.cwd(),
    cwd_only          = false,      -- LSP/diagnostics for cwd only?
    async_or_timeout  = true,       -- timeout(ms) or false for blocking calls
    file_icons        = true,
    git_icons         = false,
    lsp_icons         = true,
    severity          = "hint",
    icons = {
      ["Error"]       = { icon = "", color = "red" },       -- error
      ["Warning"]     = { icon = "", color = "yellow" },    -- warning
      ["Information"] = { icon = "", color = "blue" },      -- info
      ["Hint"]        = { icon = "", color = "magenta" },   -- hint
    },
  },
  -- uncomment to disable the previewer
  -- nvim = { marks    = { previewer = { _ctor = false } } },
  -- helptags = { previewer = { _ctor = false } },
  -- manpages = { previewer = { _ctor = false } },
  -- uncomment to set dummy win location (help|man bar)
  -- "topleft"  : up
  -- "botright" : down
  -- helptags = { previewer = { split = "topleft" } },
  -- uncomment to use `man` command as native fzf previewer
  -- manpages = { previewer = { _ctor = require'fzf-lua.previewer'.fzf.man_pages } },
  -- optional override of file extension icon colors
  -- available colors (terminal):
  --    clear, bold, black, red, green, yellow
  --    blue, magenta, cyan, grey, dark_grey, white
  -- padding can help kitty term users with
  -- double-width icon rendering
  file_icon_padding = '',
  file_icon_colors = {
    ["lua"]   = "blue",
  },
}
```

This can also be run from a `.vim` file using:

```lua
lua << EOF
require('fzf-lua').setup{
-- ...
}
EOF
```

## Credits

Big thank you to all those I borrowed code/ideas from, I read so many configs
and plugin codes that I probably forgot where I found some samples from so if
I missed your name feel free to contact me and I'll add it below:

- [@vijaymarupudi](https://github.com/vijaymarupudi/) for his wonderful
  [nvim-fzf](https://github.com/vijaymarupudi/nvim-fzf) plugin which is in the
  core of this plugin
- [@tjdevries](https://github.com/tjdevries/) for too many great things to
  list here and for borrowing some of his
  [nvim-telescope](https://github.com/nvim-telescope/telescope.nvim) provider
  code
- [@lukas-reineke](https://github.com/lukas-reineke) for inspiring the
  solution after browsing his
  [dotfiles](https://github.com/lukas-reineke/dotfiles) and coming across his
  [fuzzy.lua](https://github.com/lukas-reineke/dotfiles/blob/master/vim/lua/fuzzy.lua)
  , and while we're, also here for his great lua plugin
  [indent-blankline](https://github.com/lukas-reineke/indent-blankline.nvim)
- [@sindrets](https://github.com/sindrets) for borrowing utilities from his
  fantastic lua plugin [diffview.nvim](https://github.com/sindrets/diffview.nvim)
- [@kevinhwang91](https://github.com/kevinhwang91) for using his previewer
  code as baseline for the builtin previewer and his must have plugin
  [nvim-bqf](https://github.com/kevinhwang91/nvim-bqf)
