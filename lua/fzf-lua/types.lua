---@meta
error("Cannot require a meta file")

---@class fzf-lua
local FzfLua = require("fzf-lua")

---@class fzf-lua.path.Entry
---@field stripped? string
---@field path? string
---@field bufnr? integer
---@field line? integer 1-based
---@field col? integer 1-based
---@field bufname? string
---@field terminal? boolean
---@field ctag? string
---@field uri? string
---@field range? lsp.Range
---@field title? string
---@field hlgroup? any
---@field debug? string debug information
---@field extmarks? table

---@class fzf-lua.cmd.Entry
---@field cmd string[] cmd used to generated content
---@field cmd_stream? boolean stream process cmd content
---@field cmd_opts? vim.SystemOpts vim.system opts for cmd

---@class fzf-lua.buffer_or_file.Entry : fzf-lua.path.Entry, fzf-lua.cmd.Entry,{}
---@field do_not_cache? boolean
---@field no_scrollbar? boolean
---@field tick? integer
---@field no_syntax? boolean
---@field cached? fzf-lua.buffer_or_file.Bcache
---@field filetype? string
---@field content? (string|fzf-lua.line)[]
---@field end_line? integer 1-based
---@field end_col? integer 1-based
---@field open_term? boolean open_term for content (cmd always open_term)

---@class fzf-lua.keymap.Entry
---@field vmap string?
---@field mode string?
---@field key string?

---@class fzf-lua.buffer_or_file.Bcache
---@field bufnr integer
---@field min_winopts? boolean
---@field invalid? boolean buffer content changed
---@field tick? integer

---@alias fzf-lua.config.Action fzf-lua.ActionSpec|fzf-lua.shell.data2|fzf-lua.shell.data2[]|false
---@alias fzf-lua.config.Actions { [1]?: boolean, [string]: fzf-lua.config.Action }

---@class fzf-lua.ActionSpec
---@field [1] fzf-lua.shell.data2?
---@field fn? fzf-lua.shell.data2?
---@field exec_silent? boolean
---@field reload? boolean
---@field field_index? string
---@field desc? string
---@field prefix? string
---@field postfix? string
---@field reuse? boolean
---@field noclose? boolean
---@field _ignore? boolean

---@alias fzf-lua.profile "border-fused"|"borderless-full"|"borderless"|"cli"|"default-prompt"|"default-title"|"default"|"fzf-native"|"fzf-tmux"|"fzf-vim"|"hide"|"ivy"|"max-perf"|"skim"|"telescope"

---@class fzf-lua.Config: fzf-lua.config.Defaults,{}
---@field [1]? fzf-lua.profile|fzf-lua.profile[]
---@field [2]? boolean|integer
---@field defaults fzf-lua.config.Defaults|{}

---@class fzf-lua.SpawnStdioOpts
---@field debug? boolean
---@field profiler? boolean
---@field process1? boolean
---@field silent? boolean|integer
---@field cmd? string|string[]
---@field cwd? string
---@field cwd_only? boolean
---@field stdout? boolean
---@field stderr? boolean
---@field stderr_to_stdout? boolean
---@field formatter? fun(line:string):string|nil
---@field multiline? boolean
---@field git_dir? string
---@field git_worktree? string
---@field git_icons? boolean
---@field file_icons? boolean
---@field color_icons? boolean
---@field path_shorten? boolean
---@field absolute_path? boolean
---@field strip_cwd_prefix? boolean
---@field render_crlf? boolean
---@field exec_empty_query? boolean
---@field file_ignore_patterns? string[]
---@field rg_glob? boolean
---@field fn_transform? string|fun(line:string, opts: fzf-lua.SpawnStdioOpts):string|nil
---@field fn_preprocess? string|fun(opts: fzf-lua.SpawnStdioOpts):string[]|nil
---@field fn_postprocess? string|fun(opts: fzf-lua.SpawnStdioOpts):string[]|nil
---@field is_live? boolean
---@field contents? fzf-lua.content|fzf-lua.shell.data2
---@field __FZF_VERSION? string
---@field glob_flag? string
---@field glob_separator? string
---@field g? fzf-lua.SpawnStdioOpts.g
---@field no_ansi_colors? boolean

---@class fzf-lua.SpawnStdioOpts.g
---@field _fzf_lua_server? string
---@field _EOL? string
---@field _debug? boolean

---a basic config can be used by fzf_exec?
---generated from the result of `:=FzfLua.config.normalize_opts({}, {})`
---@class fzf-lua.config.Base
---@field dir_icon? string
---@field enrich? fun(opts: fzf-lua.config.Resolved|{}):fzf-lua.config.Resolved|{}
---Path to fzf binary. By default uses fzf found in `$PATH`.
---@field fzf_bin? string
---Fzf `--color` flag configuration passed to the fzf binary, set `[1]=true` to inherit terminal colorscheme, consult `man fzf` for all available options.
---@field fzf_colors? { [1]?: boolean, [string]: string? }
---Fzf command-line options passed to fzf binary as key-value pairs, consult `man fzf` for all available options. For example `fzf_opts = { ["--layout"] = "reverse-list" }`.
---@field fzf_opts? table<string, any>
---Options passed to the fzf-tmux wrapper, e.g. `{ ["-p"] = "80%,80%" }`.
---@field fzf_tmux_opts table<string, any>
---Highlight groups configuration, consult `:FzfLua profiles` and select `default` for the default values.
---@field hls fzf-lua.config.HLS
---@field winopts? fzf-lua.config.Winopts|(fun(opts: fzf-lua.config.Resolved):fzf-lua.config.Winopts)
---@field keymap? fzf-lua.config.Keymap|(fun(opts: fzf-lua.config.Resolved):fzf-lua.config.Keymap)
---@field actions? fzf-lua.config.Actions|(fun(opts: fzf-lua.config.Resolved):fzf-lua.config.Actions)
---Disable interactive action headers.
---@field no_header_i? boolean
---Fzf prompt, passed to fzf as `--prompt` flag.
---@field prompt? string
---Sets the current working directory.
---@field cwd? string
---Use the multiprocess shell wrapper for async file generation, improves performance for large file sets.
---@field multiprocess? integer|boolean
---Transform function for each entry, can be a function or a string that returns a function.
---@field fn_transform? boolean|string|function
---Preprocess function called before command execution.
---@field fn_preprocess? boolean|string|function
---Postprocess function called after command execution.
---@field fn_postprocess? boolean|string|function
---If available, display file icons. Set to `true` will attempt to use "nvim-web-devicons" and fallback to "mini.icons", other possible values are `devicons` or `mini` which force loading a specific icons plugin, for example: `:FzfLua files file_icons=mini` or `:lua require("fzf-lua").files({ file_icons = "devicons" })`.
---@field file_icons? boolean|integer|string
---Add coloring of file|git icons.
---@field color_icons? boolean
---If inside a git-repo add git status indicator icons e.g. `M` for modified files.
---@field git_icons? boolean
---Do not display any messages or warnings.
---@field silent? boolean|integer
---Previewer override, set to `false` to disable the previewer. By default files pickers use the "builtin" previewer, possible values for file pickers `bat|cat|head`. Other overrides include: `:FzfLua helptags previewer=help_native` or `:FzfLua manpages previewer=man_native`.
---@field previewer? fzf-lua.config.Previewer|string|false
---Fzf native preview command, can be a string, function or table.
---@field preview? string|function|table
---@field complete? (fun(s: string[], _o: fzf-lua.config.Resolved, l: string, c: integer):string?, integer?)|boolean
---Header line, set to any string to display a header line, set to `false` to disable fzf-lua interactive headers (e.g. "ctrl-g to disable .gitignore", etc), passed to fzf as `--header` flag.
---@field header? string|false
---Initial query (prompt text), passed to fzf as `--query` flag.
---@field query? string
---Resume last search for the picker, recall last query, selected items, etc.
---@field resume? boolean
---Disable resuming for the current picker.
---@field no_resume? boolean
---Disable "hide" profile for the picker, process will be terminated on abort/accept.
---@field no_hide? boolean
---Apply a profile on top of the current configuration, can be a string or table.
---@field profile? string|table
---Do not display an error message when the provider command fails.
---@field silent_fail? boolean
---@field rg_glob? boolean|integer
---@field headers? string[]
---@field header_prefix? string
---@field header_separator? string
---@field fn_selected function
---@field cb_co fun(co: thread)
---Limit results to files in the current working directory only.
---@field cwd_only boolean
---@field cmd? string
---Enable debug mode (output debug prints).
---@field debug? boolean|integer|'v'|'verbose'
---Preview offset expression passed to fzf `--preview-window`, consult `man fzf` for more info.
---@field preview_offset? string
---Enable rendering CRLF (`\r\n`) in entries.
---@field render_crlf? boolean
---Custom path formatter, can be defined under `setup.formatters`, fzf-lua comes with a builtin vscode-like formatter, displaying the filename first followed by the folder. Try it out with `:FzfLua files formatter=path.filename_first` or `:FzfLua live_grep formatter=path.filename_first`. For permanency: `require("fzf-lua").setup({ files = { formatter = "path.filename_first" } })`.
---@field formatter? string
---@field _fzf_cli_args? string[]
---@field __INFO fzf-lua.Info
---@field __CTX fzf-lua.Ctx
---@field _normalized? boolean
---@field __call_fn function
---@field __call_opts table
---@field is_live? boolean
---@field contents? fzf-lua.content|fzf-lua.shell.data2
---@field _actions? fun():fzf-lua.config.Actions?
---@field __ACT_TO? function
---@field _start? boolean
---@field _treesitter? (fun(line: string):string?,string?,string?,string?)|boolean?
---@field help_open_win? fun(buf: integer, enter: boolean, config: vim.api.keyset.win_config): integer
---Auto close fzf-lua interface when a terminal is opened, set to `false` to keep the interface open.
---@field autoclose? boolean
---@field line_field_index? string
---@field field_index_expr? string
---@field _ctag? string
---Pager command for shell preview commands (e.g. `delta`).
---@field preview_pager? string
---@field toggle_flag? string
---@field _fzf_nth_devicons? boolean
---@field _headers? boolean

---@class fzf-lua.config.Resolved: fzf-lua.config.Base
---@field PidObject? table
---@field _headers? string[]
---@field _fmt? table
---@field pipe_cmd? string
---@field RIPGREP_CONFIG_PATH? string
---@field _ctx? fzf-lua.Ctx
---@field __FZF_VERSION? number[]
---@field __resume_key? function|string
---@field _cwd? string
---@field _type? "file"?
---@field _cached_hls? string[]
---@field _multiline? boolean
---@field __resume_set? function
---@field __resume_get? function
---@field _contents? string
---@field _is_fzf_tmux? boolean
---@field __stringified? boolean
---@field __stringify_cmd? boolean
---@field __sigwinches? string[]
---@field __sigwinch_on_scope table<string, function>
---@field __sigwinch_on_any function[]
---@field process1? boolean
---@field profiler? boolean
---@field use_queue? boolean
---@field throttle? boolean
---@field env? boolean
---@field winopts fzf-lua.config.WinoptsResolved
---@field actions fzf-lua.config.Actions
---@field keymap fzf-lua.config.Keymap
---@field fzf_opts table<string, any>
---@field _resume_reload? boolean|function
---@field _fzf_cli_args string[]
---@field _uri? boolean

---GENERATED from `make gen`

FzfLua.win = require("fzf-lua.win")
FzfLua.core = require("fzf-lua.core")
FzfLua.path = require("fzf-lua.path")
FzfLua.utils = require("fzf-lua.utils")
FzfLua.libuv = require("fzf-lua.libuv")
FzfLua.shell = require("fzf-lua.shell")
FzfLua.config = require("fzf-lua.config")
FzfLua.actions = require("fzf-lua.actions")
FzfLua.make_entry = require("fzf-lua.make_entry")

FzfLua.args = require("fzf-lua.providers.files").args
FzfLua.autocmds = require("fzf-lua.providers.nvim").autocmds
FzfLua.awesome_colorschemes = require("fzf-lua.providers.colorschemes").awesome_colorschemes
FzfLua.blines = require("fzf-lua.providers.buffers").blines
FzfLua.btags = require("fzf-lua.providers.tags").btags
FzfLua.buffers = require("fzf-lua.providers.buffers").buffers
FzfLua.changes = require("fzf-lua.providers.nvim").changes
FzfLua.colorschemes = require("fzf-lua.providers.colorschemes").colorschemes
FzfLua.combine = require("fzf-lua.providers.meta").combine
FzfLua.command_history = require("fzf-lua.providers.nvim").command_history
FzfLua.commands = require("fzf-lua.providers.nvim").commands
FzfLua.complete_bline = require("fzf-lua.complete").bline
FzfLua.complete_file = require("fzf-lua.complete").file
FzfLua.complete_line = require("fzf-lua.complete").line
FzfLua.complete_path = require("fzf-lua.complete").path
FzfLua.dap_breakpoints = require("fzf-lua.providers.dap").breakpoints
FzfLua.dap_commands = require("fzf-lua.providers.dap").commands
FzfLua.dap_configurations = require("fzf-lua.providers.dap").configurations
FzfLua.dap_frames = require("fzf-lua.providers.dap").frames
FzfLua.dap_variables = require("fzf-lua.providers.dap").variables
FzfLua.deregister_ui_select = require("fzf-lua.providers.ui_select").deregister
FzfLua.diagnostics_document = require("fzf-lua.providers.diagnostic").diagnostics
FzfLua.diagnostics_workspace = require("fzf-lua.providers.diagnostic").all
FzfLua.files = require("fzf-lua.providers.files").files
FzfLua.filetypes = require("fzf-lua.providers.nvim").filetypes
FzfLua.fzf_exec = require("fzf-lua.core").fzf_exec
FzfLua.fzf_live = require("fzf-lua.core").fzf_live
FzfLua.fzf_wrap = require("fzf-lua.core").fzf_wrap
FzfLua.git_bcommits = require("fzf-lua.providers.git").bcommits
FzfLua.git_blame = require("fzf-lua.providers.git").blame
FzfLua.git_branches = require("fzf-lua.providers.git").branches
FzfLua.git_commits = require("fzf-lua.providers.git").commits
FzfLua.git_diff = require("fzf-lua.providers.git").diff
FzfLua.git_files = require("fzf-lua.providers.git").files
FzfLua.git_hunks = require("fzf-lua.providers.git").hunks
FzfLua.git_stash = require("fzf-lua.providers.git").stash
FzfLua.git_status = require("fzf-lua.providers.git").status
FzfLua.git_tags = require("fzf-lua.providers.git").tags
FzfLua.git_worktrees = require("fzf-lua.providers.git").worktrees
FzfLua.global = require("fzf-lua.providers.meta").global
FzfLua.grep = require("fzf-lua.providers.grep").grep
FzfLua.grep_cWORD = require("fzf-lua.providers.grep").grep_cWORD
FzfLua.grep_curbuf = require("fzf-lua.providers.grep").grep_curbuf
FzfLua.grep_cword = require("fzf-lua.providers.grep").grep_cword
FzfLua.grep_last = require("fzf-lua.providers.grep").grep_last
FzfLua.grep_loclist = require("fzf-lua.providers.grep").grep_loclist
FzfLua.grep_project = require("fzf-lua.providers.grep").grep_project
FzfLua.grep_quickfix = require("fzf-lua.providers.grep").grep_quickfix
FzfLua.grep_visual = require("fzf-lua.providers.grep").grep_visual
FzfLua.help_tags = require("fzf-lua.providers.helptags").helptags
FzfLua.helptags = require("fzf-lua.providers.helptags").helptags
FzfLua.highlights = require("fzf-lua.providers.colorschemes").highlights
FzfLua.jumps = require("fzf-lua.providers.nvim").jumps
FzfLua.keymaps = require("fzf-lua.providers.nvim").keymaps
FzfLua.lgrep_curbuf = require("fzf-lua.providers.grep").lgrep_curbuf
FzfLua.lgrep_loclist = require("fzf-lua.providers.grep").lgrep_loclist
FzfLua.lgrep_quickfix = require("fzf-lua.providers.grep").lgrep_quickfix
FzfLua.lines = require("fzf-lua.providers.buffers").lines
FzfLua.live_grep = require("fzf-lua.providers.grep").live_grep
FzfLua.live_grep_glob = require("fzf-lua.providers.grep").live_grep_glob
FzfLua.live_grep_native = require("fzf-lua.providers.grep").live_grep_native
FzfLua.live_grep_resume = require("fzf-lua.providers.grep").live_grep_resume
FzfLua.loclist = require("fzf-lua.providers.quickfix").loclist
FzfLua.loclist_stack = require("fzf-lua.providers.quickfix").loclist_stack
FzfLua.lsp_code_actions = require("fzf-lua.providers.lsp").code_actions
FzfLua.lsp_declarations = require("fzf-lua.providers.lsp").declarations
FzfLua.lsp_definitions = require("fzf-lua.providers.lsp").definitions
FzfLua.lsp_document_diagnostics = require("fzf-lua.providers.diagnostic").diagnostics
FzfLua.lsp_document_symbols = require("fzf-lua.providers.lsp").document_symbols
FzfLua.lsp_finder = require("fzf-lua.providers.lsp").finder
FzfLua.lsp_implementations = require("fzf-lua.providers.lsp").implementations
FzfLua.lsp_incoming_calls = require("fzf-lua.providers.lsp").incoming_calls
FzfLua.lsp_live_workspace_symbols = require("fzf-lua.providers.lsp").live_workspace_symbols
FzfLua.lsp_outgoing_calls = require("fzf-lua.providers.lsp").outgoing_calls
FzfLua.lsp_references = require("fzf-lua.providers.lsp").references
FzfLua.lsp_type_sub = require("fzf-lua.providers.lsp").type_sub
FzfLua.lsp_type_super = require("fzf-lua.providers.lsp").type_super
FzfLua.lsp_typedefs = require("fzf-lua.providers.lsp").typedefs
FzfLua.lsp_workspace_diagnostics = require("fzf-lua.providers.diagnostic").all
FzfLua.lsp_workspace_symbols = require("fzf-lua.providers.lsp").workspace_symbols
FzfLua.man_pages = require("fzf-lua.providers.manpages").manpages
FzfLua.manpages = require("fzf-lua.providers.manpages").manpages
FzfLua.marks = require("fzf-lua.providers.nvim").marks
FzfLua.menus = require("fzf-lua.providers.nvim").menus
FzfLua.nvim_options = require("fzf-lua.providers.nvim").nvim_options
FzfLua.oldfiles = require("fzf-lua.providers.oldfiles").oldfiles
FzfLua.history = require("fzf-lua.providers.oldfiles").history
FzfLua.packadd = require("fzf-lua.providers.nvim").packadd
FzfLua.profiles = require("fzf-lua.providers.meta").profiles
FzfLua.quickfix = require("fzf-lua.providers.quickfix").quickfix
FzfLua.quickfix_stack = require("fzf-lua.providers.quickfix").quickfix_stack
FzfLua.register_ui_select = require("fzf-lua.providers.ui_select").register
FzfLua.registers = require("fzf-lua.providers.nvim").registers
FzfLua.resume = require("fzf-lua.core").fzf_resume
FzfLua.search_history = require("fzf-lua.providers.nvim").search_history
FzfLua.serverlist = require("fzf-lua.providers.nvim").serverlist
FzfLua.spell_suggest = require("fzf-lua.providers.nvim").spell_suggest
FzfLua.spellcheck = require("fzf-lua.providers.buffers").spellcheck
FzfLua.tabs = require("fzf-lua.providers.buffers").tabs
FzfLua.tags = require("fzf-lua.providers.tags").tags
FzfLua.tags_grep = require("fzf-lua.providers.tags").grep
FzfLua.tags_grep_cWORD = require("fzf-lua.providers.tags").grep_cWORD
FzfLua.tags_grep_cword = require("fzf-lua.providers.tags").grep_cword
FzfLua.tags_grep_visual = require("fzf-lua.providers.tags").grep_visual
FzfLua.tags_live_grep = require("fzf-lua.providers.tags").live_grep
FzfLua.tagstack = require("fzf-lua.providers.nvim").tagstack
FzfLua.tmux_buffers = require("fzf-lua.providers.tmux").buffers
FzfLua.treesitter = require("fzf-lua.providers.buffers").treesitter
FzfLua.undotree = require("fzf-lua.providers.undotree").undotree
FzfLua.zoxide = require("fzf-lua.providers.files").zoxide

---@class fzf-lua.win.api: fzf-lua.Win
---@field set_autoclose fun(autoclose: vim.NIL), any
---@field autoclose fun(): any
---@field win_leave fun(): nil
---@field hide fun(): nil
---@field unhide fun(): true?
---@field toggle_fullscreen fun(): nil
---@field focus_preview fun(): nil
---@field toggle_preview fun(): nil
---@field toggle_preview_wrap fun(): nil
---@field toggle_preview_cw fun(direction: integer), nil
---@field toggle_preview_behavior fun(): nil
---@field toggle_preview_ts_ctx fun(): nil
---@field toggle_preview_undo_diff fun(): nil
---@field preview_ts_ctx_inc_dec fun(num: integer), nil
---@field preview_scroll fun(direction: fzf-lua.win.direction), nil
---@field close_help fun(): nil
---@field toggle_help fun(): nil
