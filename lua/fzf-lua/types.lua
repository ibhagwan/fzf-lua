---@meta
error("Cannot require a meta file")

---@class fzf-lua
_G.FzfLua = require("fzf-lua")

---@class fzf-lua.path.Entry
---@field stripped? string
---@field path? string
---@field bufnr? integer
---@field line? integer
---@field col? integer
---@field bufname? string
---@field terminal? boolean
---@field ctag? string
---@field uri? string
---@field range? lsp.Range
---@field debug? string debug information

---@class fzf-lua.buffer_or_file.Entry : fzf-lua.path.Entry,{}
---@field do_not_cache? boolean
---@field no_scrollbar? boolean
---@field tick? integer
---@field no_syntax? boolean
---@field cached? fzf-lua.buffer_or_file.Bcache
---@field content? string[]
---@field filetype? string

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
---@field fzf_bin? string
---@field fzf_colors? { [1]?: boolean, [string]: string? }
---@field fzf_opts? table<string, any>
---@field fzf_tmux_opts table<string, any>
---@field hls fzf-lua.config.HLS
---@field winopts? fzf-lua.config.Winopts|(fun(opts: fzf-lua.config.Resolved):fzf-lua.config.Winopts)
---@field keymap? fzf-lua.config.Keymap|(fun(opts: fzf-lua.config.Resolved):fzf-lua.config.Keymap)
---@field actions? fzf-lua.config.Actions|(fun(opts: fzf-lua.config.Resolved):fzf-lua.config.Actions)
---@field no_header? boolean
---@field no_header_i? boolean
---@field prompt? string
---@field cwd? string
---@field multiprocess? integer|boolean
---@field fn_transform? boolean|string|function
---@field fn_preprocess? boolean|string|function
---@field fn_postprocess? boolean|string|function
---@field file_icons? boolean|integer
---@field color_icons? boolean
---@field git_icons? boolean
---@field silent? boolean|integer
---@field previewer? fzf-lua.config.Previewer|string
---@field preview? string|function|table
---@field complete? (fun(s: string[], _o: fzf-lua.config.Resolved, l: string, c: integer):string?, integer?)|boolean
---@field header string
---@field query? string
---@field resume? boolean
---@field no_resume? boolean
---@field no_hide? boolean
---@field profile? string|table
---@field silent_fail? boolean
---@field rg_glob? boolean|integer
---@field headers? string[]
---@field header_prefix? string
---@field header_separator? string
---@field fn_selected function
---@field cb_co fun(co: thread)
---@field cwd_only boolean
---@field cmd? string
---@field debug? boolean|integer|'v'|'verbose'
---@field preview_offset? string
---@field _fzf_cli_args? string[]
---@field __INFO fzf-lua.Info
---@field __CTX fzf-lua.Ctx
---@field _normalized? boolean
---@field __call_fn function
---@field __call_opts table
---@field is_live? boolean is "live" picker
---@field contents? fzf-lua.content|fzf-lua.shell.data2
---@field _actions? fun():fzf-lua.config.Actions?
---@field __ACT_TO? function
---@field _start? boolean
---@field _is_skim? boolean
---@field _treesitter? (fun(line: string):string?,string?,string?,string?)|boolean?
---@field help_open_win? fun(buf: integer, enter: boolean, config: vim.api.keyset.win_config): integer
---@field autoclose? boolean
---@field line_field_index? string
---@field field_index_expr? string
---@field _ctag? string
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
---@field _is_skim? boolean
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
---@field _resume_reload? boolean
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
