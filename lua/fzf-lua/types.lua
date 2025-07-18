---@meta
error("Cannot require a meta file")

_G.FzfLua = require("fzf-lua")

---@class fzf-lua.Config
---@field [string] any

---@class fzf-lua.previewer
---@field new function
---@field zero function?
---@field cmdline function?
---@field fzf_delimiter function?
---@field preview_window function?
---@field _preview_offset function?

---@class fzf-lua.previewer.Builtin
---@field type "builtin"
---@field opts table
---@field win fzf-lua.Win
---@field delay integer
---@field title string?
---@field title_pos string?
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
---
---@field orig_pos fzf-lua.previewer.CursorPos
---@alias fzf-lua.previewer.CursorPos (true|[integer, integer])

---@class fzf-lua.previewer.BufferOrFile
---@field match_id integer?
---@field clear_on_redraw boolean?

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
