---@meta
error("Cannot require a meta file")

_G.FzfLua = require("fzf-lua")

---@class fzf-lua.previewer.SwiperBase
---@field new function
---@field setup_opts function
---@field zero_cmd function?
---@field result_cmd function?
---@field preview_cmd function?
---@field highlight_matches function?
---@field win fzf-lua.Win

---@class fzf-lua.previewer.Fzf
---@field new function
---@field setup_opts function
---@field zero function?
---@field cmdline function?
---@field fzf_delimiter function?
---@field preview_window function?
---@field _preview_offset function?

---@class fzf-lua.previewer.Builtin
---@field type "builtin"
---@field new function
---@field setup_opts function
---@field opts table
---@field win fzf-lua.Win
---@field delay integer
---@field title any
---@field title_pos "center"|"left"|"right"
---@field title_fnamemodify fun(title: string, width: integer?): string
---@field render_markdown table?
---@field snacks_image table?
---@field winopts table?
---@field syntax boolean
---@field syntax_delay integer
---@field syntax_limit_b integer
---@field syntax_limit_l integer
---@field limit_b integer
---@field _ts_limit_b_per_line integer
---@field treesitter table
---@field toggle_behavior "default"|"extend"
---@field winopts_orig table
---@field winblend integer
---@field extensions { [string]: string[]? }
---@field ueberzug_scaler "crop"|"distort"|"contain"|"fit_contain"|"cover"|"forced_cover"
---@field cached_bufnrs { [string]: fzf-lua.previewer.CursorPos? }
---@field cached_buffers { [string]: fzf-lua.buffer_or_file.Bcache? }
---@field listed_buffers { [string]: boolean? }
---@field clear_on_redraw boolean?
---
---@field orig_pos fzf-lua.previewer.CursorPos
---@alias fzf-lua.previewer.CursorPos (true|[integer, integer])

---@class fzf-lua.previewer.BufferOrFile
---@field match_id integer?

---@class fzf-lua.path.Entry
---@field stripped string
---@field bufnr integer?
---@field bufname string?
---@field terminal boolean?
---@field path string?
---@field line integer
---@field col integer
---@field ctag string?
---@field uri string?
---@field range { start: { line: integer, col: integer } }?
---@field debug string? debug information

---@class fzf-lua.buffer_or_file.Entry : fzf-lua.path.Entry, {}
---@field do_not_cache boolean?
---@field no_scrollbar boolean?
---@field buf_is_valid boolean?
---@field buf_is_loaded boolean?
---@field tick integer?
---@field fs_stat uv.fs_stat.result?
---@field no_syntax boolean?
---@field cached fzf-lua.buffer_or_file.Bcache?
---@field content string[]?
---@field filetype string?

---@class fzf-lua.keymap.Entry
---@field vmap string?
---@field mode string?
---@field key string?

---@class fzf-lua.buffer_or_file.Bcache
---@field bufnr integer
---@field min_winopts boolean?
---@field invalid boolean? buffer content changed
---@field invalid_pos boolean? position changed
---@field tick integer?

---@alias fzf-lua.config.Action fzf-lua.ActionSpec|fzf-lua.shell.data2|fzf-lua.shell.data2[]|false
---@alias fzf-lua.config.Actions { [string]: fzf-lua.config.Action }

---@class fzf-lua.ActionSpec
---@field [1] fzf-lua.shell.data2?
---@field fn fzf-lua.shell.data2?
---@field exec_silent boolean?
---@field reload boolean
---@field field_index string?
---@field desc string?
---@field prefix string?
---@field postfix string?
---@field reuse boolean?
---@field noclose boolean?
---@field _ignore boolean?

-- partial type
---@class fzf-lua.Config: fzf-lua.config.Defaults,{}
---@field __CTX fzf-lua.Ctx?
---@field [string] any

---a basic config can be used by fzf_exec?
---generated from the result of `:=FzfLua.config.normalize_opts({}, {})`
---@class fzf-lua.config.Base
---@field PidObject table
---@field __FZF_VERSION number[]
---@field __call_fn function
---@field __call_opts table
---@field __resume_key function|string
---@field _cwd string
---@field _fzf_cli_args string[]
---@field _is_skim boolean
---@field _normalized boolean
---@field actions fzf-lua.config.Actions|{}
---@field cwd_prompt boolean
---@field dir_icon string
---@field enrich function
---@field file_icon_padding string
---@field fzf_bin string
---@field fzf_colors table<string, string>
---@field fzf_opts table<string, any>
---@field fzf_tmux_opts table<string, any>
---@field hls table<string, any>
---@field keymap fzf-lua.config.Keymap
---@field no_header boolean
---@field no_header_i boolean
---@field prompt string
---@field winopts fzf-lua.config.Winopts|{}
---...
---@field cwd string?
---@field multiprocess integer|boolean?
---@field fn_transform boolean|string|function?
---@field fn_preprocess boolean|string|function?
---@field fn_postprocess boolean|string|function?
---@field file_icons boolean|integer?
---@field color_icons boolean?
---@field _type "file"?
---@field git_icons boolean?
---@field _actions? fun():fzf-lua.config.Actions
---@field silent boolean?
---@field _cached_hls string[]?
---@field previewer fun(...)|table|string?
---@field preview string|function|table?
---@field complete (fun(_, _, _ ,_):_, _)|boolean?
---@field header string
---@field _multiline? boolean
---@field query string?
---@field __CTX fzf-lua.Ctx?
---@field resume boolean?
---@field no_resume boolean?
---@field profile string|table?
---@field is_live boolean? is "live" picker
---@field silent_fail boolean?
---set_headers
---@field _headers string[]?
---@field headers string[]?
---@field cwd_prompt_shorten_len integer?
---@field cwd_prompt_shorten_val integer?
---@field header_prefix string?
---@field header_separator string?
---fzf_wrap
---@field fn_selected string
---@field cb_co fun(co: thread)
---@field _start boolean?
---make_entry.preprocess
---@field cwd_only boolean
---make_entry
---@field _fmt table
---FzfWin:treesitter_attach
---@field _treesitter (fun(line:string):string,string?,string?,string?)|boolean?
---stringify_mt
---@field cmd? string
---@field contents? fzf-lua.content|fzf-lua.shell.data2
---@field debug? boolean|'v'|'verbose'
---@field rg_glob? boolean

---mostly ai generated currently...
---@class fzf-lua.config.Defaults
---@field nbsp string
---@field winopts fzf-lua.config.Winopts
---@field keymap fzf-lua.config.Keymap
---@field actions fzf-lua.config.Actions
---@field fzf_bin string?
---@field fzf_opts table<string, any>
---@field fzf_tmux_opts table<string, any>
---@field previewers table<string, fzf-lua.config.Previewer>
---@field formatters table<string, any>
---@field files fzf-lua.config.Files
---@field global fzf-lua.config.Global
---@field git fzf-lua.config.Git
---@field grep fzf-lua.config.Grep
---@field grep_curbuf fzf-lua.config.GrepCurbuf
---@field args fzf-lua.config.Args
---@field oldfiles fzf-lua.config.Oldfiles
---@field quickfix fzf-lua.config.Quickfix
---@field quickfix_stack fzf-lua.config.QuickfixStack
---@field loclist fzf-lua.config.Loclist
---@field loclist_stack fzf-lua.config.LoclistStack
---@field buffers fzf-lua.config.Buffers
---@field tabs fzf-lua.config.Tabs
---@field lines fzf-lua.config.Lines
---@field blines fzf-lua.config.Blines
---@field treesitter fzf-lua.config.Treesitter
---@field spellcheck fzf-lua.config.Spellcheck
---@field tags fzf-lua.config.Tags
---@field btags fzf-lua.config.Btags
---@field colorschemes fzf-lua.config.Colorschemes
---@field highlights fzf-lua.config.Highlights
---@field awesome_colorschemes fzf-lua.config.AwesomeColorschemes
---@field helptags fzf-lua.config.Helptags
---@field manpages fzf-lua.config.Manpages
---@field lsp fzf-lua.config.Lsp
---@field diagnostics fzf-lua.config.Diagnostics
---@field builtin fzf-lua.config.Builtin
---@field profiles fzf-lua.config.Profiles
---@field marks fzf-lua.config.Marks
---@field changes fzf-lua.config.Changes
---@field jumps fzf-lua.config.Jumps
---@field tagstack fzf-lua.config.Tagstack
---@field commands fzf-lua.config.Commands
---@field autocmds fzf-lua.config.Autocmds
---@field command_history fzf-lua.config.CommandHistory
---@field search_history fzf-lua.config.SearchHistory
---@field registers fzf-lua.config.Registers
---@field keymaps fzf-lua.config.Keymaps
---@field nvim_options fzf-lua.config.NvimOptions
---@field spell_suggest fzf-lua.config.SpellSuggest
---@field filetypes fzf-lua.config.Filetypes
---@field packadd fzf-lua.config.Packadd
---@field menus fzf-lua.config.Menus
---@field tmux fzf-lua.config.Tmux
---@field dap fzf-lua.config.Dap
---@field complete_path fzf-lua.config.CompletePath
---@field complete_file fzf-lua.config.CompleteFile
---@field zoxide fzf-lua.config.Zoxide
---@field complete_line table
---@field file_icon_padding string
---@field dir_icon string
---@field __HLS fzf-lua.config.HLS

---@class fzf-lua.config.Winopts
---@field height number
---@field width number
---@field row number
---@field col number
---@field border any
---@field zindex integer
---@field relative string
---@field hide boolean
---@field split string|function|false
---@field backdrop number|boolean
---@field fullscreen boolean
---@field title any
---@field title_pos "center"|"left"|"right"
---@field treesitter fzf-lua.config.TreesitterWinopts
---@field preview fzf-lua.config.PreviewWinopts
---@field on_create fun(e: { winid: integer, bufnr: integer })
---@field on_close fun()
---@field toggle_behavior string?
---@field __winhls { main: [string, string][], prev: [string, string][] }

---@class fzf-lua.config.TreesitterWinopts
---@field enabled boolean
---@field fzf_colors? table<string, string>

---@class fzf-lua.config.PreviewWinopts
---@field default? string
---@field border? any
---@field wrap? boolean
---@field hidden? boolean
---@field vertical? string
---@field horizontal? string
---@field layout? string
---@field flip_columns? integer
---@field title? any
---@field title_pos? "center"|"left"|"right"
---@field scrollbar? string
---@field scrolloff? integer
---@field delay? integer
---@field winopts? fzf-lua.config.PreviewerWinopts

---@class fzf-lua.config.PreviewerWinopts
---@field number? boolean
---@field relativenumber? boolean
---@field cursorline? boolean
---@field cursorlineopt? string
---@field cursorcolumn? boolean
---@field signcolumn? string
---@field list? boolean
---@field foldenable? boolean
---@field foldmethod? string
---@field scrolloff? integer

---@class fzf-lua.config.Keymap
---@field builtin? table<string, string>
---@field fzf? table<string, string>

---@class fzf-lua.config.Previewer
---@field cmd string|fun():string?
---@field args string?
---@field _ctor fun(...)?
---@field pager fun(...)?
---@field cmd_deleted string?
---@field cmd_modified string?
---@field cmd_untracked string?
---@field _fn_git_icons fun():any?
---@field syntax boolean?
---@field syntax_delay integer?
---@field syntax_limit_l integer?
---@field syntax_limit_b integer?
---@field limit_b integer?
---@field treesitter table?
---@field ueberzug_scaler string?
---@field title_fnamemodify fun(s:string):string?
---@field render_markdown table?
---@field snacks_image table?
---@field diff_opts table?

---@class fzf-lua.config.Files: fzf-lua.config.Base
---@field cmd string|string[]?
---@field cwd_prompt_shorten_len integer
---@field cwd_prompt_shorten_val integer
---@field _fzf_nth_devicons boolean
---@field git_status_cmd string[]
---@field find_opts string
---@field rg_opts string
---@field fd_opts string
---@field dir_opts string
---@field hidden boolean
---@field toggle_ignore_flag string
---@field toggle_hidden_flag string
---@field toggle_follow_flag string
---@field ignore_current_file boolean
---@field file_ignore_patterns string[]
---@field line_query boolean|fun(query: string): lnum: string?, new_query: string?
---@field raw_cmd string

---@class fzf-lua.config.Global : fzf-lua.config.Files
---@field pickers (fun():table)|table
---@field _ctx table
---@field _fzf_nth_devicons boolean
---@field __alt_opts boolean?

---@class fzf-lua.config.Git
---@field files     fzf-lua.config.GitFiles
---@field status    fzf-lua.config.GitStatus
---@field diff      fzf-lua.config.GitDiff
---@field hunks     fzf-lua.config.GitHunks
---@field commits   fzf-lua.config.GitCommits
---@field bcommits  fzf-lua.config.GitBcommits
---@field blame     fzf-lua.config.GitBlame
---@field branches  fzf-lua.config.GitBranches
---@field worktrees fzf-lua.config.GitWorktrees
---@field tags      fzf-lua.config.GitTags
---@field stash     fzf-lua.config.GitStash
---@field icons     table<string, {icon:string, color:string}>

---@class fzf-lua.config.GitBase: fzf-lua.config.Base
---@field cmd string
---@field git_dir string
---@field _fzf_nth_devicons? boolean
---@field preview_pager? fun(...)|string

---@class fzf-lua.config.GitFiles: fzf-lua.config.GitBase

---@class fzf-lua.config.GitStatus: fzf-lua.config.GitBase

---@class fzf-lua.config.GitDiff: fzf-lua.config.GitBase
---@field ref? string

---@class fzf-lua.config.GitHunks: fzf-lua.config.GitBase
---@field cmd string
---@field ref? string

---@class fzf-lua.config.GitCommits: fzf-lua.config.GitBase
---@field cmd string

---@class fzf-lua.config.GitBcommits: fzf-lua.config.GitBase
---@field cmd string
---@field _multiline? boolean
---@field git_dir string

---@class fzf-lua.config.GitBlame: fzf-lua.config.GitBase
---@field cmd string
---@field _multiline? boolean
---@field git_dir string

---@class fzf-lua.config.GitBranches: fzf-lua.config.GitBase
---@field remotes? string
---@field cmd_add? table
---@field cmd_del? table
---@field _multiline? boolean

---@class fzf-lua.config.GitWorktrees: fzf-lua.config.GitBase
---@field _multiline? boolean

---@class fzf-lua.config.GitTags: fzf-lua.config.GitBase
---@field _multiline? boolean

---@class fzf-lua.config.GitStash: fzf-lua.config.GitBase

---@class fzf-lua.config.GrepCurbuf: fzf-lua.config.Grep
---@field filename string

---@class fzf-lua.config.Grep: fzf-lua.config.Base
---@field input_prompt string
---@field cmd string?
---@field grep_opts string
---@field rg_opts string
---@field rg_glob boolean|integer
---@field glob_flag string
---@field glob_separator string
---@field raw_cmd string
---@field __ACT_TO function
---@field search string?
---@field no_esc integer|boolean
---@field __resume_set function
---@field __resume_get function
---@field lgrep boolean grep or lgrep

---@class fzf-lua.config.Args: fzf-lua.config.Base
---@field files_only boolean
---@field _fzf_nth_devicons boolean

---@class fzf-lua.config.Oldfiles: fzf-lua.config.Base
---@field stat_file boolean
---@field _fzf_nth_devicons boolean
---@field include_current_session boolean

---@class fzf-lua.config.Quickfix: fzf-lua.config.Base
---@field separator string
---@field valid_only boolean

---@class fzf-lua.config.QuickfixStack: fzf-lua.config.Base
---@field marker string

---@class fzf-lua.config.Loclist : fzf-lua.config.Quickfix: fzf-lua.config.Base

---@class fzf-lua.config.LoclistStack : fzf-lua.config.QuickfixStack: fzf-lua.config.Base

---@class fzf-lua.config.BufferLines: fzf-lua.config.Base
---@field current_buffer_only boolean?
---@field sort_lastused boolean?
---@field show_bufname boolean?
---@field start_line integer?
---@field end_line integer?
---@field start "cursor"?

---@class fzf-lua.config.Buffers: fzf-lua.config.BufferLines
---@field filename_only boolean
---@field sort_lastused boolean
---@field show_unloaded boolean
---@field show_unlisted boolean
---@field ignore_current_buffer boolean
---@field no_action_set_cursor boolean
---@field cwd string?
---@field _ctx table
---@field _resume_reload boolean

---@class fzf-lua.config.Tabs: fzf-lua.config.Base
---@field filename_only boolean
---@field tab_title string
---@field tab_marker string
---@field locate boolean
---@field __locate_pos integer?
---@field _ctx table
---@field _resume_reload boolean
---@field current_tab_only boolean?

---@class fzf-lua.config.Lines: fzf-lua.config.BufferLines
---@field show_bufname boolean|integer
---@field show_unloaded boolean
---@field show_unlisted boolean
---@field no_term_buffers boolean
---@field sort_lastused boolean
---@field line_field_index string
---@field field_index_expr string
---@field _ctx table

---@class fzf-lua.config.Blines: fzf-lua.config.Lines

---@class fzf-lua.config.Treesitter: fzf-lua.config.Base
---@field line_field_index string
---@field bufnr integer?

---@class fzf-lua.config.Spellcheck: fzf-lua.config.BufferLines
---@field word_separator string
---@field bufnr integer?

---@class fzf-lua.config.TagsBase: fzf-lua.config.Base
---@field input_prompt string
---@field ctags_file string?
---@field rg_opts string
---@field grep_opts string
---@field formatter boolean
---@field cmd string

---@class fzf-lua.config.Tags: fzf-lua.config.TagsBase
---
---@class fzf-lua.config.TagsGrep: fzf-lua.config.TagsBase,fzf-lua.config.Grep

---@class fzf-lua.config.Btags : fzf-lua.config.TagsBase
---@field filename string
---@field _btags_cmd string
---@field ctags_autogen boolean
---@field ctags_bin string
---@field ctags_args string

---@class fzf-lua.config.Colorschemes: fzf-lua.config.Base
---@field live_preview boolean
---@field colors string[] overriden colorscheme list
---@field ignore_patterns string[] lua patterns to filter colorschemes

---@class fzf-lua.config.Highlights: fzf-lua.config.Base

---@class fzf-lua.config.AwesomeColorschemes: fzf-lua.config.Base
---@field live_preview boolean
---@field max_threads integer
---@field dbfile string
---@field icons table
---@field packpath fun():string
---@field _adm table AsyncDownloadManager
---@field dl_status integer
---@field _apply_awesome_theme function

---@class fzf-lua.config.Helptags: fzf-lua.config.Base
---@field fallback boolean?

---@class fzf-lua.config.Manpages: fzf-lua.config.Base
---@field cmd string

---@class fzf-lua.config.LspBase: fzf-lua.config.Base
---@field lsp_handler table
---@field lsp_params table
---@field jump1 boolean
---@field jump1_action fun(...)?
---@field _uri boolean
---@field async_or_timeout integer|boolean?
---@field reuse_win boolean

---@class fzf-lua.config.Lsp: fzf-lua.config.LspBase
---@field symbols fzf-lua.config.LspSymbols
---@field document_symbols fzf-lua.config.LspDocumentSymbols
---@field workspace_symbols fzf-lua.config.LspWorkspaceSymbols
---@field finder fzf-lua.config.LspFinder
---@field code_actions fzf-lua.config.LspCodeActions

---@class fzf-lua.config.LspSymbols: fzf-lua.config.LspBase
---@field locate boolean
---@field symbol_style integer
---@field symbol_icons table<string, string>
---@field symbol_hl fun(s:string):string
---@field symbol_fmt fun(s:string, ...):string
---@field child_prefix boolean
---@field exec_empty_query boolean
---@field line_field_index string
---@field field_index_expr string

---@class fzf-lua.config.LspDocumentSymbols: fzf-lua.config.LspSymbols
---@field __sym_bufnr integer
---@field __sym_bufname string

---@class fzf-lua.config.LspWorkspaceSymbols: fzf-lua.config.LspSymbols
---@field lsp_query string
---@field __ACT_TO function

---@class fzf-lua.config.LspLiveWorkspaceSymbols: fzf-lua.config.LspSymbols
---@field lsp_query string
---@field __ACT_TO function
---@field __resume_set function
---@field __resume_get function

---@class fzf-lua.config.LspFinder: fzf-lua.config.LspBase
---@field async boolean
---@field separator string
---@field _providers table<string, boolean>
---@field providers table
---@field no_autoclose boolean

---@class fzf-lua.config.LspCodeActions: fzf-lua.config.LspBase
---@field post_action_cb function
---@field context lsp.CodeActionContext
---@field filter fun(x: lsp.CodeAction|lsp.Command):boolean

---@class fzf-lua.config.Diagnostics: fzf-lua.config.Base
---@field color_headings boolean
---@field diag_icons boolean
---@field diag_source boolean
---@field diag_code boolean
---@field multiline integer
---@field signs boolean
---@field severity_only boolean
---@field severity_limit "string"|1|2|3|4
---@field severity_bound "string"|1|2|3|4
---@field namespace integer
---@field diag_all boolean
---@field client_id integer
---@field sort integer|boolean
---@field icon_padding boolean?

---@class fzf-lua.config.Builtin: fzf-lua.config.Base
---@field metatable table
---@field metatable_exclude table

---@class fzf-lua.config.Profiles: fzf-lua.config.Base
---@field load table

---@class fzf-lua.config.Marks: fzf-lua.config.Base
---@field sort boolean sort mark list?
---@field marks string lua pattern to filter marks

---@class fzf-lua.config.Changes: fzf-lua.config.Jumps

---@class fzf-lua.config.Jumps: fzf-lua.config.Base
---@field cmd string
---@field h1 string

---@class fzf-lua.config.Tagstack: fzf-lua.config.Base

---@class fzf-lua.config.Commands: fzf-lua.config.Base
---@field flatten table
---@field include_builtin boolean
---@field sort_lastused boolean?

---@class fzf-lua.config.Autocmds: fzf-lua.config.Base
---@field show_desc boolean

---@class fzf-lua.config.CommandHistory: fzf-lua.config.Base

---@class fzf-lua.config.SearchHistory : fzf-lua.config.CommandHistory

---@class fzf-lua.config.Registers: fzf-lua.config.Base
---@field multiline boolean
---@field ignore_empty boolean
---@field filter string

---@class fzf-lua.config.Keymaps: fzf-lua.config.Base
---@field ignore_patterns string[]
---@field show_desc boolean
---@field show_details boolean
---@field modes string[]

---@class fzf-lua.config.NvimOptions: fzf-lua.config.Base
---@field separator string
---@field color_values boolean

---@class fzf-lua.config.SpellSuggest: fzf-lua.config.Base
---@field word_pattern string

---@class fzf-lua.config.Filetypes: fzf-lua.config.Base

---@class fzf-lua.config.Packadd: fzf-lua.config.Base

---@class fzf-lua.config.Menus: fzf-lua.config.Base

---@class fzf-lua.config.TmuxBuffers: fzf-lua.config.Base
---@field cmd string

---@class fzf-lua.config.Tmux
---@field buffers fzf-lua.config.TmuxBuffers

---@class fzf-lua.config.DapBase: fzf-lua.config.Base

---@class fzf-lua.config.DapCommands: fzf-lua.config.DapBase
---@class fzf-lua.config.DapConfigurations: fzf-lua.config.DapBase
---@class fzf-lua.config.DapVariables: fzf-lua.config.DapBase
---@class fzf-lua.config.DapFrames: fzf-lua.config.DapBase
---@class fzf-lua.config.DapBreakpoints: fzf-lua.config.DapBase

---@class fzf-lua.config.Dap: fzf-lua.config.DapBase
---@field commands fzf-lua.config.DapCommands
---@field configurations fzf-lua.config.DapConfigurations
---@field variables fzf-lua.config.DapVariables
---@field frames fzf-lua.config.DapFrames
---@field breakpoints fzf-lua.config.DapBreakpoints

---@class fzf-lua.config.CompletePath: fzf-lua.config.Base
---@field cmd string?
---@field word_pattern string?
---@field _fzf_nth_devicons boolean

---@class fzf-lua.config.CompleteFile: fzf-lua.config.Base
---@field cmd string?
---@field word_pattern string?
---@field _fzf_nth_devicons boolean

---@class fzf-lua.config.CompleteLine: fzf-lua.config.Lines

---@class fzf-lua.config.CompleteBline: fzf-lua.config.Lines
---@field current_buffer_only boolean

---@class fzf-lua.config.Zoxide: fzf-lua.config.Base
---@field cmd string
---@field git_root boolean
---@field formatter string

---@class fzf-lua.config.HLS
---@field normal string
---@field border string
---@field title string
---@field title_flags string
---@field backdrop string
---@field help_normal string
---@field help_border string
---@field preview_normal string
---@field preview_border string
---@field preview_title string
---@field cursor string
---@field cursorline string
---@field cursorlinenr string
---@field search string
---@field scrollborder_e string
---@field scrollborder_f string
---@field scrollfloat_e string
---@field scrollfloat_f string
---@field header_bind string
---@field header_text string
---@field path_colnr string
---@field path_linenr string
---@field buf_name string
---@field buf_id string
---@field buf_nr string
---@field buf_linenr string
---@field buf_flag_cur string
---@field buf_flag_alt string
---@field tab_title string
---@field tab_marker string
---@field dir_icon string
---@field dir_part string
---@field file_part string
---@field live_prompt string
---@field live_sym string
---@field fzf table<string, string>

---partial types for api
---@class fzf-lua.config.Args.p: fzf-lua.config.Args, {}
---@class fzf-lua.config.Autocmds.p: fzf-lua.config.Autocmds, {}
---@class fzf-lua.config.AwesomeColorschemes.p: fzf-lua.config.AwesomeColorschemes, {}
---@class fzf-lua.config.Blines.p: fzf-lua.config.Blines, {}
---@class fzf-lua.config.Btags.p: fzf-lua.config.Btags, {}
---@class fzf-lua.config.Buffers.p: fzf-lua.config.Buffers, {}
---@class fzf-lua.config.Changes.p: fzf-lua.config.Changes, {}
---@class fzf-lua.config.Colorschemes.p: fzf-lua.config.Colorschemes, {}
-- -@class fzf-lua.config.Combine.p: fzf-lua.config.Combine, {}
---@class fzf-lua.config.CommandHistory.p: fzf-lua.config.CommandHistory, {}
---@class fzf-lua.config.Commands.p: fzf-lua.config.Commands, {}
---@class fzf-lua.config.CompleteBline.p: fzf-lua.config.CompleteBline, {}
---@class fzf-lua.config.CompleteFile.p: fzf-lua.config.CompleteFile, {}
---@class fzf-lua.config.CompleteLine.p: fzf-lua.config.CompleteLine, {}
---@class fzf-lua.config.CompletePath.p: fzf-lua.config.CompletePath, {}
---@class fzf-lua.config.DapBreakpoints.p: fzf-lua.config.DapBreakpoints, {}
---@class fzf-lua.config.DapCommands.p: fzf-lua.config.DapCommands, {}
---@class fzf-lua.config.DapConfigurations.p: fzf-lua.config.DapConfigurations, {}
---@class fzf-lua.config.DapFrames.p: fzf-lua.config.DapFrames, {}
---@class fzf-lua.config.DapVariables.p: fzf-lua.config.DapVariables, {}
-- -@class fzf-lua.config.DeregisterUiSelect.p: fzf-lua.config.DeregisterUiSelect, {}
---@class fzf-lua.config.DiagnosticsDocument.p: fzf-lua.config.Diagnostics, {}
---@class fzf-lua.config.DiagnosticsWorkspace.p: fzf-lua.config.Diagnostics, {}
---@class fzf-lua.config.Files.p: fzf-lua.config.Files, {}
---@class fzf-lua.config.Filetypes.p: fzf-lua.config.Filetypes, {}
-- -@class fzf-lua.config.FzfExec.p: fzf-lua.config.FzfExec, {}
-- -@class fzf-lua.config.FzfLive.p: fzf-lua.config.FzfLive, {}
-- -@class fzf-lua.config.FzfWrap.p: fzf-lua.config.FzfWrap, {}
---@class fzf-lua.config.GitBcommits.p: fzf-lua.config.GitBcommits, {}
---@class fzf-lua.config.GitBlame.p: fzf-lua.config.GitBlame, {}
---@class fzf-lua.config.GitBranches.p: fzf-lua.config.GitBranches, {}
---@class fzf-lua.config.GitWorktrees.p: fzf-lua.config.GitWorktrees, {}
---@class fzf-lua.config.GitCommits.p: fzf-lua.config.GitCommits, {}
---@class fzf-lua.config.GitDiff.p: fzf-lua.config.GitDiff, {}
---@class fzf-lua.config.GitFiles.p: fzf-lua.config.GitFiles, {}
---@class fzf-lua.config.GitHunks.p: fzf-lua.config.GitHunks, {}
---@class fzf-lua.config.GitStash.p: fzf-lua.config.GitStash, {}
---@class fzf-lua.config.GitStatus.p: fzf-lua.config.GitStatus, {}
---@class fzf-lua.config.GitTags.p: fzf-lua.config.GitTags, {}
---@class fzf-lua.config.Global.p: fzf-lua.config.Global, {}
---@class fzf-lua.config.Grep.p: fzf-lua.config.Grep, {}
---@class fzf-lua.config.GrepCWORD.p: fzf-lua.config.Grep, {}
---@class fzf-lua.config.GrepCurbuf.p: fzf-lua.config.GrepCurbuf, {}
---@class fzf-lua.config.GrepCword.p: fzf-lua.config.Grep, {}
---@class fzf-lua.config.GrepLast.p: fzf-lua.config.Grep, {}
---@class fzf-lua.config.GrepLoclist.p: fzf-lua.config.Grep, {}
---@class fzf-lua.config.GrepProject.p: fzf-lua.config.Grep, {}
---@class fzf-lua.config.GrepQuickfix.p: fzf-lua.config.Grep, {}
---@class fzf-lua.config.GrepVisual.p: fzf-lua.config.Grep, {}
---@class fzf-lua.config.HelpTags.p: fzf-lua.config.Helptags, {}
---@class fzf-lua.config.Highlights.p: fzf-lua.config.Highlights, {}
---@class fzf-lua.config.Jumps.p: fzf-lua.config.Jumps, {}
---@class fzf-lua.config.Keymaps.p: fzf-lua.config.Keymaps, {}
---@class fzf-lua.config.LgrepCurbuf.p: fzf-lua.config.Grep, {}
---@class fzf-lua.config.LgrepLoclist.p: fzf-lua.config.Grep, {}
---@class fzf-lua.config.LgrepQuickfix.p: fzf-lua.config.Grep, {}
---@class fzf-lua.config.Lines.p: fzf-lua.config.Lines, {}
---@class fzf-lua.config.LiveGrep.p: fzf-lua.config.Grep, {}
---@class fzf-lua.config.LiveGrepGlob.p: fzf-lua.config.Grep, {}
---@class fzf-lua.config.LiveGrepNative.p: fzf-lua.config.Grep, {}
---@class fzf-lua.config.LiveGrepResume.p: fzf-lua.config.Grep, {}
---@class fzf-lua.config.Loclist.p: fzf-lua.config.Loclist, {}
---@class fzf-lua.config.LoclistStack.p: fzf-lua.config.LoclistStack, {}
---@class fzf-lua.config.LspCodeActions.p: fzf-lua.config.LspCodeActions, {}
---@class fzf-lua.config.LspDeclarations.p: fzf-lua.config.Lsp, {}
---@class fzf-lua.config.LspDefinitions.p: fzf-lua.config.Lsp, {}
---@class fzf-lua.config.LspDocumentDiagnostics.p: fzf-lua.config.Diagnostics, {}
---@class fzf-lua.config.LspDocumentSymbols.p: fzf-lua.config.LspDocumentSymbols, {}
---@class fzf-lua.config.LspFinder.p: fzf-lua.config.LspFinder, {}
---@class fzf-lua.config.LspImplementations.p: fzf-lua.config.Lsp, {}
---@class fzf-lua.config.LspIncomingCalls.p: fzf-lua.config.Lsp, {}
---@class fzf-lua.config.LspLiveWorkspaceSymbols.p: fzf-lua.config.LspLiveWorkspaceSymbols, {}
---@class fzf-lua.config.LspOutgoingCalls.p: fzf-lua.config.Lsp, {}
---@class fzf-lua.config.LspReferences.p: fzf-lua.config.Lsp, {}
---@class fzf-lua.config.LspTypedefs.p: fzf-lua.config.Lsp, {}
---@class fzf-lua.config.LspWorkspaceDiagnostics.p: fzf-lua.config.Diagnostics, {}
---@class fzf-lua.config.LspWorkspaceSymbols.p: fzf-lua.config.LspWorkspaceSymbols, {}
---@class fzf-lua.config.ManPages.p: fzf-lua.config.Manpages, {}
---@class fzf-lua.config.Marks.p: fzf-lua.config.Marks, {}
---@class fzf-lua.config.Menus.p: fzf-lua.config.Menus, {}
---@class fzf-lua.config.NvimOptions.p: fzf-lua.config.NvimOptions, {}
---@class fzf-lua.config.Oldfiles.p: fzf-lua.config.Oldfiles, {}
---@class fzf-lua.config.Packadd.p: fzf-lua.config.Packadd, {}
---@class fzf-lua.config.Profiles.p: fzf-lua.config.Profiles, {}
---@class fzf-lua.config.Quickfix.p: fzf-lua.config.Quickfix, {}
---@class fzf-lua.config.QuickfixStack.p: fzf-lua.config.QuickfixStack, {}
-- -@class fzf-lua.config.RegisterUiSelect.p: fzf-lua.config.RegisterUiSelect, {}
---@class fzf-lua.config.Registers.p: fzf-lua.config.Registers, {}
-- -@class fzf-lua.config.Resume.p: fzf-lua.config.resume, {}
---@class fzf-lua.config.SearchHistory.p: fzf-lua.config.SearchHistory, {}
---@class fzf-lua.config.SpellSuggest.p: fzf-lua.config.SpellSuggest, {}
---@class fzf-lua.config.Spellcheck.p: fzf-lua.config.Spellcheck, {}
---@class fzf-lua.config.Tabs.p: fzf-lua.config.Tabs, {}
---@class fzf-lua.config.Tags.p: fzf-lua.config.Tags, {}
---@class fzf-lua.config.TagsGrep.p: fzf-lua.config.TagsGrep, {}
---@class fzf-lua.config.TagsGrepCWORD.p: fzf-lua.config.TagsGrep, {}
---@class fzf-lua.config.TagsGrepCword.p: fzf-lua.config.TagsGrep, {}
---@class fzf-lua.config.TagsGrepVisual.p: fzf-lua.config.TagsGrep, {}
---@class fzf-lua.config.TagsLiveGrep.p: fzf-lua.config.TagsGrep, {}
---@class fzf-lua.config.Tagstack.p: fzf-lua.config.Tagstack, {}
---@class fzf-lua.config.TmuxBuffers.p: fzf-lua.config.TmuxBuffers, {}
---@class fzf-lua.config.Treesitter.p: fzf-lua.config.Treesitter, {}
---@class fzf-lua.config.Zoxide.p: fzf-lua.config.Zoxide, {}
