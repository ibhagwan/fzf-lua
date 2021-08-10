<div align="center">

# fzf :heart: lua

![Neovim version](https://img.shields.io/badge/Neovim-0.5-57A143?style=flat-square&logo=neovim)

[Installation](#installation) • [Usage](#usage) • [Commands](#commands) • [Customization](#customization) • [Wiki](https://github.com/ibhagwan/fzf-lua/wiki)

![screenshot](https://raw.githubusercontent.com/ibhagwan/fzf-lua/main/screenshots/main.png)

[fzf](https://github.com/junegunn/fzf) changed my life, it can change yours too, if you allow it.

  </div>

### Rationale

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

### Why use this plug-in?

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

### Dependencies

- `Linux` or `MacOS` only, see [nvim-fzf's How it
  works](https://github.com/vijaymarupudi/nvim-fzf#How-it-works) section
- [`fzf`](https://github.com/junegunn/fzf) or
  [`skim`](https://github.com/lotabout/skim) binary installed
- [nvim-fzf](https://github.com/vijaymarupudi/nvim-fzf)
- [nvim-web-devicons](https://github.com/kyazdani42/nvim-web-devicons)
  (optional)

### Optional dependencies (recommended)

- [fd](https://github.com/sharkdp/fd) - better performance `find` utility
- [bat](https://github.com/sharkdp/bat) - for colorful syntax highlighted previews
- [ripgrep](https://github.com/BurntSushi/ripgrep) - for better grep-like searches

### Installation

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

## Commands

| Command | List |
| --- | --- |
|`buffers`|open buffers|
|`files`|`find` or `fd` on a path|
|`oldfiles`|opened files history|
|`quickfix`|quickfix list|
|`loclist`|location list|
|`grep`|search for a pattern with `grep` or `rg`|
|`grep_last`|run search again with the last pattern|
|`grep_cword`|search word under cursor|
|`grep_cWORD`|search WORD under cursor|
|`grep_visual`|search visual selection|
|`grep_curbuf`|live grep current buffer|
|`live_grep`|live grep current project|
|`help_tags`|help tags|
|`man_pages`|man pages|
|`colorschemes`|color schemes|
|`builtin`|fzf-lua builtin methods|
|`git_files`|`git ls-files`|
|`git_status`|`git status`|
|`git_commits`|git commit log (project)|
|`git_bcommits`|git commit log (buffer)|
|`git_branch`|git branches|

## LSP Commands

| Command | List |
| --- | --- |
|`lsp_references`|References|
|`lsp_definitions`|Definitions|
|`lsp_declarations`|Declarations|
|`lsp_typedefs`|Type Definitions|
|`lsp_implementations`|Implementations|
|`lsp_document_symbols`|Document Symbols|
|`lsp_workspace_symbols`|Workspace Symbols|
|`lsp_code_actions`|Code Actions|
|`lsp_document_diagnostics`|Document Diagnostics|
|`lsp_workspace_diagnostics`|Workspace Diagnostics|

## Customization

I tried to make it as customizable as possible, if you find you need to change something that isn’t below, open an issue and I’ll do my best to add it.

customization can be achieved by calling the `setup()` function or individually sending parameters to a builtin command, for exmaple:
```lua
:lua require('fzf-lua').files({ fzf_layout = 'reverse-list' })
```

Consult the list below for available settings:
```lua
local actions = require "fzf-lua.actions"
require'fzf-lua'.setup {
  winopts = {
    -- split         = "new",           -- open in a split instead?
    win_height       = 0.85,            -- window height
    win_width        = 0.80,            -- window width
    win_row          = 0.30,            -- window row position (0=top, 1=bottom)
    win_col          = 0.50,            -- window col position (0=left, 1=right)
    -- win_border    = false,           -- window border? or borderchars?
    win_border       = { '╭', '─', '╮', '│', '╯', '─', '╰', '│' },
    window_on_create = function()         -- nvim window options override
      vim.cmd("set winhl=Normal:Normal")  -- popup bg match normal windows
    end,
  },
  -- fzf_bin             = 'sk',        -- use skim instead of fzf?
  fzf_layout          = 'reverse',      -- fzf '--layout='
  fzf_args            = '',             -- adv: fzf extra args, empty unless adv
  fzf_binds           = {               -- fzf '--bind=' options
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
  preview_border      = 'border',       -- border|noborder
  preview_wrap        = 'nowrap',       -- wrap|nowrap
  preview_opts        = 'nohidden',     -- hidden|nohidden
  preview_vertical    = 'down:45%',     -- up|down:size
  preview_horizontal  = 'right:60%',    -- right|left:size
  preview_layout      = 'flex',         -- horizontal|vertical|flex
  flip_columns        = 120,            -- #cols to switch to horizontal on flex
  -- default_previewer   = "bat",       -- override the default previewer?
                                        -- by default auto-detect bat|cat
  previewers = {
    cmd = {
      -- custom previewer, will execute:
      -- `<cmd> <args> <filename>`
      cmd             = "echo",
      args            = "",
    },
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
      ["default"]     = actions.file_edit,
      ["ctrl-s"]      = actions.file_split,
      ["ctrl-v"]      = actions.file_vsplit,
      ["ctrl-t"]      = actions.file_tabedit,
      ["ctrl-q"]      = actions.file_sel_to_qf,
      ["ctrl-y"]      = function(selected) print(selected[2]) end,
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
        ["default"] = nil,
      },
    },
    bcommits = {
      prompt          = 'BCommits❯ ',
      cmd             = "git log --pretty=oneline --abbrev-commit --color --",
      preview         = "git show --pretty='%Cred%H%n%Cblue%an%n%Cgreen%s' --color {1}",
      actions = {
        ["default"] = nil,
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
    actions = {
      ["default"]     = actions.file_edit,
      ["ctrl-s"]      = actions.file_split,
      ["ctrl-v"]      = actions.file_vsplit,
      ["ctrl-t"]      = actions.file_tabedit,
      ["ctrl-q"]      = actions.file_sel_to_qf,
      ["ctrl-y"]      = function(selected) print(selected[2]) end,
    }
  },
  oldfiles = {
    prompt            = 'History❯ ',
    cwd_only          = false,
  },
  buffers = {
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
  colorschemes = {
    prompt            = 'Colorschemes❯ ',
    live_preview      = true,       -- apply the colorscheme on preview?
    actions = {
      ["default"]     = actions.colorscheme,
      ["ctrl-y"]      = function(selected) print(selected[2]) end,
    },
    winopts = {
      win_height        = 0.55,
      win_width         = 0.30,
      window_on_create  = function()
        vim.cmd("set winhl=Normal:Normal")
      end,
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
  -- placeholders for additional user customizations
  loclist = {},
  helptags = {},
  manpages = {},
  -- optional override of file extension icon colors
  -- available colors (terminal):
  --    clear, bold, black, red, green, yellow
  --    blue, magenta, cyan, grey, dark_grey, white
  file_icon_colors = {
    ["lua"]   = "blue",
  },
}
```

This can also be run from a `.vim` file using

```lua
lua << EOF
require('fzf-lua').setup{
-- ...
}
EOF
```

### Known issues

- [ ] `live_grep` has icons disabled until I find a solution for fzf's
  `change:reload` event
- [ ] Tested mostly with both `rg`, `fd` and `bat` installed, there might be
  issues with the default `grep`, `find` and `head` alternatives

## TODO

- Add more providers
    + [x] ~~LSP (refs, symbols, etc)~~ (2021-07-20)
    + [x] ~~git commits~~ (2021-08-05)
    + [x] ~~git branches~~ (2021-08-05)
    + [ ] vim commands
    + [ ] vim command history
    + [ ] vim keymaps
    + [ ] vim options
    + [ ] search history
    + [ ] tags
    + [ ] marks
    + [ ] registers
    + [ ] spelling suggestions
- [ ] Add built-in plugin documentation
- [ ] Add "hidden" options documentation
- [ ] Add FAQ

### Credits

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
