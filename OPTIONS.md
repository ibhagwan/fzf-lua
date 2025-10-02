# NOTE: THIS DOCUMENT IS CURRENTLY WIP

**This document does not yet contain all of fzf-lua's options, there are a lot of esoteric and
undocumented options which can be found in issues/discussions which I will slowly but surely
add to this document.**

---

# Fzf-Lua Commands and Options

- [General Usage](#general-usage)
- [Setup Options](#setup-options)
- [Global Options](#global-options)
- [Pickers](#pickers)
  + [Buffers and Files](#buffers-and-files)
  + [Search](#search)
  + [CTags](#ctags)
  + [Git](#git)
  + [LSP | Diagnostics](#lspdiagnostics)
  + [Misc](#misc)
  + [Neovim API](#neovim-api)
  + [`nvim-dap`](#nvim-dap)
  + [`tmux`](#tmux)
  + [Completion Functions](#completion-functions)

---

## General Usage

Options in fzf-lua can be specified in a few different ways:
- Global setup options
- Provider-defaults setup options
- Provider-specific setup options
- Command call options

Most of fzf-lua's options are applicable in all of the above, a few examples below:

Global setup, applies to all fzf-lua interfaces:
```lua
-- Places the floating window at the bottom left corner
require("fzf-lua").setup({ winopts = { row = 1, col = 0 } })
```

Disable `file_icons` globally (files, grep, etc) via provider defaults setup options:
```lua
require("fzf-lua").setup({ defaults = { file_icons = false } })
```

Disable `file_icons` in `files` only via provider specific setup options:
```lua
require("fzf-lua").setup({ files = { file_icons = false } })
```

Disable `file_icons` in `files`, applies to this call only:
```lua
:lua require("fzf-lua").files({ file_icons = false  })
-- Or
:FzfLua files file_icons=false
```

Fzf-lua conveniently enables setting lua tables recursively using dotted keys, for example, if we
wanted to call `files` in "split" mode (instead of the default floating window), we would normally call:

```lua
:lua require("fzf-lua").files({ winopts = { split = "belowright new" } })
```

But we can also use the dotted key format (unique to fzf-lua):
```lua
:lua require("fzf-lua").files({ ["winopts.split"] = "belowright new" })
```

This makes it possible to send nested lua values via the `:FzfLua` user command:
```lua
-- Escape spaces with \
:FzfLua files winopts.split=belowright\ new
```

Lua string serialization is also possible:
```lua
-- Places the floating window at the top left corner
:FzfLua files winopts={row=0,col=0}
```

---

## Setup Options

Most of fzf-lua's options are global, meaning they can be specified in any of the different ways
explained in [General Usage](#general-usage) and are described in detail in the [Global Options](#global-options) section below.

There are however a few options that can be specified only during the call to `setup`, these are
described below.

#### setup.nbsp

Type: `string`, Default: `nil`

Fzf-lua uses a special invisible unicode character `EN SPACE` (U+2002) as text delimiter.

It is not recommended to modify this value as this can have uninteded consequnces when entries contain the character designated as `nbsp`, but if your terminal/font does not support `EN_SPACE` you can use `NBSP` (U+00A0) instead:
```lua
require("fzf-lua").setup({ nbsp = "\xc2\xa0" })
```

#### setup.winopts.preview.default

Type: `string|function|object`, Default: `builtin`

Default previewer for file pickers, possible values `builtin|bat|cat|head`, for example:

```lua
require("fzf-lua").setup({ winopts = { preview = { default = "bat" } } })
```

If set to a `function` the return value will be used (`string|object`).

If set to an `object`, fzf-lua expects a previewer class that will be initlaized with `object:new(...)`, see the advanced Wiki "Neovim builtin previewer" section for more info.

#### setup.help_open_win

Type: `fun(number, boolean, table)`,  Default: `vim.api.nvim_open_win`

Function override for opening the help window (default bound to `<F1>`), will be called with the same arguments as `nvim_open_win(bufnr, enter, winopts)`. By default opens a floating window at the bottom of current screen.

Override this function if you want to customize window configs of the help window (location, width, border, etc.).

Example, opening a floating help window at the top of screen with single border:
```lua
    require("fzf-lua").setup({
      help_open_win = function(buf, enter, opts)
        opts.border = 'single'
        opts.row = 0
        opts.col = 0
        return vim.api.nvim_open_win(buf, enter, opts)
      end,
    })
```

---

## Global Options

Globals are options that aren't picker-specific and can be used with all fzf-lua commands, for
example, positioning the floating window at the bottom line using `globals.winopts.row`:

> The `globals` prefix denotates the scope of the option and is therefore omitted 

Using `FzfLua` user command:
```lua
:FzfLua files winopts.row=1
```

Using Lua:
```lua
:lua require("fzf-lua").files({ winopts = { row = 1 } })
-- Using the recursive option format
:lua require("fzf-lua").files({ ["winopts.row"] = 1 })
```

#### globals.cwd

Type: `string`, Default: `nil`

Sets the current working directory.

#### globals.query

Type: `string`, Default: `nil`

Initial query (prompt text), passed to fzf as `--query` flag.

#### globals.prompt

Type: `string`, Default: `nil`

Fzf prompt, passed to fzf as `--prompt` flag.

#### globals.header

Type: `string|false`, Default: `nil`

Header line, set to any string to display a header line, set to `false` to disable fzf-lua
interactive headers (e.g. "ctrl-g to disable .gitignore", etc), passed to fzf as `--header` flag.

#### globals.previewer

Type: `string`, Default: `nil`

Previewer override, set to `false` to disable the previewer.

By default files pickers use the "builtin" previewer, possible values for file pickers `bat|cat|head`.

Other overrides include:
```lua
:FzfLua helptags previewer=help_native
:FzfLua manpages previewer=man_native
```

#### globals.formatter

Type: `string`, Default: `nil`

Custom path formatter, can be defined under `setup.formatters`, fzf-lua comes with a builtin vscode-like formatter, displaying the filename first followed by the folder.

Try it out with:
```lua
:FzfLua files formatter=path.filename_first
:FzfLua live_grep formatter=path.filename_first
```

Or via `setup` for permanency:
```lua
require("fzf-lua").setup({ files = { formatter = "path.filename_first" } })
```

#### globals.file_icons

Type: `boolean|string`, Default: `true`

If available, display file icons.

Set to `true` will attempt to use "nvim-web-devicons" and fallback to "mini.icons", other possible
values are `devicons` or `mini` which force loading a specific icons plugin, for example:

```lua
:FzfLua files file_icons=mini
:lua require("fzf-lua").files({ file_icons = "devicons"  })
```

#### globals.git_icons

Type: `boolean`, Default: `true`

If inside a git-repo add git status indicator icons e.g. `M` for modified files.

#### globals.color_icons

Type: `boolean`, Default: `true`

Add coloring of file|git icons.

#### globals.winopts.split

Type: `string`, Default: `nil`

Neovim split command to use for fzf-lua interface, e.g `belowright new`.

#### globals.winopts.col

Type: `number`, Default: `0.55`

Screen column where to place the fzf-lua float window, between 0-1 will represent percentage of `vim.o.columns` (0: leftmost, 1: rightmost), if >= 1 will attempt to place the float in the exact screen column.

#### globals.winopts.row

Type: `number`, Default: `0.35`

Screen row where to place the fzf-lua float window, between 0-1 will represent percentage of `vim.o.lines` (0: top, 1: bottom), if >= 1 will attempt to place the float in the exact screen line.

#### globals.winopts.width

Type: `number`, Default: `0.80`

Width of the fzf-lua float, between 0-1 will represent percentage of `vim.o.columns` (1: max width), if >= 1 will use fixed number of columns.

#### globals.winopts.height

Type: `number`, Default: `0.85`

Height of the fzf-lua float, between 0-1 will represent percentage of `vim.o.lines` (1: max height), if >= 1 will use fixed number of lines.

#### globals.winopts.border

Type: `string|table`, Default: `rounded`

Border of the fzf-lua float, possible values are `none|single|double|rounded|thicc|thiccc|thicccc`
or a custom border character array passed as is to `nvim_open_win`.

#### globals.winopts.backdrop

Type: `boolean|number`, Default: `60`

Backdrop opacity value, 0 for fully opaque, 100 for fully transparent (i.e. disabled).

#### globals.winopts.fullscreen

Type: `boolean`, Default: `false`

Use fullscreen for the fzf-load floating window.

#### globals.winopts.title

Type: `string`, Default: `nil`

Controls title display in the fzf window, set by the calling picker.

#### globals.winopts.title_pos

Type: `string`, Default: `center`

Controls title display in the fzf window, possible values are `left|right|center`.

#### globals.winopts.title_flags

Type: `boolean`, Default: `nil`

Set to `false` to disable fzf window title flags (hidden, ignore, etc).

#### globals.winopts.treesitter

Type: `boolean`, Default: `false`

Use treesitter highlighting in fzf's main window.

> **NOTE**: Only works for file-like entires where treesitter parser exists and is loaded
> for the filetype.

#### globals.winopts.on_create

Type: `function`, Default: `nil`

Callback after the creation of the fzf-lua main terminal window.

#### globals.winopts.preview.delay

Type: `number`, Default: `20`

Debounce time (milliseconds) for displaying the preview buffer in the builtin previewer.

#### globals.winopts.preview.wrap

Type: `boolean`, Default: `false`

Line wrap in both native fzf and the builtin previewer, mapped to fzf's `--preview-window:[no]wrap` flag.

#### globals.winopts.preview.hidden

Type: `boolean`, Default: `false`

Preview startup visibility in both native fzf and the builtin previewer, mapped to fzf's `--preview-window:[no]hidden` flag.

> **NOTE**: this is different than setting `previewer=false` which disables the previewer
> altogether with no toggle ability.

#### globals.winopts.preview.border

Type: `string`, Default: `border`

Preview border for native fzf previewers (i.e. `bat`, `git_status`), set to `noborder` to hide the preview border, consult `man fzf` for all available options.

#### globals.winopts.preview.layout

Type: `string`, Default: `flex`

Preview layout, possible values are `horizontal|vertical|flex`, when set to `flex` fzf window
width is tested against `winopts.preview.flip_columns`, when <= `vertical` is used, otherwise
`horizontal`.

#### globals.winopts.preview.flip_columns

Type: `number`, Default: `100`

Auto-detect the preview layout based on available width, see above note in `winopts.preview.layout`.

#### globals.winopts.preview.horizontal

Type: `string`, Default: `right:60%`

Horizontal preview layout, mapped to fzf's `--preview-window:...` flag.

<sub><sup>*Requires `winopts.preview.layout={horizontal|flex}`</sup></sub>

#### globals.winopts.preview.vertical

Type: `string`, Default: `down:45%`

Vertical preview layout, mapped to fzf's `--preview-window:...` flag.

<sub><sup>*Requires `winopts.preview.layout={vertical|flex}`</sup></sub>

#### globals.winopts.preview.title

Type: `boolean`, Default: `true`

Controls title display in the builtin previewer.

#### globals.winopts.preview.title_pos

Type: `string`, Default: `center`

Controls title display in the builtin previewer, possible values are `left|right|center`.

#### globals.winopts.preview.scrollbar

Type: `string|boolean`, Default: `float`

Scrollbar style in the builtin previewer, set to `false` to disable, possible values are
`float|border`.

#### globals.winopts.preview.scrolloff

Type: `number`, Default: `-1`

Float style scrollbar offset from the right edge of the preview window.

<sub><sup>*Requires `winopts.preview.scrollbar=float`</sup></sub>

#### globals.winopts.preview.winopts.number

Type: `boolean`, Default: `true`

Builtin previewer buffer local option, see `:help 'number'`.

#### globals.winopts.preview.winopts.relativenumber

Type: `boolean`, Default: `false`

Builtin previewer buffer local option, see `:help 'relativenumber'`.

#### globals.winopts.preview.winopts.cursorline

Type: `boolean`, Default: `true`

Builtin previewer buffer local option, see `:help 'cursorline'`.

#### globals.winopts.preview.winopts.cursorcolumn

Type: `boolean`, Default: `false`

Builtin previewer buffer local option, see `:help 'cursorcolumn'`.

#### globals.winopts.preview.winopts.cursorlineopt

Type: `string`, Default: `both`

Builtin previewer buffer local option, see `:help 'cursorlineopt'`.

#### globals.winopts.preview.winopts.signcolumn

Type: `string`, Default: `no`

Builtin previewer buffer local option, see `:help 'signcolumn'`.

#### globals.winopts.preview.winopts.list

Type: `boolean`, Default: `false`

Builtin previewer buffer local option, see `:help 'list'`.

#### globals.winopts.preview.winopts.foldenable

Type: `boolean`, Default: `false`

Builtin previewer buffer local option, see `:help 'foldenable'`.

#### globals.winopts.preview.winopts.foldmethod

Type: `string`, Default: `manual`

Builtin previewer buffer local option, see `:help 'foldmethod'`.

#### globals.winopts.preview.winopts.scrolloff

Type: `number`, Default: `1`

Builtin previewer buffer local option, see `:help 'scrolloff'`.

#### globals.hls.normal

Type: `string`, Default: `FzfLuaNormal`

Main fzf (terminal) window normal (text/bg) highlight group.

#### globals.hls.border

Type: `string`, Default: `FzfLuaBorder`

Main fzf (terminal) window border highlight group.

#### globals.hls.title

Type: `string`, Default: `FzfLuaTitle`

Main fzf (terminal) window title highlight group.

#### globals.hls.title_flags

Type: `string`, Default: `CursorLine`

Main fzf (terminal) window title flags highlight group (hidden, etc).

#### globals.hls.backdrop

Type: `string`, Default: `FzfLuaBackdrop`

Backdrop color, black by default, used to darken the background color when opening the UI.

#### globals.hls.preview_normal

Type: `string`, Default: `FzfLuaPreviewNormal`

Builtin previewer window normal (text/bg) highlight group.

#### globals.hls.preview_border

Type: `string`, Default: `FzfLuaPreviewBorder`

Builtin previewer window border highlight group.

#### globals.hls.preview_title

Type: `string`, Default: `FzfLuaPreviewTitle`

Builtin previewer window title highlight group.

#### globals.hls.cursor

Type: `string`, Default: `FzfLuaCursor`

Builtin previewer window `Cursor` highlight group.

#### globals.hls.cursorline

Type: `string`, Default: `FzfLuaCursorLine`

Builtin previewer window `CursorLine` highlight group.

#### globals.hls.cursorlinenr

Type: `string`, Default: `FzfLuaCursorLineNr`

Builtin previewer window `CursorLineNr` highlight group.

#### globals.hls.search

Type: `string`, Default: `FzfLuaSearch`

Builtin previewer window search matches highlight group.

#### globals.hls.scrollborder_e

Type: `string`, Default: `FzfLuaScrollBorderEmpty`

Builtin previewer window `border` scrollbar empty highlight group.

#### globals.hls.scrollborder_f

Type: `string`, Default: `FzfLuaScrollBorderFull`

Builtin previewer window `border` scrollbar full highlight group.

#### globals.hls.scrollfloat_e

Type: `string`, Default: `FzfLuaScrollFloatEmpty`

Builtin previewer window `float` scrollbar empty highlight group.

#### globals.hls.scrollfloat_f

Type: `string`, Default: `FzfLuaScrollFloatFull`

Builtin previewer window `float` scrollbar full highlight group.

#### globals.hls.help_normal

Type: `string`, Default: `FzfLuaHelpNormal`

Help window (F1) normal (text/bg) highlight group.

#### globals.hls.help_border

Type: `string`, Default: `FzfLuaHelpBorder`

Help window (F1) border highlight group.

#### globals.hls.header_bind

Type: `string`, Default: `FzfLuaHeaderBind`

Interactive headers keybind highlight group, e.g. `<ctrl-g> to Disable .gitignore`.

#### globals.hls.header_text

Type: `string`, Default: `FzfLuaHeaderText`

Interactive headers description highlight group, e.g. `<ctrl-g> to Disable .gitignore`.

#### globals.hls.path_linenr

Type: `string`, Default: `FzfLuaPathLineNr`

Highlight group for the line part of paths, e.g. `file:<line>:<col>:`, used in pickers such as `buffers`, `quickfix`, `lsp`, `diagnostics`, etc.

#### globals.hls.path_colnr

Type: `string`, Default: `FzfLuaPathColNr`

Highlight group for the column part of paths, e.g. `file:<line>:<col>:`, used in pickers such as `buffers`, `quickfix`, `lsp`, `diagnostics`, etc.

#### globals.hls.buf_name

Type: `string`, Default: `FzfLuaBufName`

Highlight group for buffer name (filepath) in `lines`.

#### globals.hls.buf_id

Type: `string`, Default: `FzfLuaBufId`

Highlight group for buffer id (number) in `lines`.

#### globals.hls.buf_nr

Type: `string`, Default: `FzfLuaBufNr`

Highlight group for buffer number in `buffers`, `tabs`.

#### globals.hls.buf_linenr

Type: `string`, Default: `FzfLuaBufLineNr`

Highlight group for buffer line number in `lines`, `blines` and `treesitter`.

#### globals.hls.buf_flag_cur

Type: `string`, Default: `FzfLuaBufFlagCur`

Highlight group for the current buffer flag in `buffers`, `tabs`.

#### globals.hls.buf_flag_alt

Type: `string`, Default: `FzfLuaBufFlagAlt`

Highlight group for the alternate buffer flag in `buffers`, `tabs`.

#### globals.hls.tab_title

Type: `string`, Default: `FzfLuaTabTitle`

Highlight group for the tab title in `tabs`.

#### globals.hls.tab_marker

Type: `string`, Default: `FzfLuaTabMarker`

Highlight group for the current tab marker in `tabs`.

#### globals.hls.dir_icon

Type: `string`, Default: `FzfLuaDirIcon`

Highlight group for the directory icon in paths that end with a separator, usually used in path
completion, e.g. `complete_path`.

#### globals.hls.dir_part

Type: `string`, Default: `FzfLuaDirPart`

Highlight group for the directory part when using `path.dirname_first` or `path.filename_first` formatters.

#### globals.hls.file_part

Type: `string`, Default: `FzfLuaFilePart`

Highlight group for the directory part when using `path.dirname_first` or `path.filename_first` formatters.

#### globals.hls.live_prompt

Type: `string`, Default: `FzfLuaLivePrompt`

Highlight group for the prompt text in "live" pickers.

#### globals.hls.live_sym

Type: `string`, Default: `FzfLuaLiveSym`

Highlight group for the matched characters in `lsp_live_workspace_symbols`.

#### globals.hls.cmd_global

Type: `string`, Default: `FzfLuaCmdGlobal`

Highlight group for global commands in `:FzfLua commands`, by default links to `Directory`.

#### globals.hls.cmd_buf

Type: `string`, Default: `FzfLuaCmdBuf`

Highlight group for buffer commands in `:FzfLua commands`, by default links to `Added`.

#### globals.hls.cmd_ex

Type: `string`, Default: `FzfLuaCmdEx`

Highlight group for ex commands in `:FzfLua commands`, by default links to `Statement`.

#### globals.hls.fzf.normal

Type: `string`, Default: `FzfLuaFzfNormal`

Highlight group for fzf's `fg` and `bg`, by default links to `FzfLuaNormal`.

#### globals.hls.fzf.cursorline

Type: `string`, Default: `FzfLuaFzfCursorLine`

Highlight group for fzf's `fg+` and `bg+`, by default links to `FzfLuaCursorLine`.

#### globals.hls.fzf.match

Type: `string`, Default: `FzfLuaFzfMatch`

Highlight group for fzf's `hl+`, by default links to `Special`.

#### globals.hls.fzf.border

Type: `string`, Default: `FzfLuaFzfBorder`

Highlight group for fzf's `border`, by default links to `FzfLuaBorder`.

#### globals.hls.fzf.scrollbar

Type: `string`, Default: `FzfLuaFzfScrollbar`

Highlight group for fzf's `border`, by default links to `FzfLuaFzfBorder`.

#### globals.hls.fzf.separator

Type: `string`, Default: `FzfLuaFzfSeparator`

Highlight group for fzf's `separator`, by default links to `FzfLuaFzfBorder`.

#### globals.hls.fzf.gutter

Type: `string`, Default: `FzfLuaFzfGutter`

Highlight group for fzf's `gutter`, by default links to `FzfLuaFzfBorder`.

> **NOTE**: `bg` property of the highlight group will be used.

#### globals.hls.fzf.header

Type: `string`, Default: `FzfLuaFzfHeader`

Highlight group for fzf's `header`, by default links to `FzfLuaTitle`.

#### globals.hls.fzf.info

Type: `string`, Default: `FzfLuaFzfInfo`

Highlight group for fzf's `info`, by default links to `NonText`.

#### globals.hls.fzf.pointer

Type: `string`, Default: `FzfLuaFzfPointer`

Highlight group for fzf's `pointer`, by default links to `Special`.

#### globals.hls.fzf.marker

Type: `string`, Default: `FzfLuaFzfMarker`

Highlight group for fzf's `marker`, by default links to `FzfLuaFzfPointer`.

#### globals.hls.fzf.spinner

Type: `string`, Default: `FzfLuaFzfSpinner`

Highlight group for fzf's `spinner`, by default links to `FzfLuaFzfPointer`.

#### globals.hls.fzf.prompt

Type: `string`, Default: `FzfLuaFzfPrompt`

Highlight group for fzf's `prompt`, by default links to `Special`.

#### globals.hls.fzf.query

Type: `string`, Default: `FzfLuaFzfQuery`

Highlight group for fzf's `query`, by default links to `FzfLuaNormal` and
sets text to `regular` (non-bold).

---

## Pickers

### Buffers and Files

#### buffers

Open buffers

#### tabs

Open buffers in tabs

#### oldfiles

File history (output of `:oldfiles`)

#### quickfix

Quickfix list (output of `:copen`)

#### quickfix_stack

Quickfix list history (output of `:chistory`)

#### loclist

Location list (output of `:lopen`)

#### loclist_stack

Location list history (output of `:lhistory`)

#### treesitter

Current buffer treesitter symbols

#### blines

Current buffer lines

#### lines

Open buffers lines

#### args

Neovim's argument list (output of `:args`)

##### args.files_only

Type: `boolean`, Default: `true`

Exclude non-file entries (directories).

#### files

Files finder, will enumerate the filesystem of the current working directory using `fd`, `rg` and `grep` or `dir.exe`.

##### files.cwd_prompt

Type: `boolean`, Default: `true`

Display the current working directory in the prompt (`fzf.vim` style).

##### files.cwd_prompt_shorten_len

Type: `number`, Default: `32`

Prompt over this length will be shortened, e.g.  `~/.config/nvim/lua/` will be shortened to `~/.c/n/lua/` (for more info see `:help pathshorten`).

<sub><sup>*Requires `cwd_prompt=true`</sup></sub>

##### files.cwd_prompt_shorten_val

Type: `number`, Default: `1`

Length of shortened prompt path parts, e.g. set to `2`, `~/.config/nvim/lua/` will be shortened to `~/.co/nv/lua/` (for more info see `:help pathshorten`).

<sub><sup>*Requires `cwd_prompt=true`</sup></sub>

---

### Search

#### grep

Search for strings/regexes using `rg`, `grep` or any other compatible grep'er binary (e.g. `ag`).

Unless `search=...` is specified will prompt for the search string.

##### grep.search_paths

Type: `[string]`, Default: `nil`

list of paths to be grep'd, for example:

```lua
-- Using the vimL command
:FzfLua live_grep search_paths=/path/to/search
-- multiple paths using the lua command
:lua FzfLua.grep({ search_paths = { "/path1", "path2" } })
```


#### live_grep

Search for strings/regexes using `rg`, `grep` or any other compatible grep'er binary (e.g. `ag`).

Unlike `grep` which uses a fixed search string/regex each keypress generates a new underlying grep command with the prompt input text, this can be more performant on large monorepos to narrow down the result set before switching to fuzzy matching with `ctrl-g` for further refinement.

#### live_grep_native

Performant "live" grep variant piping the underlying command directly to fzf (without any processing by fzf-lua), disables all the bells and whistles (icons, path manipulation, etc).

#### live_grep_glob

"Live" grep variant with add support for `rg --iglob` flag, use the default separator `--` to specify globs, for example, `pcall -- *.lua !*spec*` will search for `pcall` in any lua file that doesn't contain `spec`.

#### live_grep_resume

Alias to `:FzfLua live_grep resume=true`

#### grep_project

Alias to `:FzfLua grep search=""`, feeds all lines of the project into fzf for fuzzy matching.

**NOTE**: on large monorepos feeding all lines of the project into fzf isn't very efficient, consider using `live_grep` first with a regex to narrow down the result set and then switch to fuzzy finding for further refinement by pressing `ctrl-g`.

#### grep_last

Alias to `:FzfLua grep resume=true`

#### grep_cword

Grep word/WORD under cursor

#### grep_visual

Grep visual selection

#### grep_curbuf

Grep on current buffer only

#### lgrep_curbuf

"Live" grep on current buffer only

#### grep_quickfix

Grep the quickfix list

#### lgrep_quickfix

"Live" grep the quickfix list

#### grep_loclist

Grep the location list

#### lgrep_loclist

"Live" grep the location list

---

### CTags

#### tags

Search project ctags

#### btags

Search current buffer ctags

#### tags_grep

"Grep" for tags, see `grep` for more info.

#### tags_live_grep

"Live-Grep" for tags, see `live_grep` for more info.

#### tags_grep_cword

Tags-Grep word/WORD under cursor

#### tags_grep_visual

Tags-Grep visual selection

---

### Git

#### git_files

Git files

#### git_status

Git status

#### git_diff

Git diff (files) for any ref

#### git_hunks

Git diff (hunks) for any ref

#### git_commits

Git commits (project)

#### git_bcommits

Git commits (buffer)

#### git_blame

Git blame (buffer)

#### git_branches

Git branches

#### git_worktrees

Git worktrees

#### git_tags

Git tags

#### git_stash

Git stashes

---

### LSP/Diagnostics

#### lsp_references

LSP references

#### lsp_definitions

LSP Definitions

#### lsp_declarations

LSP Declarations

#### lsp_typedefs

LSP Type Definitions

#### lsp_implementations

LSP Implementations

#### lsp_document_symbols

LSP Document Symbols

#### lsp_workspace_symbols

LSP Workspace Symbols

#### lsp_live_workspace_symbols

LSP Workspace Symbols "live" query

#### lsp_incoming_calls

LSP Incoming Calls

#### lsp_outgoing_calls

LSP Outgoing Calls

#### lsp_code_actions

LSP Code Actions

#### lsp_finder

All LSP locations, combined view

#### lsp_document_diagnostics

Document Diagnostics (alias to `diagnostics_document`)

#### lsp_workspace_diagnostics

Workspace Diagnostics (alias to `diagnostics_workspace`)

#### diagnostics_document

Document Diagnostics

#### diagnostics_workspace

Workspace Diagnostics

##### lsp.async_or_timeout

Type: `number|boolean`, Default: `5000`

Whether LSP calls are made block, set to `true` for asynchronous, otherwise defines the timeout
(ms) for the LPS request via `vim.lsp.buf_request_sync`.
 
---

### Misc

#### resume

Resume last command/query

#### builtin

fzf-lua builtin commands

#### profiles

Fzf-lua configuration profiles

#### helptags

Search Helptags

#### manpages

Search man pages

#### colorschemes

Installed colorschemes

#### awesome_colorschemes

"Awesome Neovim" colorschemes

#### highlights

Neovim's highlight groups

#### commands

Neovim commands

#### command_history

Executed command history

#### search_history

Search history

#### marks

Search `:marks`

#### jumps

Search `:jumps`

#### changes

Search `:changes`

#### registers

Search `:registers`

#### tagstack

Search `:tags`

#### autocmds

Neovim's autocmds

#### keymaps

Neovims key mappings

#### nvim_options

Neovim's options

#### filetypes

Filetypes

#### menus

Neovim's menus

#### spellcheck

Misspelled words in buffer

#### spell_suggest

Spelling suggestions

#### packadd

`:packadd <package>`

#### setup_highlights

Setup/Reset fzf-lua highlight groups.

#### setup_fzfvim_cmds

Setup `fzf.vim` user commands mapped to their fzf-lua equivalents (e.g. `:Files`, `:Rg`, etc).


---

### Neovim API

#### register_ui_select

Register fzf-lua as the UI interface for `vim.ui.select`

#### deregister_ui_select

De-register fzf-lua with `vim.ui.select`

---

### nvim-dap

#### dap_commands

DAP builtin commands

#### dap_configurations

DAP configurations

#### dap_breakpoints

DAP breakpoints

#### dap_variables

DAP active session variables

#### dap_frames

DAP active session jump to frame


### shell integrations

#### tmux_buffers

Tmux paste buffers

#### zoxide

Zoxide recent directories

---

### Completion Functions

#### complete_path

Complete path under cursor (incl dirs)

##### complete_path.word_pattern

Type: `string`, Default: `nil`

The pattern used to match the word under the cursor. Text around the cursor position that matches will be used as the initial query and replaced by a chosen completion. The default matches anything but spaces and single/double quotes.

#### complete_file

Complete file under cursor (excl dirs)

##### complete_file.word_pattern

Type: `string`, Default: `nil`

See [`complete_path.word_pattern`](#complete_path.word_pattern)

#### complete_line

Complete line (all open buffers)

#### complete_bline

Complete line (current buffer only)

---

<!--- vim: set nospell: -->
