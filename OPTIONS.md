> [!NOTE]
> **This document should not be modified directly as it's automatically generated from emmylua
> comments and annotations and updated as part of the vimdoc CI, for manual regeneration run
> `nvim -l scripts/gen_options.lua`**

---

# Fzf-Lua Commands and Options

- [General Usage](#general-usage)
- [Setup Options](#setup-options)
- [Global Options](#global-options)
- [Pickers](#pickers)

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

It is not recommended to modify this value as this can have unintended consequences when entries contain the character designated as `nbsp`, but if your terminal/font does not support `EN_SPACE` you can use `NBSP` (U+00A0) instead:
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

If set to an `object`, fzf-lua expects a previewer class that will be initialized with `object:new(...)`, see the advanced Wiki "Neovim builtin previewer" section for more info.

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

#### setup.ui_select

Type: `boolean|table|function`, Default: `false`

Register fzf-lua as the UI interface for `vim.ui.select` during `setup`.

When set to a table or function, the value is passed to `register_ui_select`.

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

#### globals.autoclose

Type: `boolean`, Default: `nil`

Auto close fzf-lua interface when a terminal is opened, set to `false` to keep the interface open.

#### globals.color_icons

Type: `boolean`, Default: `nil`

Add coloring of file|git icons.

#### globals.cwd

Type: `string`, Default: `nil`

Sets the current working directory.

#### globals.cwd_only

Type: `boolean`, Default: `nil`

Limit results to files in the current working directory only.

#### globals.debug

Type: `string[]`, Default: `(boolean|integer|"v"|"verbose")`

Enable debug mode (output debug prints).

#### globals.file_icons

Type: `boolean|integer|string`, Default: `nil`

If available, display file icons. Set to `true` will attempt to use "nvim-web-devicons" and fallback to "mini.icons", other possible values are `devicons` or `mini` which force loading a specific icons plugin, for example: `:FzfLua files file_icons=mini` or `:lua require("fzf-lua").files({ file_icons = "devicons" })`.

#### globals.fn_postprocess

Type: `boolean|string|function`, Default: `nil`

Postprocess function called after command execution.

#### globals.fn_preprocess

Type: `boolean|string|function`, Default: `nil`

Preprocess function called before command execution.

#### globals.fn_transform

Type: `boolean|string|function`, Default: `nil`

Transform function for each entry, can be a function or a string that returns a function.

#### globals.formatter

Type: `string`, Default: `nil`

Custom path formatter, can be defined under `setup.formatters`, fzf-lua comes with a builtin vscode-like formatter, displaying the filename first followed by the folder. Try it out with `:FzfLua files formatter=path.filename_first` or `:FzfLua live_grep formatter=path.filename_first`. For permanency: `require("fzf-lua").setup({ files = { formatter = "path.filename_first" } })`.

#### globals.fzf_bin

Type: `string`, Default: `nil`

Path to fzf binary. By default uses fzf found in `$PATH`.

#### globals.fzf_colors

Type: `{ [1]: boolean?, [string]: string? }`, Default: `nil`

Fzf `--color` flag configuration passed to the fzf binary, set `[1]=true` to inherit terminal colorscheme, consult `man fzf` for all available options.

#### globals.fzf_opts

Type: `table<string,any>`, Default: `{ ["--ansi"] = true, ["--border"] = "none", ["--height"] ...`

Fzf command-line options passed to fzf binary as key-value pairs, consult `man fzf` for all available options. For example `fzf_opts = { ["--layout"] = "reverse-list" }`.

#### globals.fzf_tmux_opts

Type: `table<string,any>`, Default: `{ ["--margin"] = "0,0", ["-p"] = "80%,80%" }`

Options passed to the fzf-tmux wrapper, e.g. `{ ["-p"] = "80%,80%" }`.

#### globals.git_icons

Type: `boolean`, Default: `nil`

If inside a git-repo add git status indicator icons e.g. `M` for modified files.

#### globals.header

Type: `string|false`, Default: `nil`

Header line, set to any string to display a header line, set to `false` to disable fzf-lua interactive headers (e.g. "ctrl-g to disable .gitignore", etc), passed to fzf as `--header` flag.

#### globals.multiprocess

Type: `integer|boolean`, Default: `nil`

Use the multiprocess shell wrapper for async file generation, improves performance for large file sets.

#### globals.no_header_i

Type: `boolean`, Default: `nil`

Disable interactive action headers.

#### globals.no_hide

Type: `boolean`, Default: `nil`

Disable "hide" profile for the picker, process will be terminated on abort/accept.

#### globals.no_resume

Type: `boolean`, Default: `nil`

Disable resuming for the current picker.

#### globals.preview

Type: `string|function|table`, Default: `nil`

Fzf native preview command, can be a string, function or table.

#### globals.preview_offset

Type: `string`, Default: `nil`

Preview offset expression passed to fzf `--preview-window`, consult `man fzf` for more info.

#### globals.preview_pager

Type: `string`, Default: `nil`

Pager command for shell preview commands (e.g. `delta`).

#### globals.previewer

Type: `Previewer|string|false`, Default: `nil`

Previewer override, set to `false` to disable the previewer. By default files pickers use the "builtin" previewer, possible values for file pickers `bat|cat|head`. Other overrides include: `:FzfLua helptags previewer=help_native` or `:FzfLua manpages previewer=man_native`.

#### globals.profile

Type: `string|table`, Default: `nil`

Apply a profile on top of the current configuration, can be a string or table.

#### globals.prompt

Type: `string`, Default: `nil`

Fzf prompt, passed to fzf as `--prompt` flag.

#### globals.query

Type: `string`, Default: `nil`

Initial query (prompt text), passed to fzf as `--query` flag.

#### globals.render_crlf

Type: `boolean`, Default: `nil`

Enable rendering CRLF (`\r\n`) in entries.

#### globals.resume

Type: `boolean`, Default: `nil`

Resume last search for the picker, recall last query, selected items, etc.

#### globals.silent

Type: `boolean|integer`, Default: `nil`

Do not display any messages or warnings.

#### globals.silent_fail

Type: `boolean`, Default: `nil`

Do not display an error message when the provider command fails.

#### globals.winopts.backdrop

Type: `number|boolean`, Default: `60`

Backdrop opacity value, 0 for fully opaque, 100 for fully transparent (i.e. disabled).

#### globals.winopts.border

Type: `string|table`, Default: `"rounded"`

Border of the fzf-lua float, possible values are `none|single|double|rounded|thicc|thiccc|thicccc` or a custom border character array passed as is to `nvim_open_win`.

#### globals.winopts.col

Type: `number`, Default: `0.55`

Screen column where to place the fzf-lua float window, between 0-1 will represent percentage of `vim.o.columns` (0: leftmost, 1: rightmost), if >= 1 will attempt to place the float in the exact screen column.

#### globals.winopts.cursorline

Type: `boolean`, Default: `nil`

Highlight the current line in main window.

#### globals.winopts.fullscreen

Type: `boolean`, Default: `false`

Use fullscreen for the fzf-lua floating window.

#### globals.winopts.height

Type: `number`, Default: `0.85`

Height of the fzf-lua float, between 0-1 will represent percentage of `vim.o.lines` (1: max height), if >= 1 will use fixed number of lines.

#### globals.winopts.preview.border

Type: `any`, Default: `"rounded"`

Preview border for native fzf previewers (i.e. `bat`, `git_status`), set to `noborder` to hide the preview border, consult `man fzf` for all available options.

#### globals.winopts.preview.default

Type: `string`, Default: `"builtin"`

Default previewer for file pickers, possible values `builtin|bat|cat|head`.

#### globals.winopts.preview.delay

Type: `integer`, Default: `20`

Debounce time (milliseconds) for displaying the preview buffer in the builtin previewer.

#### globals.winopts.preview.flip_columns

Type: `integer`, Default: `100`

Auto-detect the preview layout based on available width, see note in `winopts.preview.layout`.

#### globals.winopts.preview.hidden

Type: `boolean`, Default: `false`

Preview startup visibility in both native fzf and the builtin previewer, mapped to fzf's `--preview-window:[no]hidden` flag. NOTE: this is different than setting `previewer=false` which disables the previewer altogether with no toggle ability.

#### globals.winopts.preview.horizontal

Type: `string`, Default: `"right:60%"`

Horizontal preview layout, mapped to fzf's `--preview-window:...` flag. Requires `winopts.preview.layout={horizontal|flex}`.

#### globals.winopts.preview.layout

Type: `string`, Default: `"flex"`

Preview layout, possible values are `horizontal|vertical|flex`, when set to `flex` fzf window width is tested against `winopts.preview.flip_columns`, when <= `vertical` is used, otherwise `horizontal`.

#### globals.winopts.preview.scrollbar

Type: `string|boolean`, Default: `"border"`

Scrollbar style in the builtin previewer, set to `false` to disable, possible values are `float|border`.

#### globals.winopts.preview.scrolloff

Type: `integer`, Default: `-1`

Float style scrollbar offset from the right edge of the preview window. Requires `winopts.preview.scrollbar=float`.

#### globals.winopts.preview.title

Type: `boolean`, Default: `true`

Controls title display in the builtin previewer.

#### globals.winopts.preview.title_pos

Type: `string[]`, Default: `("center"|"left"|"right")`

Controls title display in the builtin previewer, possible values are `left|right|center`.

#### globals.winopts.preview.vertical

Type: `string`, Default: `"down:45%"`

Vertical preview layout, mapped to fzf's `--preview-window:...` flag. Requires `winopts.preview.layout={vertical|flex}`.

#### globals.winopts.preview.winopts.cursorcolumn

Type: `boolean`, Default: `false`

Builtin previewer buffer local option, see `:help 'cursorcolumn'`.

#### globals.winopts.preview.winopts.cursorline

Type: `boolean`, Default: `true`

Builtin previewer buffer local option, see `:help 'cursorline'`.

#### globals.winopts.preview.winopts.cursorlineopt

Type: `string`, Default: `"both"`

Builtin previewer buffer local option, see `:help 'cursorlineopt'`.

#### globals.winopts.preview.winopts.foldenable

Type: `boolean`, Default: `false`

Builtin previewer buffer local option, see `:help 'foldenable'`.

#### globals.winopts.preview.winopts.foldmethod

Type: `string`, Default: `"manual"`

Builtin previewer buffer local option, see `:help 'foldmethod'`.

#### globals.winopts.preview.winopts.list

Type: `boolean`, Default: `false`

Builtin previewer buffer local option, see `:help 'list'`.

#### globals.winopts.preview.winopts.number

Type: `boolean`, Default: `true`

Builtin previewer buffer local option, see `:help 'number'`.

#### globals.winopts.preview.winopts.relativenumber

Type: `boolean`, Default: `false`

Builtin previewer buffer local option, see `:help 'relativenumber'`.

#### globals.winopts.preview.winopts.scrolloff

Type: `integer`, Default: `0`

Builtin previewer buffer local option, see `:help 'scrolloff'`.

#### globals.winopts.preview.winopts.signcolumn

Type: `string`, Default: `"no"`

Builtin previewer buffer local option, see `:help 'signcolumn'`.

#### globals.winopts.preview.winopts.winblend

Type: `integer`, Default: `nil`

Builtin previewer window transparency, see `:help 'winblend'`.

#### globals.winopts.preview.wrap

Type: `boolean`, Default: `false`

Line wrap in both native fzf and the builtin previewer, mapped to fzf's `--preview-window:[no]wrap` flag.

#### globals.winopts.row

Type: `number`, Default: `0.35`

Screen row where to place the fzf-lua float window, between 0-1 will represent percentage of `vim.o.lines` (0: top, 1: bottom), if >= 1 will attempt to place the float in the exact screen line.

#### globals.winopts.split

Type: `string|function|false`, Default: `nil`

Neovim split command to use for fzf-lua interface, e.g `belowright new`.

#### globals.winopts.title

Type: `string`, Default: `nil`

Controls title display in the fzf window, set by the calling picker.

#### globals.winopts.title_flags

Type: `boolean`, Default: `nil`

Set to `false` to disable fzf window title flags (hidden, ignore, etc).

#### globals.winopts.title_pos

Type: `string`, Default: `"center"`

Controls title display in the fzf window, possible values are `left|right|center`.

#### globals.winopts.toggle_behavior

Type: `string`, Default: `nil`

Toggle behavior for fzf-lua window.

#### globals.winopts.treesitter

Type: `TreesitterWinopts|boolean`, Default: `{ enabled = true, fzf_colors = { hl = "-1:reverse", ["hl+...`

Use treesitter highlighting in fzf's main window. NOTE: Only works for file-like entries where treesitter parser exists and is loaded for the filetype.

#### globals.winopts.width

Type: `number`, Default: `0.8`

Width of the fzf-lua float, between 0-1 will represent percentage of `vim.o.columns` (1: max width), if >= 1 will use fixed number of columns.

#### globals.winopts.winblend

Type: `boolean`, Default: `nil`

Enable window transparency.

#### globals.winopts.winhl

Type: `boolean`, Default: `nil`

Enable window highlight groups.

#### globals.keymap.builtin

Type: `table<string,string>`, Default: `{ ["<F1>"] = "toggle-help", ["<F2>"] = "toggle-fullscreen...`

Keybinds for builtin (Neovim) commands.

#### globals.keymap.fzf

Type: `table<string,string>`, Default: `{ ["alt-G"] = "last", ["alt-a"] = "toggle-all", ["alt-g"]...`

Keybinds for fzf commands.

#### globals.actions

Type: `table<string,Actions>`, Default: `{ files = { ["alt-Q"] = <function 1>, ["alt-f"] = { fn = ...`

Actions to execute on selected items.

#### globals.file_icon_padding

Type: `string`, Default: `""`

Padding after file icons.

#### globals.hls.backdrop

Type: `string`, Default: `"FzfLuaBackdrop"`

Backdrop color, black by default, used to darken the background color when opening the UI.

#### globals.hls.border

Type: `string`, Default: `"FzfLuaBorder"`

Main fzf (terminal) window border highlight group.

#### globals.hls.buf_flag_alt

Type: `string`, Default: `"FzfLuaBufFlagAlt"`

Highlight group for the alternate buffer flag in `buffers`, `tabs`.

#### globals.hls.buf_flag_cur

Type: `string`, Default: `"FzfLuaBufFlagCur"`

Highlight group for the current buffer flag in `buffers`, `tabs`.

#### globals.hls.buf_id

Type: `string`, Default: `"FzfLuaBufId"`

Highlight group for buffer id (number) in `lines`.

#### globals.hls.buf_linenr

Type: `string`, Default: `"FzfLuaBufLineNr"`

Highlight group for buffer line number in `lines`, `blines` and `treesitter`.

#### globals.hls.buf_name

Type: `string`, Default: `"FzfLuaBufName"`

Highlight group for buffer name (filepath) in `lines`.

#### globals.hls.buf_nr

Type: `string`, Default: `"FzfLuaBufNr"`

Highlight group for buffer number in `buffers`, `tabs`.

#### globals.hls.cmd_buf

Type: `string`, Default: `"FzfLuaCmdBuf"`

Highlight group for buffer commands in `:FzfLua commands`, by default links to `Added`.

#### globals.hls.cmd_ex

Type: `string`, Default: `"FzfLuaCmdEx"`

Highlight group for ex commands in `:FzfLua commands`, by default links to `Statement`.

#### globals.hls.cmd_global

Type: `string`, Default: `"FzfLuaCmdGlobal"`

Highlight group for global commands in `:FzfLua commands`, by default links to `Directory`.

#### globals.hls.cursor

Type: `string`, Default: `"FzfLuaCursor"`

Builtin previewer window `Cursor` highlight group.

#### globals.hls.cursorline

Type: `string`, Default: `"FzfLuaCursorLine"`

Builtin previewer window `CursorLine` highlight group.

#### globals.hls.cursorlinenr

Type: `string`, Default: `"FzfLuaCursorLineNr"`

Builtin previewer window `CursorLineNr` highlight group.

#### globals.hls.dir_icon

Type: `string`, Default: `"FzfLuaDirIcon"`

Highlight group for the directory icon in paths that end with a separator, usually used in path completion, e.g. `complete_path`.

#### globals.hls.dir_part

Type: `string`, Default: `"FzfLuaDirPart"`

Highlight group for the directory part when using `path.dirname_first` or `path.filename_first` formatters.

#### globals.hls.file_part

Type: `string`, Default: `"FzfLuaFilePart"`

Highlight group for the directory part when using `path.dirname_first` or `path.filename_first` formatters.

#### globals.hls.fzf.border

Type: `string`, Default: `"FzfLuaFzfBorder"`

Highlight group for fzf's `border`, by default links to `FzfLuaBorder`.

#### globals.hls.fzf.cursorline

Type: `string`, Default: `"FzfLuaFzfCursorLine"`

Highlight group for fzf's `fg+` and `bg+`, by default links to `FzfLuaCursorLine`.

#### globals.hls.fzf.gutter

Type: `string`, Default: `"FzfLuaFzfGutter"`

Highlight group for fzf's `gutter`, by default links to `FzfLuaFzfBorder`. NOTE: `bg` property of the highlight group will be used.

#### globals.hls.fzf.header

Type: `string`, Default: `"FzfLuaFzfHeader"`

Highlight group for fzf's `header`, by default links to `FzfLuaTitle`.

#### globals.hls.fzf.info

Type: `string`, Default: `"FzfLuaFzfInfo"`

Highlight group for fzf's `info`, by default links to `NonText`.

#### globals.hls.fzf.marker

Type: `string`, Default: `"FzfLuaFzfMarker"`

Highlight group for fzf's `marker`, by default links to `FzfLuaFzfPointer`.

#### globals.hls.fzf.match

Type: `string`, Default: `"FzfLuaFzfMatch"`

Highlight group for fzf's `hl+`, by default links to `Special`.

#### globals.hls.fzf.normal

Type: `string`, Default: `"FzfLuaFzfNormal"`

Highlight group for fzf's `fg` and `bg`, by default links to `FzfLuaNormal`.

#### globals.hls.fzf.pointer

Type: `string`, Default: `"FzfLuaFzfPointer"`

Highlight group for fzf's `pointer`, by default links to `Special`.

#### globals.hls.fzf.prompt

Type: `string`, Default: `"FzfLuaFzfPrompt"`

Highlight group for fzf's `prompt`, by default links to `Special`.

#### globals.hls.fzf.query

Type: `string`, Default: `"FzfLuaFzfQuery"`

Highlight group for fzf's `query`, by default links to `FzfLuaNormal` and sets text to `regular` (non-bold).

#### globals.hls.fzf.scrollbar

Type: `string`, Default: `"FzfLuaFzfScrollbar"`

Highlight group for fzf's `scrollbar`, by default links to `FzfLuaFzfBorder`.

#### globals.hls.fzf.separator

Type: `string`, Default: `"FzfLuaFzfSeparator"`

Highlight group for fzf's `separator`, by default links to `FzfLuaFzfBorder`.

#### globals.hls.fzf.spinner

Type: `string`, Default: `"FzfLuaFzfSpinner"`

Highlight group for fzf's `spinner`, by default links to `FzfLuaFzfPointer`.

#### globals.hls.header_bind

Type: `string`, Default: `"FzfLuaHeaderBind"`

Interactive headers keybind highlight group, e.g. `<ctrl-g> to Disable .gitignore`.

#### globals.hls.header_text

Type: `string`, Default: `"FzfLuaHeaderText"`

Interactive headers description highlight group, e.g. `<ctrl-g> to Disable .gitignore`.

#### globals.hls.help_border

Type: `string`, Default: `"FzfLuaHelpBorder"`

Help window (F1) border highlight group.

#### globals.hls.help_normal

Type: `string`, Default: `"FzfLuaHelpNormal"`

Help window (F1) normal (text/bg) highlight group.

#### globals.hls.live_prompt

Type: `string`, Default: `"FzfLuaLivePrompt"`

Highlight group for the prompt text in "live" pickers.

#### globals.hls.live_sym

Type: `string`, Default: `"FzfLuaLiveSym"`

Highlight group for the matched characters in `lsp_live_workspace_symbols`.

#### globals.hls.normal

Type: `string`, Default: `"FzfLuaNormal"`

Main fzf (terminal) window normal (text/bg) highlight group.

#### globals.hls.path_colnr

Type: `string`, Default: `"FzfLuaPathColNr"`

Highlight group for the column part of paths, e.g. `file:<line>:<col>:`, used in pickers such as `buffers`, `quickfix`, `lsp`, `diagnostics`, etc.

#### globals.hls.path_linenr

Type: `string`, Default: `"FzfLuaPathLineNr"`

Highlight group for the line part of paths, e.g. `file:<line>:<col>:`, used in pickers such as `buffers`, `quickfix`, `lsp`, `diagnostics`, etc.

#### globals.hls.preview_border

Type: `string`, Default: `"FzfLuaPreviewBorder"`

Builtin previewer window border highlight group.

#### globals.hls.preview_normal

Type: `string`, Default: `"FzfLuaPreviewNormal"`

Builtin previewer window normal (text/bg) highlight group.

#### globals.hls.preview_title

Type: `string`, Default: `"FzfLuaPreviewTitle"`

Builtin previewer window title highlight group.

#### globals.hls.scrollborder_e

Type: `string`, Default: `"FzfLuaScrollBorderEmpty"`

Builtin previewer window `border` scrollbar empty highlight group.

#### globals.hls.scrollborder_f

Type: `string`, Default: `"FzfLuaScrollBorderFull"`

Builtin previewer window `border` scrollbar full highlight group.

#### globals.hls.scrollfloat_e

Type: `string`, Default: `"FzfLuaScrollFloatEmpty"`

Builtin previewer window `float` scrollbar empty highlight group.

#### globals.hls.scrollfloat_f

Type: `string|false`, Default: `"FzfLuaScrollFloatFull"`

Builtin previewer window `float` scrollbar full highlight group.

#### globals.hls.search

Type: `string`, Default: `"FzfLuaSearch"`

Builtin previewer window search matches highlight group.

#### globals.hls.tab_marker

Type: `string`, Default: `"FzfLuaTabMarker"`

Highlight group for the current tab marker in `tabs`.

#### globals.hls.tab_title

Type: `string`, Default: `"FzfLuaTabTitle"`

Highlight group for the tab title in `tabs`.

#### globals.hls.title

Type: `string`, Default: `"FzfLuaTitle"`

Main fzf (terminal) window title highlight group.

#### globals.hls.title_flags

Type: `string`, Default: `"FzfLuaTitleFlags"`

Main fzf (terminal) window title flags highlight group (hidden, etc).

---

## Pickers

#### args

Neovim's argument list (`:args`).

##### args.files_only

Type: `boolean`, Default: `true`

Exclude non-file entries (directories) from the list.

#### autocmds

Neovim autocommands.

##### autocmds.show_desc

Type: `boolean`, Default: `true`

Show the description field for autocommands in the list.

#### awesome_colorschemes

Awesome Neovim colorschemes.

##### awesome_colorschemes.icons

Type: `string,string,string`, Default: `{ "\27[0;34m󰇚\27[0m", "\27[0;33m\27[0m", " " }`

Icons for download status: [downloading, downloaded, not downloaded].

##### awesome_colorschemes.live_preview

Type: `boolean`, Default: `true`

Preview colorschemes as you navigate.

##### awesome_colorschemes.max_threads

Type: `integer`, Default: `5`

Maximum concurrent download threads.

##### awesome_colorschemes.dbfile

Type: `string`, Default: `"data/colorschemes.json"`

Path to the colorschemes database JSON file.

##### awesome_colorschemes.packpath

Type: `string|function`, Default: `nil`

Path where downloaded colorschemes will be stored.

#### blines

Current buffer lines.

#### btags

Search current buffer ctags.

##### btags.ctags_bin

Type: `string`, Default: `nil`

Path to the ctags binary.

##### btags.ctags_args

Type: `string`, Default: `nil`

Arguments passed to ctags when generating tags.

##### btags.ctags_autogen

Type: `boolean`, Default: `true`

Auto-generate ctags for the current buffer if no tags file exists.

#### buffers

Open buffers.

##### buffers.filename_only

Type: `boolean`, Default: `nil`

Only display the filename without the path.

##### buffers.cwd

Type: `string`, Default: `nil`

Override the current working directory for relative paths.

##### buffers.sort_lastused

Type: `boolean`, Default: `true`

Sort buffers by last used.

##### buffers.show_unloaded

Type: `boolean`, Default: `true`

Include unloaded (not yet displayed) buffers.

##### buffers.show_unlisted

Type: `boolean`, Default: `false`

Include unlisted buffers (`:help unlisted-buffer`).

##### buffers.ignore_current_buffer

Type: `boolean`, Default: `false`

Exclude the current buffer from the list.

##### buffers.cwd_only

Type: `boolean`, Default: `false`

Limit results to buffers from the current working directory only.

##### buffers.no_action_set_cursor

Type: `boolean`, Default: `true`

Do not set cursor position when switching buffers.

#### builtin

Fzf-lua builtin commands.

#### changes

Change list.

#### colorschemes

Installed colorschemes.

##### colorschemes.colors

Type: `string[]`, Default: `nil`

Override the list of colorschemes to display.

##### colorschemes.ignore_patterns

Type: `string[]`, Default: `nil`

Lua patterns to filter colorschemes.

##### colorschemes.live_preview

Type: `boolean`, Default: `true`

Preview colorschemes as you navigate.

#### command_history

Command history.

##### command_history.reverse_list

Type: `boolean`, Default: `nil`

Reverse the order of the history list (oldest first).

#### commands

Neovim commands.

##### commands.flatten

Type: `table<string,boolean>`, Default: `{}`

Table of commands to flatten (display without subcommands).

##### commands.include_builtin

Type: `boolean`, Default: `true`

Include builtin Neovim commands.

##### commands.sort_lastused

Type: `boolean`, Default: `nil`

Sort commands by last used.

#### complete_file

Complete file under cursor (excl dirs).

##### complete_file.word_pattern

Type: `string`, Default: `nil`

Pattern to match the word under cursor for initial query and replacement.

#### complete_line

Complete line (all open buffers).

#### complete_path

Complete path under cursor (incl dirs).

##### complete_path.word_pattern

Type: `string`, Default: `nil`

Pattern to match the word under cursor for initial query and replacement.

#### dap_breakpoints

DAP breakpoints.

#### dap_commands

DAP builtin commands.

#### dap_configurations

DAP configurations.

#### dap_frames

DAP active session frames.

#### dap_variables

DAP active session variables.

#### diagnostics

Workspace/document diagnostics.

##### diagnostics.signs

Type: `table`, Default: `nil`

Override default diagnostic signs.

##### diagnostics.severity_only

Type: `vim.diagnostic.SeverityFilter`, Default: `nil`

Filter diagnostics by exact severity.

##### diagnostics.severity_limit

Type: `vim.diagnostic.Severity|1|2|3|4`, Default: `nil`

Filter diagnostics up to and including this severity level.

##### diagnostics.severity_bound

Type: `vim.diagnostic.Severity|1|2|3|4`, Default: `nil`

Filter diagnostics from this severity level and below.

##### diagnostics.namespace

Type: `integer`, Default: `nil`

Filter diagnostics by namespace.

##### diagnostics.diag_all

Type: `boolean`, Default: `nil`

Include all workspace diagnostics (not just current buffer).

##### diagnostics.client_id

Type: `integer`, Default: `nil`

Filter diagnostics by LSP client ID.

##### diagnostics.sort

Type: `integer|boolean`, Default: `nil`

Sort diagnostics by severity, set to `false` to disable sorting.

##### diagnostics.icon_padding

Type: `boolean`, Default: `nil`

Add padding after diagnostic icons for alignment.

##### diagnostics.diag_icons

Type: `boolean`, Default: `true`

Display diagnostic icons.

##### diagnostics.diag_source

Type: `boolean`, Default: `true`

Display diagnostic source (e.g. `lua_ls`, `eslint`).

##### diagnostics.diag_code

Type: `boolean`, Default: `true`

Display diagnostic code.

##### diagnostics.multiline

Type: `integer|boolean`, Default: `2`

Enable multiline diagnostics display, set to a number for max lines.

##### diagnostics.color_headings

Type: `boolean`, Default: `true`

Color the file/buffer headings.

#### files

Find files using `fd`, `rg`, `find` or `dir.exe`.

##### files.ignore_current_file

Type: `boolean`, Default: `nil`

Exclude the current file from the list.

##### files.file_ignore_patterns

Type: `string[]`, Default: `nil`

Lua patterns of files to ignore.

##### files.line_query

Type: `boolean|fun(query: string) -> multi<...>`, Default: `nil`

Parse the query for a line number suffix, e.g. `file.lua:10` will open `file.lua` at line 10.

##### files.raw_cmd

Type: `string`, Default: `nil`

Raw shell command to use without any processing, bypasses all fzf-lua internals.

##### files.cwd_prompt

Type: `boolean`, Default: `true`

Display the current working directory in the prompt (`fzf.vim` style).

##### files.cwd_prompt_shorten_len

Type: `integer`, Default: `32`

Prompt over this length will be shortened using `pathshorten`.

##### files.cwd_prompt_shorten_val

Type: `integer`, Default: `1`

Length of shortened prompt path parts (`:help pathshorten`).

##### files.hidden

Type: `boolean`, Default: `true`

Include hidden files (toggle with `<A-h>`).

##### files.toggle_ignore_flag

Type: `string`, Default: `"--no-ignore"`

Flag passed to the shell command to toggle ignoring `.gitignore` rules.

##### files.toggle_hidden_flag

Type: `string`, Default: `"--hidden"`

Flag passed to the shell command to toggle showing hidden files.

##### files.toggle_follow_flag

Type: `string`, Default: `"-L"`

Flag passed to the shell command to toggle following symbolic links.

#### filetypes

Filetypes.

#### git_bcommits

Git commits (buffer).

#### git_blame

Git blame (buffer).

#### git_branches

Git branches.

##### git_branches.remotes

Type: `string`, Default: `"local"`

Filter branches, possible values are `local|remote|all`.

##### git_branches.cmd_add

Type: `string[]`, Default: `{ "git", "branch" }`

Shell command used to add a branch.

##### git_branches.cmd_del

Type: `string[]`, Default: `{ "git", "branch", "--delete" }`

Shell command used to delete a branch.

#### git_commits

Git commits (project).

#### git_diff

Git diff (changed files vs a git ref).

##### git_diff.ref

Type: `string`, Default: `"HEAD"`

Git reference to compare against.

##### git_diff.compare_against

Type: `string`, Default: `""`

Git reference used as the base for the comparison.

#### git_files

Git tracked files.

#### git_hunks

Git diff hunks (changed lines).

##### git_hunks.ref

Type: `string`, Default: `"HEAD"`

Git reference to compare against.

#### git_stash

Git stashes.

#### git_status

Git status (modified files).

#### git_tags

Git tags.

#### git_worktrees

Git worktrees.

##### git_worktrees.scope

Type: `string`, Default: `"global"`

Scope of the `cd` action, possible values are `local|win|tab|global`.

#### grep

Grep using `rg`, `grep` or other grep commands.

##### grep.rg_glob

Type: `boolean|integer`, Default: `1`

Use `rg` glob parsing, e.g. `foo -- -g*.md` will only match markdown files containing `foo`.

##### grep.raw_cmd

Type: `string`, Default: `nil`

Raw shell command to use without any processing, bypasses all fzf-lua internals.

##### grep.search

Type: `string`, Default: `nil`

Initial search string.

##### grep.regex

Type: `string`, Default: `nil`

Initial search pattern.

##### grep.no_esc

Type: `integer|boolean`, Default: `nil`

Disable escaping of special characters in the search query, set to `2` to disable escaping and regex mode.

##### grep.lgrep

Type: `boolean`, Default: `nil`

Enable live grep mode (search-as-you-type).

##### grep.search_paths

Type: `string[]`, Default: `nil`

List of paths to search (grep), e.g. `:FzfLua grep search_paths=/path/to/search`.

##### grep.input_prompt

Type: `string`, Default: `"Grep For> "`

Input prompt for the initial search query.

##### grep.rg_opts

Type: `string`, Default: `"--column --line-number --no-heading --color=always --sma...`

Ripgrep options passed to the `rg` command.

##### grep.grep_opts

Type: `string`, Default: `"--binary-files=without-match --line-number --recursive -...`

GNU grep options passed to the `grep` command.

##### grep.glob_flag

Type: `string`, Default: `"--iglob"`

Glob flag passed to the shell command, default `--iglob` (case insensitive), use `--glob` for case sensitive.

##### grep.glob_separator

Type: `string`, Default: `"%s%-%-"`

Query separator pattern (lua) for extracting glob patterns from the search query, default `%s%-%-` (` --`).

#### grep_curbuf

Grep current buffer only.

#### helptags

Neovim help tags.

##### helptags.fallback

Type: `boolean`, Default: `nil`

Fallback to searching all help files if no tags match.

#### highlights

Neovim highlight groups.

#### history

File history including current session.

#### jumps

Jump list.

#### keymaps

Neovim keymaps.

##### keymaps.ignore_patterns

Type: `string[]`, Default: `{ "^<SNR>", "^<Plug>" }`

Lua patterns to filter keymaps.

##### keymaps.show_desc

Type: `boolean`, Default: `true`

Show the description field for keymaps in the list.

##### keymaps.show_details

Type: `boolean`, Default: `true`

Show additional keymap details (buffer, noremap, etc).

##### keymaps.modes

Type: `string[]`, Default: `nil`

List of modes to include, e.g. `{ "n", "i", "v" }`.

#### lines

Open buffers lines.

##### lines.show_bufname

Type: `boolean|integer`, Default: `120`

Show buffer name in results. Set to a number to only show if the window width exceeds this value.

##### lines.show_unloaded

Type: `boolean`, Default: `true`

Include unloaded (not yet displayed) buffers.

##### lines.show_unlisted

Type: `boolean`, Default: `false`

Include unlisted buffers (`:help unlisted-buffer`).

##### lines.no_term_buffers

Type: `boolean`, Default: `true`

Exclude terminal buffers from the list.

##### lines.sort_lastused

Type: `boolean`, Default: `true`

Sort buffers by last used.

#### loclist

Location list entries.

#### loclist_stack

Location list history.

#### lsp

LSP references, definitions, etc.

##### lsp.async_or_timeout

Type: `integer|boolean`, Default: `5000`

Set to `true` for async LSP requests, or timeout (ms) for `vim.lsp.buf_request_sync`.

#### lsp_code_actions

LSP code actions.

##### lsp_code_actions.post_action_cb

Type: `function`, Default: `nil`

Callback to execute after applying a code action.

##### lsp_code_actions.context

Type: `lsp.CodeActionContext`, Default: `nil`

Code action context passed to the LSP server.

#### lsp_document_symbols

LSP document symbols.

#### lsp_finder

All LSP locations combined.

##### lsp_finder.async

Type: `boolean`, Default: `true`

Use async LSP requests.

##### lsp_finder.separator

Type: `string`, Default: `"| "`

Separator between provider prefix and entry text.

##### lsp_finder.providers

Type: `table`, Default: `{ { "declarations", prefix = "\27[0;35mdecl\27[0m" }, { "...`

List of LSP providers to query, e.g. `{ "references", "definitions" }`.

##### lsp_finder.no_autoclose

Type: `boolean`, Default: `nil`

Do not automatically close the picker when a single result is found.

#### lsp_symbols

LSP symbols (shared config).

##### lsp_symbols.lsp_query

Type: `string`, Default: `nil`

Initial query to filter symbols.

##### lsp_symbols.symbol_style

Type: `integer`, Default: `1`

Display style for symbol icons, `1` for icon only, `2` for icon+name, `3` for icon+name(colored).

##### lsp_symbols.symbol_icons

Type: `table<string,string>`, Default: `{ Array = "󱡠", Boolean = "󰨙", Class = "󰆧", Const...`

Icons for each symbol kind.

##### lsp_symbols.child_prefix

Type: `boolean`, Default: `true`

Display child prefix (indentation) for nested symbols.

##### lsp_symbols.parent_postfix

Type: `boolean`, Default: `false`

Display parent postfix for nested symbols.

##### lsp_symbols.locate

Type: `boolean`, Default: `false`

Jump to the selected symbol location in the file.

#### lsp_workspace_symbols

LSP workspace symbols.

#### manpages

Man pages.

#### marks

Neovim marks.

##### marks.marks

Type: `string`, Default: `nil`

Lua pattern to filter marks.

##### marks.sort

Type: `boolean`, Default: `false`

Sort marks alphabetically. Set to `false` to maintain original order.

#### menus

Neovim menus.

#### nvim_options

Neovim options.

##### nvim_options.separator

Type: `string`, Default: `"│"`

Separator between option name and value.

##### nvim_options.color_values

Type: `boolean`, Default: `true`

Colorize option values.

#### oldfiles

File history (output of `:oldfiles`).

##### oldfiles.stat_file

Type: `boolean`, Default: `true`

Only include files that still exist on disk.

##### oldfiles.include_current_session

Type: `boolean`, Default: `false`

Include files opened during the current session.

##### oldfiles.ignore_current_buffer

Type: `boolean`, Default: `true`

Exclude the current buffer from the list.

#### packadd

`:packadd <package>`.

#### profiles

Fzf-lua configuration profiles.

#### quickfix

Quickfix list entries.

##### quickfix.separator

Type: `string`, Default: `"▏"`

Separator between filename and text.

##### quickfix.valid_only

Type: `boolean`, Default: `false`

Only include entries with valid file/line information.

#### quickfix_stack

Quickfix list history.

#### registers

Neovim registers.

##### registers.filter

Type: `string|function`, Default: `nil`

Lua pattern or function to filter registers.

##### registers.multiline

Type: `integer|boolean`, Default: `true`

Display multiline register contents, set to a number for max lines.

##### registers.ignore_empty

Type: `boolean`, Default: `true`

Ignore empty registers.

#### search_history

Search history.

##### search_history.reverse_list

Type: `boolean`, Default: `nil`

Reverse the order of the history list (oldest first).

##### search_history.reverse_search

Type: `boolean`, Default: `nil`

Also search in reverse direction.

#### serverlist

Neovim server list.

#### spell_suggest

Spelling suggestions.

##### spell_suggest.word_pattern

Type: `string`, Default: `nil`

The pattern used to match the word under the cursor. Text around the cursor position that matches will be used as the initial query and replaced by a chosen completion. The default matches anything but spaces and single/double quotes.

#### spellcheck

Misspelled words in buffer.

##### spellcheck.word_separator

Type: `string`, Default: `"[%s%p]"`

Lua pattern used to split words for spell checking.

##### spellcheck.bufnr

Type: `integer`, Default: `nil`

Buffer number to check, default: current buffer.

#### tabs

Open buffers by tabs.

##### tabs.filename_only

Type: `boolean`, Default: `nil`

Only display the filename without the path.

##### tabs.current_tab_only

Type: `boolean`, Default: `nil`

Only display buffers from the current tab.

##### tabs.tab_title

Type: `string`, Default: `"Tab"`

Tab title prefix in the results list.

##### tabs.tab_marker

Type: `string`, Default: `"<<"`

Marker for the current tab.

##### tabs.locate

Type: `boolean`, Default: `true`

Jump to the selected buffer's location in the file.

#### tags

Search project ctags.

#### tagstack

Tag stack.

#### tmux_buffers

Tmux paste buffers.

#### treesitter

Current buffer treesitter symbols.

##### treesitter.bufnr

Type: `integer`, Default: `nil`

Buffer number to search, default: current buffer.

#### undotree

Undo tree.

##### undotree.locate

Type: `boolean`, Default: `true`

Jump to the current undo position on picker open.

#### zoxide

Zoxide recent directories.

##### zoxide.scope

Type: `string`, Default: `"global"`

Scope of the `cd` action, possible values are `local|win|tab|global`.

##### zoxide.git_root

Type: `boolean`, Default: `false`

Change to the git root directory instead of the zoxide path.

---

<!--- vim: set nospell: -->
