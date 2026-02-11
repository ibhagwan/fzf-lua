---@diagnostic disable: missing-fields
local path = require "fzf-lua.path"
local utils = require "fzf-lua.utils"
local actions = require "fzf-lua.actions"
local previewers = require "fzf-lua.previewer"
local M = {}

function M._default_previewer_fn()
  local winopts = M.globals.winopts
  if type(winopts) == "function" then
    winopts = winopts() or {}
    winopts.preview = type(winopts.preview) == "table" and winopts.preview or {}
    winopts.preview.default = winopts.preview.default or M.defaults.winopts.preview.default
  end
  local previewer = M.globals.default_previewer or winopts.preview.default
  -- the setup function cannot have a custom previewer as deepcopy
  -- fails with stack overflow while trying to copy the custom class
  -- the workaround is to define the previewer as a function instead
  -- https://github.com/ibhagwan/fzf-lua/issues/677
  return type(previewer) == "function" and previewer() or previewer
end

function M._preview_pager_fn()
  return vim.fn.executable("delta") == 1 and
      ("delta --width=%s --%s"):format(utils._if_win_normalize_vars("$COLUMNS"), vim.o.bg) or
      nil
end

function M._man_cmd_fn(bat_pager)
  local cmd = utils.is_darwin() and "man -P cat"
      or vim.fn.executable("mandb") == 1 and "man"
      or "man -c"
  local bat_cmd = bat_pager and (function()
    for _, bin in ipairs({ "batcat", "bat" }) do
      if vim.fn.executable(bin) == 1 then
        return string.format("%s --color=always -p -l man", bin)
      end
    end
  end)()
  local pager = bat_cmd or "col -bx"
  return string.format("%s %%s 2>/dev/null | %s", cmd, pager)
end

---@class fzf-lua.config.TreesitterWinopts
---@field enabled boolean Enable treesitter highlighting in fzf main window.
---@field fzf_colors? table<string, string> Treesitter fzf color overrides.

---@class fzf-lua.config.Winopts: vim.api.keyset.win_config
---Height of the fzf-lua float, between 0-1 will represent percentage of `vim.o.lines` (1: max height), if >= 1 will use fixed number of lines.
---@field height? number
---Width of the fzf-lua float, between 0-1 will represent percentage of `vim.o.columns` (1: max width), if >= 1 will use fixed number of columns.
---@field width? number
---Screen row where to place the fzf-lua float window, between 0-1 will represent percentage of `vim.o.lines` (0: top, 1: bottom), if >= 1 will attempt to place the float in the exact screen line.
---@field row? number
---Screen column where to place the fzf-lua float window, between 0-1 will represent percentage of `vim.o.columns` (0: leftmost, 1: rightmost), if >= 1 will attempt to place the float in the exact screen column.
---@field col? number
---Border of the fzf-lua float, possible values are `none|single|double|rounded|thicc|thiccc|thicccc` or a custom border character array passed as is to `nvim_open_win`.
---@field border? string|table
---Controls title display in the fzf window, set by the calling picker.
---@field title? string
---Controls title display in the fzf window, possible values are `left|right|center`.
---@field title_pos? string
---Set to `false` to disable fzf window title flags (hidden, ignore, etc).
---@field title_flags? boolean
---Preview window configuration.
---@field preview? fzf-lua.config.PreviewOpts
---Neovim split command to use for fzf-lua interface, e.g `belowright new`.
---@field split? string|function|false
---Backdrop opacity value, 0 for fully opaque, 100 for fully transparent (i.e. disabled).
---@field backdrop? number|boolean
---Use fullscreen for the fzf-lua floating window.
---@field fullscreen? boolean
---Use treesitter highlighting in fzf's main window. NOTE: Only works for file-like entries where treesitter parser exists and is loaded for the filetype.
---@field treesitter? fzf-lua.config.TreesitterWinopts|boolean
---Callback after the creation of the fzf-lua main terminal window.
---@field on_create? fun(e: { winid?: integer, bufnr?: integer })
---Callback after closing the fzf-lua window.
---@field on_close? fun()
---Toggle behavior for fzf-lua window.
---@field toggle_behavior? string
---Enable window transparency.
---@field winblend? boolean
---Enable window highlight groups.
---@field winhl? boolean
---Highlight the current line in main window.
---@field cursorline? boolean
---Internal window highlight mappings.
---@field __winhls? { main: [string, string?][], prev: [string, string?][] }

---@class fzf-lua.config.PreviewOpts
---Default previewer for file pickers, possible values `builtin|bat|cat|head`.
---@field default? string
---Preview border for native fzf previewers (i.e. `bat`, `git_status`), set to `noborder` to hide the preview border, consult `man fzf` for all available options.
---@field border? any
---Line wrap in both native fzf and the builtin previewer, mapped to fzf's `--preview-window:[no]wrap` flag.
---@field wrap? boolean
---Preview startup visibility in both native fzf and the builtin previewer, mapped to fzf's `--preview-window:[no]hidden` flag. NOTE: this is different than setting `previewer=false` which disables the previewer altogether with no toggle ability.
---@field hidden? boolean
---Vertical preview layout, mapped to fzf's `--preview-window:...` flag. Requires `winopts.preview.layout={vertical|flex}`.
---@field vertical? string
---Horizontal preview layout, mapped to fzf's `--preview-window:...` flag. Requires `winopts.preview.layout={horizontal|flex}`.
---@field horizontal? string
---Preview layout, possible values are `horizontal|vertical|flex`, when set to `flex` fzf window width is tested against `winopts.preview.flip_columns`, when <= `vertical` is used, otherwise `horizontal`.
---@field layout? string
---Auto-detect the preview layout based on available width, see note in `winopts.preview.layout`.
---@field flip_columns? integer
---Controls title display in the builtin previewer.
---@field title? boolean
---Controls title display in the builtin previewer, possible values are `left|right|center`.
---@field title_pos? "center"|"left"|"right"
---Scrollbar style in the builtin previewer, set to `false` to disable, possible values are `float|border`.
---@field scrollbar? string|boolean
---Float style scrollbar offset from the right edge of the preview window. Requires `winopts.preview.scrollbar=float`.
---@field scrolloff? integer
---Debounce time (milliseconds) for displaying the preview buffer in the builtin previewer.
---@field delay? integer
---@field winopts fzf-lua.config.PreviewerWinopts Window options for the builtin previewer.
---(skim only option), allow preview process run in pty
---@field pty? boolean

---missing fields are injected later, not sure how to tell luals about it
---@class fzf-lua.config.Defaults: fzf-lua.config.Base,{}
---@field nbsp string Special invisible unicode character used as text delimiter.
---@field winopts fzf-lua.config.Winopts Window options.
---@field keymap fzf-lua.config.Keymap Keymaps for builtin and fzf commands.
---@field actions table<string, fzf-lua.config.Actions> Actions to execute on selected items.
---@field fzf_bin string? Path to fzf binary.
---@field previewers fzf-lua.config.Previewers Previewer configurations.
---@field formatters table<string, any>
---@field file_icon_padding string Padding after file icons.
---@field dir_icon string Directory icon to display in front of directory entries.
---@field __HLS fzf-lua.config.HLS Highlight group configuration.
---@field [string] any
M.defaults        = {
  nbsp          = utils.nbsp,
  winopts       = {
    height     = 0.85,
    width      = 0.80,
    row        = 0.35,
    col        = 0.55,
    border     = "rounded",
    zindex     = 50,
    backdrop   = 60,
    fullscreen = false,
    title_pos  = "center",
    treesitter = {
      enabled    = utils.__HAS_NVIM_010,
      fzf_colors = { ["hl"] = "-1:reverse", ["hl+"] = "-1:reverse" }
    },
    preview    = {
      default      = "builtin",
      border       = "rounded",
      wrap         = false,
      hidden       = false,
      vertical     = "down:45%",
      horizontal   = "right:60%",
      layout       = "flex",
      flip_columns = 100,
      title        = true,
      title_pos    = "center",
      scrollbar    = "border",
      scrolloff    = -1,
      -- default preview delay, fzf native previewers has a 100ms delay:
      -- https://github.com/junegunn/fzf/issues/2417#issuecomment-809886535
      delay        = 20,
      ---@class fzf-lua.config.PreviewerWinopts
      ---Builtin previewer buffer local option, see `:help 'number'`.
      ---@field number boolean
      ---Builtin previewer buffer local option, see `:help 'relativenumber'`.
      ---@field relativenumber boolean
      ---Builtin previewer buffer local option, see `:help 'cursorline'`.
      ---@field cursorline boolean
      ---Builtin previewer buffer local option, see `:help 'cursorlineopt'`.
      ---@field cursorlineopt string
      ---Builtin previewer buffer local option, see `:help 'cursorcolumn'`.
      ---@field cursorcolumn boolean
      ---Builtin previewer buffer local option, see `:help 'signcolumn'`.
      ---@field signcolumn string
      ---Builtin previewer buffer local option, see `:help 'list'`.
      ---@field list boolean
      ---Builtin previewer buffer local option, see `:help 'foldenable'`.
      ---@field foldenable boolean
      ---Builtin previewer buffer local option, see `:help 'foldmethod'`.
      ---@field foldmethod string
      ---Builtin previewer buffer local option, see `:help 'scrolloff'`.
      ---@field scrolloff integer
      ---Builtin previewer window transparency, see `:help 'winblend'`.
      ---@field winblend integer
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
        scrolloff      = 0,
      },
    },
    -- on_create  = function(_)
    --   vim.cmd("set winhl=Normal:Normal,FloatBorder:Normal")
    --   utils.keymap_set("t", "<A-Esc>", actions.hide, { nowait = true, buffer = e.bufnr })
    -- end,
  },
  ---@class fzf-lua.config.Keymap
  ---@field builtin? table<string, string> Keybinds for builtin (Neovim) commands.
  ---@field fzf? table<string, string> Keybinds for fzf commands.
  keymap        = {
    builtin = {
      ["<M-Esc>"]    = "hide",
      ["<F1>"]       = "toggle-help",
      ["<F2>"]       = "toggle-fullscreen",
      -- Only valid with the 'builtin' previewer
      ["<F3>"]       = "toggle-preview-wrap",
      ["<F4>"]       = "toggle-preview",
      ["<F5>"]       = "toggle-preview-cw",
      ["<F6>"]       = "toggle-preview-behavior",
      ["<F7>"]       = "toggle-preview-ts-ctx",
      ["<F8>"]       = "preview-ts-ctx-dec",
      ["<F9>"]       = "preview-ts-ctx-inc",
      ["<S-Left>"]   = "preview-reset",
      ["<S-down>"]   = "preview-page-down",
      ["<S-up>"]     = "preview-page-up",
      ["<M-S-down>"] = "preview-down",
      ["<M-S-up>"]   = "preview-up",
    },
    fzf = {
      ["ctrl-z"]         = "abort",
      ["ctrl-u"]         = "unix-line-discard",
      ["ctrl-f"]         = "half-page-down",
      ["ctrl-b"]         = "half-page-up",
      ["ctrl-a"]         = "beginning-of-line",
      ["ctrl-e"]         = "end-of-line",
      ["alt-a"]          = "toggle-all",
      ["alt-g"]          = "first",
      ["alt-G"]          = "last",
      -- Only valid with fzf previewers (bat/cat/git/etc)
      ["f3"]             = "toggle-preview-wrap",
      ["f4"]             = "toggle-preview",
      ["shift-down"]     = "preview-page-down",
      ["shift-up"]       = "preview-page-up",
      ["alt-shift-down"] = "preview-down",
      ["alt-shift-up"]   = "preview-up",
    },
  },
  actions       = {
    files = {
      ["enter"]  = actions.file_edit_or_qf,
      ["ctrl-s"] = actions.file_split,
      ["ctrl-v"] = actions.file_vsplit,
      ["ctrl-t"] = actions.file_tabedit,
      ["alt-q"]  = actions.file_sel_to_qf,
      ["alt-Q"]  = actions.file_sel_to_ll,
      ["alt-i"]  = { fn = actions.toggle_ignore, reuse = true, header = false },
      ["alt-h"]  = { fn = actions.toggle_hidden, reuse = true, header = false },
      ["alt-f"]  = { fn = actions.toggle_follow, reuse = true, header = false },
    },
  },
  fzf_bin       = nil, ---@type string? Path to fzf binary.
  ---Fzf command-line options passed to fzf binary.
  fzf_opts      = {
    ["--ansi"]           = true,
    ["--info"]           = "inline-right",
    ["--height"]         = "100%",
    ["--layout"]         = "reverse",
    ["--border"]         = "none",
    ["--highlight-line"] = true,
    -- typo-resistant algo with skim >= v1.5.3
    -- ["--algo"]        = "frizbee",
  },
  ---Options passed to fzf-tmux wrapper.
  fzf_tmux_opts = { ["-p"] = "80%,80%", ["--margin"] = "0,0" },
  ---@class fzf-lua.config.Previewers
  ---@field builtin fzf-lua.config.BuiltinPreviewer
  ---@field git_diff fzf-lua.config.GitDiffPreviewer
  ---@field [string] fzf-lua.config.Previewer
  previewers    = {
    cat = {
      cmd   = "cat",
      args  = "-n",
      _ctor = previewers.fzf.cmd,
    },
    bat = {
      -- reduce startup time by deferring executable check to previewer constructor (#970)
      cmd   = function() return vim.fn.executable("batcat") == 1 and "batcat" or "bat" end,
      -- args  = "--color=always --style=default",
      args  = "--color=always --style=numbers,changes",
      _ctor = previewers.fzf.bat_async,
    },
    bat_native = {
      cmd   = function() return vim.fn.executable("batcat") == 1 and "batcat" or "bat" end,
      args  = "--color=always --style=numbers,changes",
      -- NOTE: no support for `bat_native` on Windows, it's a hassle for no real
      -- benefit, native previewers will be removed from the code at one point
      _ctor = utils._if_win(previewers.fzf.bat_async, previewers.fzf.bat),
    },
    head = {
      cmd   = "head",
      args  = nil,
      _ctor = previewers.fzf.head,
    },
    ---@class fzf-lua.config.GitDiffPreviewer: fzf-lua.config.Previewer
    git_diff = {
      pager         = M._preview_pager_fn,
      cmd_deleted   = "git diff --color HEAD --",
      cmd_modified  = "git diff --color HEAD",
      cmd_untracked = "git diff --color --no-index /dev/null",
      -- TODO: modify previewer code to accept table cmd
      -- cmd_deleted   = { "git", "diff", "--color", "HEAD", "--" },
      -- cmd_modified  = { "git", "diff", "--color", "HEAD" },
      -- cmd_untracked = { "git", "diff", "--color", "--no-index", "/dev/null" },
      _fn_git_icons = function() return M.globals.git.icons end,
      _ctor         = previewers.fzf.git_diff,
    },
    man = {
      _ctor = previewers.builtin.man_pages,
      cmd = function() return M._man_cmd_fn() end,
    },
    man_native = {
      _ctor = previewers.fzf.man_pages,
      cmd = function() return M._man_cmd_fn(true) end,
    },
    help_tags = { _ctor = previewers.builtin.help_tags },
    help_native = { _ctor = previewers.fzf.help_tags },
    swiper = { _ctor = previewers.swiper.default },
    ---@class fzf-lua.config.BuiltinPreviewer: fzf-lua.config.Previewer
    builtin = {
      syntax            = true,
      syntax_delay      = 0,
      syntax_limit_l    = 0,
      syntax_limit_b    = 1024 * 1024,      -- 1MB
      limit_b           = 1024 * 1024 * 10, -- 10MB
      treesitter        = {
        enabled = true,
        disabled = {},
        -- nvim-treesitter-context config options
        -- https://github.com/nvim-treesitter/nvim-treesitter-context
        context = { max_lines = 1, trim_scope = "inner" }
      },
      ueberzug_scaler   = "cover",
      title_fnamemodify = function(s) return path.tail(s) end,
      render_markdown   = { enabled = true, filetypes = { ["markdown"] = true } },
      snacks_image      = { enabled = true, render_inline = true },
      _ctor             = previewers.builtin.buffer_or_file,
    },
    ---@class fzf-lua.config.CodeActionPreviewer: fzf-lua.config.Previewer
    codeaction = {
      _ctor     = previewers.builtin.codeaction,
      diff_opts = { ctxlen = 3 },
    },
    codeaction_native = {
      _ctor     = previewers.fzf.codeaction,
      diff_opts = { ctxlen = 3 },
      pager     = M._preview_pager_fn,
    },
    ---@class fzf-lua.config.UndotreePreviewer: fzf-lua.config.Previewer
    undotree = {
      _ctor     = previewers.builtin.undotree,
      diff_opts = { ctxlen = 5 },
      show_buf  = false,
    },
    undotree_native = {
      _ctor     = previewers.fzf.undotree,
      diff_opts = { ctxlen = 5 },
      pager     = M._preview_pager_fn,
    },
    -- convenient aliaes
    undo = {
      _ctor     = previewers.builtin.undotree,
      diff_opts = { ctxlen = 5 },
    },
    undo_native = {
      _ctor     = previewers.fzf.undotree,
      diff_opts = { ctxlen = 5 },
      pager     = M._preview_pager_fn,
    },
  },
  formatters    = {
    path = {
      filename_first = {
        -- <Tab> is used as the invisible space between the parent and the file part
        enrich = function(o, v)
          o.fzf_opts = vim.tbl_extend("keep", o.fzf_opts or {}, { ["--tabstop"] = 1 })
          if tonumber(v) == 2 then
            -- https://github.com/ibhagwan/fzf-lua/pull/1255
            o.fzf_opts = vim.tbl_extend("keep", o.fzf_opts or {}, {
              ["--ellipsis"] = " ",
              ["--no-hscroll"] = true,
            })
          end
          return o
        end,
        -- underscore `_to` returns a custom to function when options could
        -- affect the transformation, here we create a different function
        -- base on the dir part highlight group.
        -- We use a string function with hardcoded values as non-scope vars
        -- (globals or file-locals) are stored by ref and will be nil in the
        -- `string.dump` (from `config.bytecode`), we use the 3rd function
        -- argument `m` to pass module imports (path, utils, etc).
        _to = function(o, v)
          local _, hl_dir = utils.ansi_from_hl(o.hls.dir_part, "foo")
          local _, hl_file = utils.ansi_from_hl(o.hls.file_part, "foo")
          local v2 = tonumber(v) ~= 2 and "" or [[, "\xc2\xa0" .. string.rep(" ", 200) .. s]]
          return ([[
            return function(s, _, m)
              local _path, _utils = m.path, m.utils
              local _hl_dir = "%s"
              local _hl_file = "%s"
              local tail = _path.tail(s)
              local parent = _path.parent(s)
              if #_hl_file > 0 then
                tail = _hl_file .. tail .. _utils.ansi_escseq.clear
              end
              if parent then
                parent = _path.remove_trailing(parent)
                if #_hl_dir > 0 then
                  parent = _hl_dir .. parent .. _utils.ansi_escseq.clear
                end
                return tail .. "\t" .. parent %s
              else
                return tail %s
              end
            end
          ]]):format(hl_dir or "", hl_file or "", v2, v2)
        end,
        from = function(s, _)
          s = s:gsub("\xc2\xa0     .*$", "") -- gsub v2 postfix
          local parts = utils.strsplit(s, utils.nbsp)
          local last = parts[#parts]
          ---@cast last -?
          -- Lines from grep, lsp, tags are formatted <file>:<line>:<col>:<text>
          -- the pattern below makes sure tab doesn't come from the line text
          local filename, rest = last:match("^([^:]-)\t(.+)$")
          if filename and rest then
            local parent
            if utils.__IS_WINDOWS and path.is_absolute(rest) then
              parent = rest:sub(1, 2) .. (#rest > 2 and rest:sub(3):match("^[^:]+") or "")
            else
              parent = rest:match("^[^:]+")
            end
            local fullpath = path.join({ parent, filename })
            -- overwrite last part with restored fullpath + rest of line
            parts[#parts] = fullpath .. rest:sub(#parent + 1)
            return table.concat(parts, utils.nbsp)
          else
            return s
          end
        end
      },
      dirname_first = {
        -- Credit fo @folke :-)
        -- https://github.com/ibhagwan/fzf-lua/pull/1255
        _to = function(o)
          local _, hl_dir = utils.ansi_from_hl(o.hls.dir_part, "foo")
          local _, hl_file = utils.ansi_from_hl(o.hls.file_part, "foo")
          return ([[
            return function(s, _, m)
              local _path, _utils = m.path, m.utils
              local _hl_dir = "%s"
              local _hl_file = "%s"
              local tail = _path.tail(s)
              local parent = _path.parent(s)
              if #_hl_file > 0 then
                tail = _hl_file .. tail .. _utils.ansi_escseq.clear
              end
              if parent then
                parent = _path.add_trailing(parent)
                if #_hl_dir > 0 then
                  parent = _hl_dir .. parent .. _utils.ansi_escseq.clear
                end
              end
              return (parent or "") .. tail
            end
          ]]):format(hl_dir or "", hl_file or "")
        end,
      },
    }
  },
}

---Find files using `fd`, `rg`, `find` or `dir.exe`.
---@class fzf-lua.config.Files: fzf-lua.config.Base
---Shell command used to generate the file list, default: auto detect `fd|rg|find|dir.exe`.
---@field cmd? string
---Exclude the current file from the list.
---@field ignore_current_file? boolean
---Lua patterns of files to ignore.
---@field file_ignore_patterns? string[]
---Parse the query for a line number suffix, e.g. `file.lua:10` will open `file.lua` at line 10.
---@field line_query? boolean|fun(query: string): lnum: string?, new_query: string?
---Raw shell command to use without any processing, bypasses all fzf-lua internals.
---@field raw_cmd? string
---Display the current working directory in the prompt (`fzf.vim` style).
---@field cwd_prompt? boolean
---Prompt over this length will be shortened using `pathshorten`.
---@field cwd_prompt_shorten_len? integer
---Length of shortened prompt path parts (`:help pathshorten`).
---@field cwd_prompt_shorten_val? integer
---Include hidden files (toggle with `<A-h>`).
---@field hidden? boolean
---Flag passed to the shell command to toggle ignoring `.gitignore` rules.
---@field toggle_ignore_flag? string
---Flag passed to the shell command to toggle showing hidden files.
---@field toggle_hidden_flag? string
---Flag passed to the shell command to toggle following symbolic links.
---@field toggle_follow_flag? string
M.defaults.files  = {
  previewer              = M._default_previewer_fn,
  multiprocess           = 1, ---@type integer|boolean
  _type                  = "file",
  file_icons             = 1, ---@type integer|boolean
  color_icons            = true,
  git_icons              = false,
  cwd_prompt             = true,
  cwd_prompt_shorten_len = 32,
  cwd_prompt_shorten_val = 1,
  fzf_opts               = { ["--multi"] = true, ["--scheme"] = "path" },
  _fzf_nth_devicons      = true,
  git_status_cmd         = {
    "git", "-c", "color.status=false", "--no-optional-locks", "status", "--porcelain=v1" },
  find_opts              = [[-type f \! -path '*/.git/*']],
  rg_opts                = [[--color=never --files -g "!.git"]],
  fd_opts                = [[--color=never --type f --type l --exclude .git]],
  dir_opts               = [[/s/b/a:-d]],
  hidden                 = true,
  toggle_ignore_flag     = "--no-ignore",
  toggle_hidden_flag     = "--hidden",
  toggle_follow_flag     = "-L",
  _actions               = function() return M.globals.actions.files end,
  _headers               = { "actions", "cwd" },
  winopts                = { preview = { winopts = { cursorline = false } } },
}

---Global multi-picker, combines files, buffers and symbols.
---@diagnostic disable-next-line: param-type-mismatch
---@class fzf-lua.config.Global : fzf-lua.config.Files
---@field pickers (fun():table)|table
---@field __alt_opts? boolean
M.defaults.global = vim.tbl_deep_extend("force", M.defaults.files, {
  silent            = true,
  -- TODO: lsp_workspace_symbols locate, not working yet
  -- as opts.__locate_pos is inside the symbols picker opts
  -- locate            = true,
  cwd_prompt        = true,
  line_query        = true,
  pickers           = function()
    local clients = utils.lsp_get_clients({ bufnr = utils.CTX().bufnr })
    local doc_sym_supported = vim.iter(clients):any(function(client)
      return client:supports_method("textDocument/documentSymbol")
    end)
    local wks_sym_supported = vim.iter(clients):any(function(client)
      return client:supports_method("workspace/symbol")
    end)
    return {
      { "files",   desc = "Files" },
      { "buffers", desc = "Bufs", prefix = "$" },
      doc_sym_supported and {
        "lsp_document_symbols",
        desc = "Symbols (buf)",
        prefix = "@",
        opts = { no_autoclose = true }
      } or {
        "btags",
        desc = "Tags (buf)",
        prefix = "@",
        opts = {
          previewer    = { _ctor = previewers.builtin.tags },
          fn_transform = [[return require("fzf-lua.make_entry").tag]],
        }
      },
      wks_sym_supported and
      {
        "lsp_workspace_symbols",
        desc = "Symbols (project)",
        prefix = "#",
        opts = { no_autoclose = true }
      } or {
        "tags",
        desc = "Tags (project)",
        prefix = "#",
        opts = {
          previewer    = { _ctor = previewers.builtin.tags },
          fn_transform = [[return require("fzf-lua.make_entry").tag]],
          rg_opts      = "--no-heading --color=always --smart-case",
          grep_opts    = "--color=auto --perl-regexp",
        }
      },
    }
  end,
  fzf_opts          = { ["--nth"] = false, ["--with-nth"] = false },
  winopts           = { preview = { winopts = { cursorline = true } } },
  _ctx              = { includeBuflist = true }, -- we include a buffer picker
  _fzf_nth_devicons = false,
})


---@class fzf-lua.config.GitBase: fzf-lua.config.Base
---Path to `.git` directory for bare repos or worktrees.
---@field git_dir? string
---Shell command used to generate the list.
---@field cmd string

---Git pickers parent table.
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
---@field icons     fzf-lua.git.icons
-- Must construct our opts table in stages
-- so we can reference 'M.globals.files'
M.defaults.git                   = {
  ---Git tracked files.
  ---@class fzf-lua.config.GitFiles: fzf-lua.config.Base
  files = {
    previewer         = M._default_previewer_fn,
    cmd               = "git ls-files --exclude-standard",
    multiprocess      = 1, ---@type integer|boolean
    _type             = "file",
    file_icons        = 1, ---@type integer|boolean
    color_icons       = true,
    git_icons         = true,
    fzf_opts          = { ["--multi"] = true, ["--scheme"] = "path" },
    _fzf_nth_devicons = true,
    _actions          = function() return M.globals.actions.files end,
    _headers          = { "cwd" },
    winopts           = { preview = { winopts = { cursorline = false } } },
  },
  ---Git status (modified files).
  ---@class fzf-lua.config.GitStatus: fzf-lua.config.Base
  status = {
    -- override `color.status=always`, technically not required
    -- since we now also call `utils.strip_ansi_coloring` (#706)
    cmd               = "git -c color.status=false --no-optional-locks status --porcelain=v1 -u",
    previewer         = "git_diff",
    multiprocess      = true, ---@type integer|boolean
    fn_transform      = [[return require("fzf-lua.make_entry").git_status]],
    fn_preprocess     = [[return require("fzf-lua.make_entry").preprocess]],
    file_icons        = 1, ---@type integer|boolean
    color_icons       = true,
    fzf_opts          = { ["--multi"] = true },
    _fzf_nth_devicons = true,
    _actions          = function() return M.globals.actions.files end,
    _headers          = { "actions", "cwd" },
    actions           = {
      ["right"]  = { fn = actions.git_unstage, reload = true },
      ["left"]   = { fn = actions.git_stage, reload = true },
      ["ctrl-x"] = { fn = actions.git_reset, reload = true },
      -- Uncomment to test stage|unstage and backward compat
      -- ["ctrl-s"] = { fn = actions.git_stage_unstage, reload = true },
      -- ["ctrl-s"] = { actions.git_stage_unstage, actions.resume },
    },
  },
  ---Git diff (changed files vs a git ref).
  ---@class fzf-lua.config.GitDiff: fzf-lua.config.GitBase
  ---Git reference to compare against.
  ---@field ref? string
  ---Git reference used as the base for the comparison.
  ---@field compare_against? string
  diff = {
    cmd               = "git --no-pager diff --name-only {compare_against} {ref}",
    ref               = "HEAD",
    compare_against   = "",
    preview           = "git diff {compare_against} {ref} {file}",
    preview_pager     = M._preview_pager_fn,
    multiprocess      = 1, ---@type integer|boolean
    _type             = "file",
    file_icons        = 1, ---@type integer|boolean
    color_icons       = true,
    fzf_opts          = { ["--multi"] = true },
    _fzf_nth_devicons = true,
    _actions          = function() return M.globals.actions.files end,
    _headers          = { "cwd" },
  },
  ---Git diff hunks (changed lines).
  ---@class fzf-lua.config.GitHunks: fzf-lua.config.GitBase
  ---Git reference to compare against.
  ---@field ref? string
  hunks = {
    previewer         = M._default_previewer_fn,
    cmd               = "git --no-pager diff --color=always {ref}",
    ref               = "HEAD",
    multiprocess      = true, ---@type integer|boolean
    fn_transform      = [[return require("fzf-lua.make_entry").git_hunk]],
    fn_preprocess     = [[return require("fzf-lua.make_entry").preprocess]],
    file_icons        = 1, ---@type integer|boolean
    color_icons       = true,
    fzf_opts          = {
      ["--multi"] = true,
      ["--delimiter"] = ":",
      ["--nth"] = "3..",
    },
    _fzf_nth_devicons = true,
    _actions          = function() return M.globals.actions.files end,
    _headers          = { "cwd" },
  },
  ---Git commits (project).
  ---@class fzf-lua.config.GitCommits: fzf-lua.config.GitBase
  commits = {
    cmd           = [[git log --color --pretty=format:"%C(yellow)%h%Creset ]]
        .. [[%Cgreen(%><(12)%cr%><|(12))%Creset %s %C(blue)<%an>%Creset"]],
    preview       = "git show --color {1}",
    preview_pager = M._preview_pager_fn,
    actions       = {
      ["enter"]  = actions.git_checkout,
      ["ctrl-y"] = { fn = actions.git_yank_commit, exec_silent = true },
    },
    fzf_opts      = { ["--no-multi"] = true },
    _headers      = { "actions", "cwd" },
    _multiline    = false,
  },
  ---Git commits (buffer).
  ---@class fzf-lua.config.GitBcommits: fzf-lua.config.GitBase
  bcommits = {
    cmd           = [[git log --color --pretty=format:"%C(yellow)%h%Creset ]]
        .. [[%Cgreen(%><(12)%cr%><|(12))%Creset %s %C(blue)<%an>%Creset" -- {file}]],
    preview       = "git show --color {1} -- {file}",
    preview_pager = M._preview_pager_fn,
    actions       = {
      ["enter"]  = actions.git_buf_edit,
      ["ctrl-s"] = actions.git_buf_split,
      ["ctrl-v"] = actions.git_buf_vsplit,
      ["ctrl-t"] = actions.git_buf_tabedit,
      ["ctrl-y"] = { fn = actions.git_yank_commit, exec_silent = true },
    },
    fzf_opts      = { ["--no-multi"] = true },
    _headers      = { "actions", "cwd" },
    _multiline    = false,
  },
  ---Git blame (buffer).
  ---@class fzf-lua.config.GitBlame: fzf-lua.config.GitBase
  blame = {
    cmd           = [[git blame --color-lines {file}]],
    preview       = "git show --color {1} -- {file}",
    preview_pager = M._preview_pager_fn,
    actions       = {
      ["enter"]  = actions.git_goto_line,
      ["ctrl-s"] = actions.git_buf_split,
      ["ctrl-v"] = actions.git_buf_vsplit,
      ["ctrl-t"] = actions.git_buf_tabedit,
      ["ctrl-y"] = { fn = actions.git_yank_commit, exec_silent = true },
    },
    fzf_opts      = { ["--no-multi"] = true },
    _multiline    = false,
    -- `winopts.treesitter==true` line match format
    _treesitter   = function(line) return line:match("(%s+)(%d+)%)(.+)$") end,
  },
  ---Git branches.
  ---@class fzf-lua.config.GitBranches: fzf-lua.config.GitBase
  ---Filter branches, possible values are `local|remote|all`.
  ---@field remotes? string
  ---Shell command used to add a branch.
  ---@field cmd_add? string[]
  ---Shell command used to delete a branch.
  ---@field cmd_del? string[]
  branches = {
    cmd        = [[git branch --all --color -vv ]]
        .. [[--sort=-'committerdate' --sort='refname:rstrip=-2' --sort=-'HEAD']],
    preview    = "git log --graph --pretty=oneline --abbrev-commit --color {1}",
    remotes    = "local",
    actions    = {
      ["enter"]  = actions.git_switch,
      ["ctrl-x"] = { fn = actions.git_branch_del, reload = true },
      ["ctrl-a"] = { fn = actions.git_branch_add, field_index = "{q}", reload = true },
    },
    cmd_add    = { "git", "branch" },
    cmd_del    = { "git", "branch", "--delete" },
    fzf_opts   = { ["--no-multi"] = true, ["--tiebreak"] = "begin" },
    _headers   = { "actions", "cwd" },
    _multiline = false,
  },
  ---Git worktrees.
  ---@class fzf-lua.config.GitWorktrees: fzf-lua.config.GitBase
  ---Scope of the `cd` action, possible values are `local|win|tab|global`.
  ---@field scope? string
  worktrees = {
    scope      = "global", -- cd action scope "local|win|tab"
    cmd        = "git worktree list",
    preview    = [[git log --color --pretty=format:"%C(yellow)%h%Creset ]]
        .. [[%Cgreen(%><(12)%cr%><|(12))%Creset %s %C(blue)<%an>%Creset"]],
    actions    = {
      ["enter"]  = actions.git_worktree_cd,
      ["ctrl-x"] = { fn = actions.git_worktree_del, reload = true },
      ["ctrl-a"] = { fn = actions.git_worktree_add, field_index = "{q}", reload = true },
    },
    fzf_opts   = { ["--no-multi"] = true },
    _headers   = { "actions", "cwd" },
    _multiline = false,
  },
  ---Git tags.
  ---@class fzf-lua.config.GitTags: fzf-lua.config.GitBase
  tags = {
    cmd        = [[git for-each-ref --color --sort="-taggerdate" --format ]]
        .. [["%(color:yellow)%(refname:short)%(color:reset) ]]
        .. [[%(color:green)(%(taggerdate:relative))%(color:reset)]]
        .. [[ %(subject) %(color:blue)%(taggername)%(color:reset)" refs/tags]],
    preview    = [[git log --graph --color --pretty=format:"%C(yellow)%h%Creset ]]
        .. [[%Cgreen(%><(12)%cr%><|(12))%Creset %s %C(blue)<%an>%Creset" {1}]],
    actions    = { ["enter"] = actions.git_checkout },
    fzf_opts   = { ["--no-multi"] = true },
    _headers   = { "cwd" },
    _multiline = false,
  },
  ---Git stashes.
  ---@class fzf-lua.config.GitStash: fzf-lua.config.GitBase
  stash = {
    cmd           = "git --no-pager stash list",
    preview       = "git --no-pager stash show --patch --color {1}",
    preview_pager = M._preview_pager_fn,
    actions       = {
      ["enter"]  = actions.git_stash_apply,
      ["ctrl-x"] = { fn = actions.git_stash_drop, reload = true },
    },
    fzf_opts      = {
      -- TODO: multiselect requires more work as dropping
      -- a stash changes the stash index, causing an error
      -- when the next stash is attempted
      ["--no-multi"]  = true,
      ["--delimiter"] = "[:]",
    },
    _headers      = { "actions", "cwd", "search" },
  },
  ---@class fzf-lua.git.icons
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

---Grep using `rg`, `grep` or other grep commands.
---@class fzf-lua.config.Grep: fzf-lua.config.Base
---Shell command used to execute grep, default: auto detect `rg|grep`.
---@field cmd? string
---Use `rg` glob parsing, e.g. `foo -- -g*.md` will only match markdown files containing `foo`.
---@field rg_glob? boolean|integer
---Custom glob parsing function, returns the search query and the glob filter.
---@field rg_glob_fn? fun(query: string, opts: table): string, string
---Raw shell command to use without any processing, bypasses all fzf-lua internals.
---@field raw_cmd? string
---Initial search string.
---@field search? string
---Initial search pattern.
---@field regex? string
---Disable escaping of special characters in the search query, set to `2` to disable escaping and regex mode.
---@field no_esc? integer|boolean
---Enable live grep mode (search-as-you-type).
---@field lgrep? boolean
---List of paths to search (grep), e.g. `:FzfLua grep search_paths=/path/to/search`.
---@field search_paths? string[]
---Input prompt for the initial search query.
---@field input_prompt? string
---Ripgrep options passed to the `rg` command.
---@field rg_opts? string
---GNU grep options passed to the `grep` command.
---@field grep_opts? string
---Glob flag passed to the shell command, default `--iglob` (case insensitive), use `--glob` for case sensitive.
---@field glob_flag? string
---Query separator pattern (lua) for extracting glob patterns from the search query, default `%s%-%-` (` --`).
---@field glob_separator? string
---@field __resume_set? function
---@field __resume_get? function
M.defaults.grep                  = {
  previewer      = M._default_previewer_fn,
  input_prompt   = "Grep For> ",
  multiprocess   = 1, ---@type integer|boolean
  _type          = "file",
  file_icons     = 1, ---@type integer|boolean
  color_icons    = true,
  git_icons      = false,
  fzf_opts       = { ["--multi"] = true },
  grep_opts      = utils.is_darwin()
      and "--binary-files=without-match --line-number --recursive --color=always "
      .. "--extended-regexp -e"
      or "--binary-files=without-match --line-number --recursive --color=always "
      .. "--perl-regexp -e",
  rg_opts        = "--column --line-number --no-heading --color=always --smart-case "
      .. "--max-columns=4096 -e",
  rg_glob        = 1, -- do not display warning if using `grep`
  _actions       = function() return M.globals.actions.files end,
  actions        = { ["ctrl-g"] = { actions.grep_lgrep } },
  -- live_grep_glob options
  glob_flag      = "--iglob", -- for case sensitive globs use '--glob'
  glob_separator = "%s%-%-",  -- query separator pattern (lua): ' --'
  _treesitter    = 1,         -- auto disable in live grep
  _headers       = { "actions", "cwd" },
}

---Grep current buffer only.
---@diagnostic disable-next-line: param-type-mismatch
---@class fzf-lua.config.GrepCurbuf: fzf-lua.config.Grep,{}
---@field filename? string
M.defaults.grep_curbuf           = vim.tbl_deep_extend("force", M.defaults.grep, {
  rg_glob          = false, -- meaningless for single file rg
  exec_empty_query = true,  -- makes sense to display lines immediately
  fzf_opts         = {
    ["--delimiter"] = "[:]",
    ["--with-nth"]  = "2..",
    ["--nth"]       = "2..",
  },
})

---Neovim's argument list (`:args`).
---@class fzf-lua.config.Args: fzf-lua.config.Base
---Exclude non-file entries (directories) from the list.
---@field files_only? boolean
M.defaults.args                  = {
  previewer         = M._default_previewer_fn,
  files_only        = true, -- Exclude non-file entries (directories).
  file_icons        = 1, ---@type integer|boolean
  color_icons       = true,
  git_icons         = false,
  fzf_opts          = { ["--multi"] = true, ["--scheme"] = "path" },
  _fzf_nth_devicons = true,
  _actions          = function() return M.globals.actions.files end,
  actions           = { ["ctrl-x"] = { fn = actions.arg_del, reload = true } },
  _headers          = { "actions", "cwd" },
}

---File history (output of `:oldfiles`).
---@class fzf-lua.config.Oldfiles: fzf-lua.config.Base
---Only include files that still exist on disk.
---@field stat_file? boolean
---Include files opened during the current session.
---@field include_current_session? boolean
---Exclude the current buffer from the list.
---@field ignore_current_buffer? boolean
M.defaults.oldfiles              = {
  previewer               = M._default_previewer_fn,
  file_icons              = 1, ---@type integer|boolean
  color_icons             = true,
  git_icons               = false,
  stat_file               = true,
  include_current_session = false,
  ignore_current_buffer   = true,
  fzf_opts                = { ["--tiebreak"] = "index", ["--multi"] = true },
  _fzf_nth_devicons       = true,
  _actions                = function() return M.globals.actions.files end,
  _headers                = { "cwd" },
  _resume_reload          = true,
}

---File history including current session.
---@class fzf-lua.config.History: fzf-lua.config.Oldfiles
M.defaults.history               = vim.tbl_deep_extend("force", {}, M.defaults.oldfiles, {
  include_current_session = true,
  ignore_current_buffer   = false,
})

---Quickfix list entries.
---@class fzf-lua.config.Quickfix: fzf-lua.config.Base
---Separator between filename and text.
---@field separator string
---Only include entries with valid file/line information.
---@field valid_only boolean
M.defaults.quickfix              = {
  previewer   = M._default_previewer_fn,
  separator   = "▏",
  file_icons  = 1, ---@type integer|boolean
  color_icons = true,
  git_icons   = false,
  valid_only  = false,
  fzf_opts    = {
    ["--multi"]     = true,
    ["--delimiter"] = "[\\]:]",
    ["--with-nth"]  = "2..",
  },
  actions     = { ["ctrl-x"] = { fn = actions.list_del, reload = true } },
  _actions    = function() return M.globals.actions.files end,
  _treesitter = true,
  _cached_hls = { "path_colnr", "path_linenr" },
  _headers    = { "actions", "cwd" },
}

---Quickfix list history.
---@class fzf-lua.config.QuickfixStack: fzf-lua.config.Base
---@field marker string
M.defaults.quickfix_stack        = {
  marker    = ">",
  previewer = { _ctor = previewers.builtin.quickfix, },
  fzf_opts  = { ["--no-multi"] = true },
  actions   = { ["enter"] = actions.set_qflist, },
}

---Location list entries.
---@class fzf-lua.config.Loclist : fzf-lua.config.Quickfix: fzf-lua.config.Base
---@field is_loclist true
M.defaults.loclist               = {
  previewer   = M._default_previewer_fn,
  separator   = "▏",
  file_icons  = 1, ---@type integer|boolean
  color_icons = true,
  git_icons   = false,
  valid_only  = false,
  fzf_opts    = {
    ["--multi"]     = true,
    ["--delimiter"] = "[\\]:]",
    ["--with-nth"]  = "2..",
  },
  actions     = { ["ctrl-x"] = { fn = actions.list_del, reload = true } },
  _actions    = function() return M.globals.actions.files end,
  _treesitter = true,
  _cached_hls = { "path_colnr", "path_linenr" },
  _headers    = { "actions", "cwd" },
}

---Location list history.
---@class fzf-lua.config.LoclistStack : fzf-lua.config.QuickfixStack: fzf-lua.config.Base
---@field is_loclist true
M.defaults.loclist_stack         = {
  marker    = ">",
  previewer = { _ctor = previewers.builtin.quickfix, },
  fzf_opts  = { ["--no-multi"] = true },
  actions   = { ["enter"] = actions.set_qflist, },
}

---Open buffers.
---@class fzf-lua.config.Buffers: fzf-lua.config.BufferLines
---Only display the filename without the path.
---@field filename_only? boolean
---Override the current working directory for relative paths.
---@field cwd? string
---Sort buffers by last used.
---@field sort_lastused? boolean
---Include unloaded (not yet displayed) buffers.
---@field show_unloaded? boolean
---Include unlisted buffers (`:help unlisted-buffer`).
---@field show_unlisted? boolean
---Exclude the current buffer from the list.
---@field ignore_current_buffer? boolean
---Limit results to buffers from the current working directory only.
---@field cwd_only? boolean
---Do not set cursor position when switching buffers.
---@field no_action_set_cursor? boolean
M.defaults.buffers               = {
  _type                 = "file",
  previewer             = M._default_previewer_fn,
  file_icons            = 1, ---@type integer|boolean
  color_icons           = true,
  sort_lastused         = true,
  show_unloaded         = true,
  show_unlisted         = false,
  ignore_current_buffer = false,
  no_action_set_cursor  = true,
  cwd_only              = false,
  cwd                   = nil,
  fzf_opts              = { ["--tiebreak"] = "index", ["--multi"] = true },
  _actions              = function()
    return M.globals.actions.buffers or M.globals.actions.files
  end,
  actions               = { ["ctrl-x"] = { fn = actions.buf_del, reload = true } },
  _cached_hls           = { "buf_nr", "buf_flag_cur", "buf_flag_alt", "path_linenr" },
  _headers              = { "actions", "cwd" },
  _ctx                  = { includeBuflist = true },
  _resume_reload        = true,
}

---Open buffers by tabs.
---@class fzf-lua.config.Tabs: fzf-lua.config.BufferLines
---Only display the filename without the path.
---@field filename_only? boolean
---@field __locate_pos? integer
---Only display buffers from the current tab.
---@field current_tab_only? boolean
---Tab title prefix in the results list.
---@field tab_title? string
---Marker for the current tab.
---@field tab_marker? string
---Jump to the selected buffer's location in the file.
---@field locate? boolean
M.defaults.tabs                  = {
  _type          = "file",
  previewer      = M._default_previewer_fn,
  tab_title      = "Tab",
  tab_marker     = "<<",
  locate         = true,
  file_icons     = 1, ---@type integer|boolean
  color_icons    = true,
  _actions       = function()
    return M.globals.actions.buffers or M.globals.actions.files
  end,
  actions        = {
    ["enter"]  = actions.buf_switch,
    ["ctrl-x"] = { fn = actions.buf_del, reload = true },
  },
  fzf_opts       = {
    ["--multi"]     = true,
    ["--delimiter"] = "[\t\\)]",
    ["--tabstop"]   = "1",
    ["--with-nth"]  = "5..",
  },
  _cached_hls    = { "buf_nr", "buf_flag_cur", "buf_flag_alt", "tab_title", "tab_marker", "path_linenr" },
  _headers       = { "actions", "cwd" },
  _ctx           = { includeBuflist = true },
  _resume_reload = true,
}

---Open buffers lines.
---@class fzf-lua.config.Lines: fzf-lua.config.BufferLines
---Show buffer name in results. Set to a number to only show if the window width exceeds this value.
---@field show_bufname? boolean|integer
---Include unloaded (not yet displayed) buffers.
---@field show_unloaded? boolean
---Include unlisted buffers (`:help unlisted-buffer`).
---@field show_unlisted? boolean
---Exclude terminal buffers from the list.
---@field no_term_buffers? boolean
---Sort buffers by last used.
---@field sort_lastused? boolean
M.defaults.lines                 = {
  previewer        = M._default_previewer_fn,
  file_icons       = 1, ---@type integer|boolean
  color_icons      = true,
  show_bufname     = 120,
  show_unloaded    = true,
  show_unlisted    = false,
  no_term_buffers  = true,
  sort_lastused    = true,
  fzf_opts         = {
    ["--multi"]     = true,
    ["--delimiter"] = "[\t]",
    ["--tabstop"]   = "1",
    ["--tiebreak"]  = "index",
    ["--with-nth"]  = "2..",
    ["--nth"]       = "4..",
  },
  line_field_index = "{4}",
  field_index_expr = "{}", -- For `_fmt.from` to work with `bat_native`
  _treesitter      = true,
  _cached_hls      = { "buf_id", "buf_name", "buf_linenr" },
  _fmt             = {
    -- NOTE: `to` is not needed, we format at the source in `buffer_lines`
    to   = false,
    from = function(s, _)
      -- restore the format to something that `path.entry_to_file` can handle
      local bufnr0, lnum, text = s:match("%[(%d+)%].-(%d+) (.+)$")
      local bufnr = tonumber(bufnr0)
      if not bufnr then return "" end ---@cast bufnr integer
      return string.format("[%s]%s%s:%s:%s",
        bufnr, utils.nbsp,
        path.tail(vim.api.nvim_buf_get_name(bufnr)),
        lnum, text)
    end
  },
  _actions         = function()
    return M.globals.actions.buffers or M.globals.actions.files
  end,
  _ctx             = { includeBuflist = true },
}

---Current buffer lines.
---@diagnostic disable-next-line: param-type-mismatch
---@class fzf-lua.config.Blines: fzf-lua.config.Lines
M.defaults.blines                = vim.tbl_deep_extend("force", M.defaults.lines, {
  show_bufname    = false,
  show_unloaded   = true,
  show_unlisted   = true,
  no_term_buffers = false,
  fzf_opts        = {
    ["--with-nth"] = "4..",
    ["--nth"]      = "2..",
  },
  _resume_reload  = true,
})

---Current buffer treesitter symbols.
---@class fzf-lua.config.Treesitter: fzf-lua.config.Base
---Buffer number to search, default: current buffer.
---@field bufnr? integer
M.defaults.treesitter            = {
  previewer        = M._default_previewer_fn,
  file_icons       = false, ---@type integer|boolean
  color_icons      = false,
  fzf_opts         = {
    ["--multi"]     = true,
    ["--tabstop"]   = "4",
    ["--delimiter"] = "[:]",
    ["--with-nth"]  = "2..",
  },
  line_field_index = "{2}",
  _actions         = function()
    return M.globals.actions.buffers or M.globals.actions.files
  end,
  _cached_hls      = { "buf_name", "buf_nr", "buf_linenr", "path_colnr" },
  _fmt             = {
    to   = false,
    from = function(s, _)
      return s:gsub("\t\t", ": ")
    end
  },
}

---Misspelled words in buffer.
---@class fzf-lua.config.Spellcheck: fzf-lua.config.BufferLines
---Lua pattern used to split words for spell checking.
---@field word_separator string
---Buffer number to check, default: current buffer.
---@field bufnr? integer
M.defaults.spellcheck            = {
  previewer        = M._default_previewer_fn,
  file_icons       = false,
  color_icons      = false,
  word_separator   = "[%s%p]",
  fzf_opts         = {
    ["--multi"]     = true,
    ["--tabstop"]   = "4",
    ["--delimiter"] = "[:]",
    ["--with-nth"]  = "2..",
  },
  line_field_index = "{2}",
  _actions         = function()
    return M.globals.actions.buffers or M.globals.actions.files
  end,
  actions          = {
    ["ctrl-s"] = { fn = actions.spell_suggest, header = "spell suggest" }
  },
  _cached_hls      = { "buf_name", "buf_nr", "buf_linenr", "path_colnr" },
  _headers         = { "actions" },
  _fmt             = {
    to   = false,
    from = function(s, _)
      return s:gsub("\t\t", ": ")
    end
  },
}

---@class fzf-lua.config.TagsBase: fzf-lua.config.Base
---Path to the tags file, default: auto-detect.
---@field ctags_file? string
---Shell command used to generate the tags list.
---@field cmd? string
---Search project ctags.
---@class fzf-lua.config.Tags: fzf-lua.config.TagsBase
---@class fzf-lua.config.TagsGrep: fzf-lua.config.TagsBase,fzf-lua.config.Grep
M.defaults.tags                  = {
  previewer     = { _ctor = previewers.builtin.tags },
  input_prompt  = "[tags] Grep For> ",
  rg_opts       = "--no-heading --color=always --smart-case",
  grep_opts     = "--color=auto --perl-regexp",
  multiprocess  = true, ---@type integer|boolean
  fn_transform  = [[return require("fzf-lua.make_entry").tag]],
  fn_preprocess = [[return require("fzf-lua.make_entry").preprocess]],
  file_icons    = 1, ---@type integer|boolean
  git_icons     = false,
  color_icons   = true,
  fzf_opts      = {
    ["--no-multi"]  = true,
    ["--delimiter"] = string.format("[:%s]", utils.nbsp),
    ["--tiebreak"]  = "begin",
  },
  _actions      = function() return M.globals.actions.files end,
  actions       = { ["ctrl-g"] = { actions.grep_lgrep } },
  formatter     = false,
}

---Search current buffer ctags.
---@class fzf-lua.config.Btags : fzf-lua.config.TagsBase
---@field filename? string
---@field _btags_cmd? string
---Path to the ctags binary.
---@field ctags_bin? string
---Arguments passed to ctags when generating tags.
---@field ctags_args? string
---Auto-generate ctags for the current buffer if no tags file exists.
---@field ctags_autogen? boolean
M.defaults.btags                 = {
  previewer     = { _ctor = previewers.builtin.tags },
  ctags_file    = nil, -- auto-detect
  rg_opts       = "--color=never --no-heading",
  grep_opts     = "--color=never --perl-regexp",
  multiprocess  = true, ---@type integer|boolean
  fn_transform  = [[return require("fzf-lua.make_entry").tag]],
  fn_preprocess = [[return require("fzf-lua.make_entry").preprocess]],
  file_icons    = false, ---@type integer|boolean
  git_icons     = false,
  color_icons   = true,
  ctags_autogen = true,
  fzf_opts      = {
    ["--no-multi"]  = true,
    ["--delimiter"] = string.format("[:%s]", utils.nbsp),
    ["--with-nth"]  = "1,-1",
    ["--tiebreak"]  = "begin",
  },
  _actions      = function() return M.globals.actions.files end,
  actions       = { ["ctrl-g"] = false },
  formatter     = false,
}

---Installed colorschemes.
---@class fzf-lua.config.Colorschemes: fzf-lua.config.Base
---Override the list of colorschemes to display.
---@field colors string[]
---Lua patterns to filter colorschemes.
---@field ignore_patterns string[]
---Preview colorschemes as you navigate.
---@field live_preview boolean
M.defaults.colorschemes          = {
  live_preview = true,
  winopts      = { height = 0.55, width = 0.50, backdrop = false },
  fzf_opts     = { ["--no-multi"] = true },
  actions      = { ["enter"] = actions.colorscheme },
  _headers     = { "actions" },
}

---Neovim highlight groups.
---@class fzf-lua.config.Highlights: fzf-lua.config.Base
M.defaults.highlights            = {
  fzf_opts   = { ["--no-multi"] = true },
  fzf_colors = { ["hl"] = "-1:reverse", ["hl+"] = "-1:reverse" },
  previewer  = { _ctor = previewers.builtin.highlights, },
  actions    = { ["enter"] = actions.hi }
}

---Awesome Neovim colorschemes.
---@class fzf-lua.config.AwesomeColorschemes: fzf-lua.config.Base
---Icons for download status: [downloading, downloaded, not downloaded].
---@field icons [string, string, string]
---@field _adm fzf-lua.AsyncDownloadManager
---@field dl_status integer
---@field _apply_awesome_theme function
---Preview colorschemes as you navigate.
---@field live_preview boolean
---Maximum concurrent download threads.
---@field max_threads integer
---Path to the colorschemes database JSON file.
---@field dbfile string
---Path where downloaded colorschemes will be stored.
---@field packpath string|function
M.defaults.awesome_colorschemes  = {
  winopts      = { row = 0, col = 0.99, width = 0.50, backdrop = false },
  live_preview = true,
  max_threads  = 5,
  fzf_opts     = {
    ["--multi"]     = true,
    ["--delimiter"] = "[:]",
    ["--with-nth"]  = "3..",
    ["--tiebreak"]  = "index",
  },
  dbfile       = "data/colorschemes.json",
  icons        = { utils.ansi_codes.blue("󰇚"), utils.ansi_codes.yellow(""), " " },
  packpath     = function()
    ---@diagnostic disable-next-line: assign-type-mismatch
    return path.join({ vim.fn.stdpath("cache"), "fzf-lua" })
  end,
  actions      = {
    ["enter"]  = actions.colorscheme,
    ["ctrl-g"] = { fn = actions.toggle_bg, exec_silent = true },
    ["ctrl-d"] = { fn = actions.cs_update, reload = true },
    ["ctrl-x"] = { fn = actions.cs_delete, reload = true },
  }
}

---Neovim help tags.
---@class fzf-lua.config.Helptags: fzf-lua.config.Base
---Fallback to searching all help files if no tags match.
---@field fallback? boolean
M.defaults.helptags              = {
  actions   = {
    ["enter"]  = actions.help,
    ["ctrl-s"] = actions.help,
    ["ctrl-v"] = actions.help_vert,
    ["ctrl-t"] = actions.help_tab,
  },
  fzf_opts  = {
    ["--no-multi"]  = true,
    ["--delimiter"] = string.format("[%s]", utils.nbsp),
    ["--with-nth"]  = "..-2",
    ["--tiebreak"]  = "begin",
  },
  previewer = {
    _ctor = previewers.builtin.help_tags,
  },
}

---Man pages.
---@class fzf-lua.config.Manpages: fzf-lua.config.Base
---Shell command used to list man pages.
---@field cmd string
M.defaults.manpages              = {
  cmd       = "man -k .",
  actions   = {
    ["enter"]  = actions.man,
    ["ctrl-s"] = actions.man,
    ["ctrl-v"] = actions.man_vert,
    ["ctrl-t"] = actions.man_tab,
  },
  fzf_opts  = { ["--tiebreak"] = "begin", ["--no-multi"] = true },
  previewer = "man",
}

---@class fzf-lua.config.LspBase: fzf-lua.config.Base
---@field lsp_handler? fzf-lua.LspHandler
---@field lsp_params? table|(fun(client: vim.lsp.Client, bufnr: integer): table?)
---Automatically jump to the location when there's only a single result.
---@field jump1? boolean
---Action to execute when `jump1` is triggered.
---@field jump1_action? fzf-lua.config.Action
---Set to `true` for async LSP requests, or timeout (ms) for `vim.lsp.buf_request_sync`.
---@field async_or_timeout? integer|boolean
---Reuse the current window for jumping to the location.
---@field reuse_win? boolean

---LSP references, definitions, etc.
---@class fzf-lua.config.Lsp: fzf-lua.config.LspBase
---Set to `true` for async LSP requests, or timeout (ms) for `vim.lsp.buf_request_sync`.
---@field async_or_timeout? integer|boolean
---@field symbols fzf-lua.config.LspSymbols
---@field document_symbols fzf-lua.config.LspDocumentSymbols
---@field workspace_symbols fzf-lua.config.LspWorkspaceSymbols
---@field finder fzf-lua.config.LspFinder
---@field code_actions fzf-lua.config.LspCodeActions
M.defaults.lsp                   = {
  previewer        = M._default_previewer_fn,
  file_icons       = 1, ---@type integer|boolean
  color_icons      = true,
  git_icons        = false,
  async_or_timeout = 5000,
  jump1            = true,
  jump1_action     = actions.file_edit,
  fzf_opts         = { ["--multi"] = true },
  _actions         = function() return M.globals.actions.files end,
  _cached_hls      = { "path_colnr", "path_linenr" },
  _treesitter      = true,
  -- Signals actions to use uri triggering the use of `lsp.util.show_document`
  _uri             = true,
  _headers         = { "actions", "regex_filter" },
}

---LSP symbols (shared config).
---@class fzf-lua.config.LspSymbols: fzf-lua.config.LspBase
---Initial query to filter symbols.
---@field lsp_query? string
---Custom highlight function for symbol kinds.
---@field symbol_hl? fun(s:string):string
---Custom format function for symbol display.
---@field symbol_fmt? fun(s:string, ...):string
---Display style for symbol icons, `1` for icon only, `2` for icon+name, `3` for icon+name(colored).
---@field symbol_style? integer
---Icons for each symbol kind.
---@field symbol_icons? table<string, string>
---Display child prefix (indentation) for nested symbols.
---@field child_prefix? boolean
---Display parent postfix for nested symbols.
---@field parent_postfix? boolean
---Jump to the selected symbol location in the file.
---@field locate? boolean
M.defaults.lsp.symbols           = {
  previewer        = M._default_previewer_fn,
  locate           = false,
  file_icons       = 1, ---@type integer|boolean
  color_icons      = true,
  git_icons        = false,
  symbol_style     = 1,
  symbol_icons     = {
    File          = "󰈙",
    Module        = "",
    Namespace     = "󰦮",
    Package       = "",
    Class         = "󰆧",
    Method        = "󰊕",
    Property      = "",
    Field         = "",
    Constructor   = "",
    Enum          = "",
    Interface     = "",
    Function      = "󰊕",
    Variable      = "󰀫",
    Constant      = "󰏿",
    String        = "",
    Number        = "󰎠",
    Boolean       = "󰨙",
    Array         = "󱡠",
    Object        = "",
    Key           = "󰌋",
    Null          = "󰟢",
    EnumMember    = "",
    Struct        = "󰆼",
    Event         = "",
    Operator      = "󰆕",
    TypeParameter = "󰗴",
  },
  symbol_hl        = function(s) return "@" .. s:lower() end,
  symbol_fmt       = function(s, _) return "[" .. s .. "]" end,
  child_prefix     = true,
  parent_postfix   = false,
  async_or_timeout = true,
  -- new formatting options with symbol name at the start
  fzf_opts         = {
    ["--delimiter"] = string.format("[:%s]", utils.nbsp),
    ["--tiebreak"]  = "begin",
    ["--multi"]     = true,
  },
  line_field_index = "{-2}", -- line field index
  field_index_expr = "{}",   -- entry field index
  _actions         = function() return M.globals.actions.files end,
  _uri             = true,
  _fmt             = {
    -- NOT NEEDED: we format at the source in `lsp.symbol_handler`
    -- to = function(s, _)
    --   local file, text = s:match("^(.+:.+:.+:)%s(.*)")
    --   -- fzf has alignment issues with ansi colorings of different escape length
    --   local align = 56 + utils.ansi_escseq_len(text)
    --   return string.format("%-" .. align .. "s%s%s", text, utils.nbsp, file)
    -- end,
    -- `_from` will be called by `path.entry_to_file` *before* `from` so we
    -- can combine `path.filename_first` with the symbol hardcoded formatter
    _from = function(s, _)
      -- restore the format to something that `path.entry_to_file` can
      -- handle more robustly, while this can still work due to the `utils.nbsp`
      -- it will fail when the symbol contains "[%d]" (which we use as bufnr)
      local text, file = s:match(string.format("^(.-)%s(.*)", utils.nbsp))
      return string.format("%s %s", file, text)
    end
  },
}

---LSP document symbols.
---@diagnostic disable-next-line: assign-type-mismatch
---@class fzf-lua.config.LspDocumentSymbols: fzf-lua.config.LspSymbols
---@field __sym_bufnr? integer
---@field __sym_bufname? string
M.defaults.lsp.document_symbols  = vim.tbl_deep_extend("force", {}, M.defaults.lsp.symbols, {
  git_icons   = false,
  file_icons  = false, ---@type integer|boolean
  fzf_opts    = {
    ["--tiebreak"]  = "begin",
    ["--multi"]     = true,
    ["--tabstop"]   = "4",
    ["--delimiter"] = "[:]",
    ["--with-nth"]  = utils.__IS_WINDOWS and "3.." or "2..",
  },
  _fmt        = {
    _from = function(s)
      -- Remove [<bufnr>] so  entry_to_file can parse as URI
      return s:gsub(".-" .. utils.nbsp, ""):gsub("\t\t", ": ")
    end
  },
  _cached_hls = { "path_colnr", "buf_name", "buf_nr", "buf_linenr" },
  _headers    = { "regex_filter" },
})

---LSP workspace symbols.
---@diagnostic disable-next-line: assign-type-mismatch
---@class fzf-lua.config.LspWorkspaceSymbols: fzf-lua.config.LspSymbols
---@field _headers? string[]
---@field __resume_set? function
---@field __resume_get? function
M.defaults.lsp.workspace_symbols = vim.tbl_deep_extend("force", {}, M.defaults.lsp.symbols, {
  exec_empty_query = true,
  actions          = { ["ctrl-g"] = { actions.sym_lsym } },
  _cached_hls      = { "live_sym", "path_colnr", "path_linenr" },
  _headers         = { "actions", "cwd", "regex_filter" },
})

---All LSP locations combined.
---@class fzf-lua.config.LspFinder: fzf-lua.config.LspBase
---Use async LSP requests.
---@field async boolean
---Separator between provider prefix and entry text.
---@field separator string
---@field _providers table<string, boolean>
---List of LSP providers to query, e.g. `{ "references", "definitions" }`.
---@field providers table
---Do not automatically close the picker when a single result is found.
---@field no_autoclose boolean
M.defaults.lsp.finder            = {
  previewer   = M._default_previewer_fn,
  file_icons  = 1, ---@type integer|boolean
  color_icons = true,
  git_icons   = false,
  async       = true,
  silent      = true,
  separator   = "|" .. utils.nbsp,
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
    type_sub        = true,
    type_super      = true,
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
    { "type_sub",        prefix = utils.ansi_codes.cyan("sub ") },
    { "type_super",      prefix = utils.ansi_codes.yellow("supr") },
  },
  fzf_opts    = { ["--multi"] = true },
  _treesitter = true,
  _cached_hls = { "path_colnr", "path_linenr" },
  _headers    = { "actions", "regex_filter" },
  _uri        = true,
}

---LSP code actions.
---@class fzf-lua.config.LspCodeActions: fzf-lua.config.LspBase
---Callback to execute after applying a code action.
---@field post_action_cb function
---Code action context passed to the LSP server.
---@field context lsp.CodeActionContext
---Filter function to exclude certain code actions.
---@field filter fun(x: lsp.CodeAction|lsp.Command):boolean
---@field _ui_select? { kind: string }
---@field _items any[]
M.defaults.lsp.code_actions      = {
  async_or_timeout = 5000,
  previewer        = "codeaction",
  -- previewer        = "codeaction_native",
  fzf_opts         = { ["--no-multi"] = true },
  -- NOTE: we don't need an action as code actions are executed by the ui.select
  -- callback but we setup an empty table to indicate to `globals.__index` that
  -- we need to inherit from the global defaults (#1232)
  actions          = {},
}

---Workspace/document diagnostics.
---@class fzf-lua.config.Diagnostics: fzf-lua.config.Base
---Override default diagnostic signs.
---@field signs? table
---Filter diagnostics by exact severity.
---@field severity_only? vim.diagnostic.SeverityFilter
---Filter diagnostics up to and including this severity level.
---@field severity_limit? vim.diagnostic.Severity|1|2|3|4
---Filter diagnostics from this severity level and below.
---@field severity_bound? vim.diagnostic.Severity|1|2|3|4
---Filter diagnostics by namespace.
---@field namespace? integer
---Include all workspace diagnostics (not just current buffer).
---@field diag_all? boolean
---Filter diagnostics by LSP client ID.
---@field client_id? integer
---Sort diagnostics by severity, set to `false` to disable sorting.
---@field sort? integer|boolean
---Add padding after diagnostic icons for alignment.
---@field icon_padding? boolean
---Display diagnostic icons.
---@field diag_icons? boolean
---Display diagnostic source (e.g. `lua_ls`, `eslint`).
---@field diag_source? boolean
---Display diagnostic code.
---@field diag_code? boolean
---Enable multiline diagnostics display, set to a number for max lines.
---@field multiline? integer|boolean
---Color the file/buffer headings.
---@field color_headings? boolean
M.defaults.diagnostics           = {
  previewer      = M._default_previewer_fn,
  file_icons     = false, ---@type integer|boolean
  color_icons    = true,
  color_headings = true,
  git_icons      = false,
  diag_icons     = true,
  diag_source    = true,
  diag_code      = true,
  multiline      = 2, ---@type integer|boolean
  fzf_opts       = {
    ["--multi"] = true,
    ["--wrap"]  = true,
  },
  _actions       = function() return M.globals.actions.files end,
  _cached_hls    = { "path_colnr", "path_linenr" },
  _headers       = { "actions", "cwd" },
  -- signs = {
  --   ["Error"] = { text = "e", texthl = "DiagnosticError" },
  --   ["Warn"]  = { text = "w", texthl = "DiagnosticWarn" },
  --   ["Info"]  = { text = "i", texthl = "DiagnosticInfo" },
  --   ["Hint"]  = { text = "h", texthl = "DiagnosticHint" },
  -- },
}

---Fzf-lua builtin commands.
---@class fzf-lua.config.Builtin: fzf-lua.config.Base
---@field metatable table
---@field metatable_exclude table
M.defaults.builtin               = {
  no_resume = true,
  winopts   = { height = 0.65, width = 0.50, preview = { hidden = true } },
  fzf_opts  = { ["--no-multi"] = true },
  preview   = function(args)
    local options_md = require("fzf-lua.cmd").options_md()
    return type(options_md) == "table" and options_md[args[1]:lower()] or ""
  end,
  actions   = { ["enter"] = actions.run_builtin },
}

---Fzf-lua configuration profiles.
---@class fzf-lua.config.Profiles: fzf-lua.config.Base
---@field load fzf-lua.profile
M.defaults.profiles              = {
  previewer = M._default_previewer_fn,
  fzf_opts  = {
    ["--delimiter"] = "[:]",
    ["--with-nth"]  = "-1..",
    ["--tiebreak"]  = "begin",
    ["--no-multi"]  = true,
  },
  actions   = { ["enter"] = actions.apply_profile },
}

---Neovim marks.
---@class fzf-lua.config.Marks: fzf-lua.config.Base
---Lua pattern to filter marks.
---@field marks? string
---Sort marks alphabetically. Set to `false` to maintain original order.
---@field sort? boolean
M.defaults.marks                 = {
  sort        = false,
  fzf_opts    = { ["--no-multi"] = true },
  actions     = {
    ["enter"] = actions.goto_mark,
    ["ctrl-s"] = actions.goto_mark_split,
    ["ctrl-v"] = actions.goto_mark_vsplit,
    ["ctrl-t"] = actions.goto_mark_tabedit,
    ["ctrl-x"] = { fn = actions.mark_del, reload = true }
  },
  previewer   = { _ctor = previewers.builtin.marks },
  _cached_hls = { "buf_nr", "path_linenr", "path_colnr" },
}

---Change list.
---@class fzf-lua.config.Changes: fzf-lua.config.Jumps
M.defaults.changes               = {
  cmd       = "changes",
  h1        = "change",
  actions   = { ["enter"] = actions.goto_jump },
  previewer = { _ctor = previewers.builtin.jumps },
}

---Jump list.
---@class fzf-lua.config.Jumps: fzf-lua.config.Base
---@field cmd string
---@field h1 string
M.defaults.jumps                 = {
  cmd       = "jumps",
  fzf_opts  = { ["--no-multi"] = true },
  actions   = { ["enter"] = actions.goto_jump },
  previewer = { _ctor = previewers.builtin.jumps },
}

---Tag stack.
---@class fzf-lua.config.Tagstack: fzf-lua.config.Base
M.defaults.tagstack              = {
  file_icons  = 1, ---@type integer|boolean
  color_icons = true,
  git_icons   = true,
  fzf_opts    = { ["--multi"] = true },
  previewer   = M._default_previewer_fn,
  _actions    = function() return M.globals.actions.files end,
}

---Neovim commands.
---@class fzf-lua.config.Commands: fzf-lua.config.Base
---Table of commands to flatten (display without subcommands).
---@field flatten table<string, boolean>
---Include builtin Neovim commands.
---@field include_builtin boolean
---Sort commands by last used.
---@field sort_lastused boolean
M.defaults.commands              = {
  actions         = { ["enter"] = actions.ex_run },
  flatten         = {},
  include_builtin = true,
  _cached_hls     = { "cmd_ex", "cmd_buf", "cmd_global" },
}

---Neovim autocommands.
---@class fzf-lua.config.Autocmds: fzf-lua.config.Base
---Show the description field for autocommands in the list.
---@field show_desc boolean
M.defaults.autocmds              = {
  show_desc = true, -- show desc field in fzf list
  previewer = { _ctor = previewers.builtin.autocmds },
  _actions  = function() return M.globals.actions.files end,
  fzf_opts  = {
    ["--delimiter"] = "[│]",
    ["--with-nth"]  = "2..",
    ["--no-multi"]  = true,
  },
}

---Undo tree.
---@class fzf-lua.config.Undotree: fzf-lua.config.Base
---@field __locate_pos? integer
---Jump to the current undo position on picker open.
---@field locate boolean
M.defaults.undotree              = {
  previewer      = "undotree",
  locate         = true,
  fzf_opts       = { ["--no-multi"] = true },
  actions        = { ["enter"] = actions.undo },
  _cached_hls    = { "buf_linenr", "buf_name", "path_linenr", "dir_part" },
  _resume_reload = true,
  keymap         = { builtin = { ["<F8>"] = "toggle-preview-undo" } },
}

---Command history.
---@class fzf-lua.config.CommandHistory: fzf-lua.config.Base
---Reverse the order of the history list (oldest first).
---@field reverse_list? boolean
M.defaults.command_history       = {
  fzf_opts    = { ["--tiebreak"] = "index", ["--no-multi"] = true },
  render_crlf = true,
  _treesitter = function(line) return "foo.vim", nil, line end,
  fzf_colors  = { ["hl"] = "-1:reverse", ["hl+"] = "-1:reverse" },
  actions     = {
    ["enter"]  = actions.ex_run_cr,
    ["ctrl-e"] = actions.ex_run,
    ["ctrl-x"] = { fn = actions.ex_del, field_index = "{+n}", reload = true }
  },
  _headers    = { "actions" },
}

---Search history.
---@class fzf-lua.config.SearchHistory : fzf-lua.config.CommandHistory
---Reverse the order of the history list (oldest first).
---@field reverse_list? boolean
---Also search in reverse direction.
---@field reverse_search? boolean
M.defaults.search_history        = {
  fzf_opts    = { ["--tiebreak"] = "index", ["--no-multi"] = true },
  render_crlf = true,
  _treesitter = function(line) return "", nil, line, "regex" end,
  fzf_colors  = { ["hl"] = "-1:reverse", ["hl+"] = "-1:reverse" },
  actions     = {
    ["enter"]  = actions.search_cr,
    ["ctrl-e"] = actions.search,
    ["ctrl-x"] = { fn = actions.search_del, field_index = "{+n}", reload = true }
  },
  _headers    = { "actions" },
}

---Neovim registers.
---@class fzf-lua.config.Registers: fzf-lua.config.Base
---Lua pattern or function to filter registers.
---@field filter string|function
---Display multiline register contents, set to a number for max lines.
---@field multiline? integer|boolean
---Ignore empty registers.
---@field ignore_empty? boolean
M.defaults.registers             = {
  multiline    = true, ---@type integer|boolean
  ignore_empty = true,
  actions      = { ["enter"] = actions.paste_register },
  fzf_opts     = { ["--no-multi"] = true },
}

---Neovim keymaps.
---@class fzf-lua.config.Keymaps: fzf-lua.config.Base
---Lua patterns to filter keymaps.
---@field ignore_patterns string[]
---Show the description field for keymaps in the list.
---@field show_desc boolean
---Show additional keymap details (buffer, noremap, etc).
---@field show_details boolean
---List of modes to include, e.g. `{ "n", "i", "v" }`.
---@field modes string[]
M.defaults.keymaps               = {
  previewer       = { _ctor = previewers.builtin.keymaps },
  winopts         = { preview = { layout = "vertical" } },
  fzf_opts        = { ["--tiebreak"] = "index", ["--no-multi"] = true },
  ignore_patterns = { "^<SNR>", "^<Plug>" },
  show_desc       = true,
  show_details    = true,
  actions         = {
    ["enter"]  = actions.keymap_apply,
    ["ctrl-s"] = actions.keymap_split,
    ["ctrl-v"] = actions.keymap_vsplit,
    ["ctrl-t"] = actions.keymap_tabedit,
  },
}

---Neovim options.
---@class fzf-lua.config.NvimOptions: fzf-lua.config.Base
---Separator between option name and value.
---@field separator string
---Colorize option values.
---@field color_values boolean
M.defaults.nvim_options          = {
  previewer    = { _ctor = previewers.builtin.nvim_options },
  separator    = "│",
  color_values = true,
  actions      = {
    ["enter"]     = { fn = actions.nvim_opt_edit_local, reload = true },
    ["alt-enter"] = { fn = actions.nvim_opt_edit_global, reload = true },
  },
  fzf_opts     = {
    ["--nth"] = 1,
    ["--delimiter"] = "[│]",
    ["--no-multi"] = true,
  },
}

---Spelling suggestions.
---@class fzf-lua.config.SpellSuggest: fzf-lua.config.Base
---The pattern used to match the word under the cursor. Text around the cursor position that matches will be used as the initial query and replaced by a chosen completion. The default matches anything but spaces and single/double quotes.
---@field word_pattern? string
M.defaults.spell_suggest         = {
  winopts = {
    relative = "cursor",
    row      = 1,
    col      = 0,
    height   = 0.40,
    width    = 0.30,
  },
  actions = {
    ["enter"] = actions.complete,
  },
}

---Neovim server list.
---@class fzf-lua.config.Serverlist : fzf-lua.config.Base
---@field _screenshot string
M.defaults.serverlist            = {
  _screenshot = vim.fn.tempname(),
  previewer = { _ctor = previewers.fzf.nvim_server },
  _resume_reload = true, -- avoid list contain killed server unhide
  actions = {
    ["enter"] = actions.serverlist_connect,
    ["ctrl-o"] = { fn = actions.serverlist_spawn, reload = true, header = "spawn" },
    ["ctrl-x"] = { fn = actions.serverlist_kill, reload = true, header = "kill" },
    ["ctrl-r"] = { fn = function() end, reload = true, header = "reload" },
  },
}


---Filetypes.
---@class fzf-lua.config.Filetypes : fzf-lua.config.Base
M.defaults.filetypes         = {
  file_icons = false, ---@type integer|boolean
  actions    = { ["enter"] = actions.set_filetype },
}

---`:packadd <package>`.
---@class fzf-lua.config.Packadd : fzf-lua.config.Base
M.defaults.packadd           = {
  actions = {
    ["enter"] = actions.packadd,
  },
}

---Neovim menus.
---@class fzf-lua.config.Menus : fzf-lua.config.Base
M.defaults.menus             = {
  actions = {
    ["enter"] = actions.exec_menu,
  },
}

---Tmux integration pickers.
---@class fzf-lua.config.Tmux
---@field buffers fzf-lua.config.TmuxBuffers
---@field cmd string
M.defaults.tmux              = {
  ---Tmux paste buffers.
  ---@class fzf-lua.config.TmuxBuffers: fzf-lua.config.Base
  buffers = {
    cmd      = "tmux list-buffers",
    register = [["]],
    actions  = { ["enter"] = actions.tmux_buf_set_reg },
    fzf_opts = { ["--no-multi"] = true, ["--delimiter"] = "[:]" }
  },
}

---DAP (Debug Adapter Protocol) pickers.
---@class fzf-lua.config.DapBase: fzf-lua.config.Base
---@field commands fzf-lua.config.DapCommands
---@field configurations fzf-lua.config.DapConfigurations
---@field variables fzf-lua.config.DapVariables
---@field frames fzf-lua.config.DapFrames
---@field breakpoints fzf-lua.config.DapBreakpoints

---DAP pickers parent table.
---@class fzf-lua.config.Dap
M.defaults.dap               = {
  ---DAP builtin commands.
  ---@class fzf-lua.config.DapCommands: fzf-lua.config.DapBase
  commands       = { fzf_opts = { ["--no-multi"] = true }, },
  ---DAP configurations.
  ---@class fzf-lua.config.DapConfigurations: fzf-lua.config.DapBase
  configurations = { fzf_opts = { ["--no-multi"] = true }, },
  ---DAP active session variables.
  ---@class fzf-lua.config.DapVariables: fzf-lua.config.DapBase
  variables      = { fzf_opts = { ["--no-multi"] = true }, },
  ---DAP active session frames.
  ---@class fzf-lua.config.DapFrames: fzf-lua.config.DapBase
  frames         = { fzf_opts = { ["--no-multi"] = true }, },
  ---DAP breakpoints.
  ---@class fzf-lua.config.DapBreakpoints: fzf-lua.config.DapBase
  breakpoints    = {
    file_icons  = 1, ---@type integer|boolean
    color_icons = true,
    git_icons   = false,
    previewer   = M._default_previewer_fn,
    _actions    = function() return M.globals.actions.files end,
    actions     = { ["ctrl-x"] = { fn = actions.dap_bp_del, reload = true } },
    fzf_opts    = {
      ["--delimiter"] = "[\\]:]",
      ["--with-nth"]  = "2..",
    },
    _cached_hls = { "path_colnr", "path_linenr" },
    _headers    = { "actions", "cwd" },
  },
}

---Complete path under cursor (incl dirs).
---@class fzf-lua.config.CompletePath: fzf-lua.config.Base
---@field cmd? string
---Pattern to match the word under cursor for initial query and replacement.
---@field word_pattern? string
M.defaults.complete_path     = {
  file_icons        = false, ---@type integer|boolean
  git_icons         = false,
  color_icons       = true,
  multiprocess      = 1, ---@type integer|boolean
  _type             = "file",
  fzf_opts          = { ["--no-multi"] = true },
  _fzf_nth_devicons = true,
  actions           = { ["enter"] = actions.complete },
}

---Complete file under cursor (excl dirs).
---@class fzf-lua.config.CompleteFile: fzf-lua.config.Base
---@field cmd? string
---Pattern to match the word under cursor for initial query and replacement.
---@field word_pattern? string
M.defaults.complete_file     = {
  multiprocess      = 1, ---@type integer|boolean
  _type             = "file",
  file_icons        = 1, ---@type integer|boolean
  color_icons       = true,
  git_icons         = false,
  _actions          = function() return M.globals.actions.files end,
  actions           = { ["enter"] = actions.complete },
  previewer         = M._default_previewer_fn,
  winopts           = { preview = { hidden = true } },
  fzf_opts          = { ["--no-multi"] = true },
  _fzf_nth_devicons = true,
}

---Zoxide recent directories.
---@class fzf-lua.config.Zoxide: fzf-lua.config.Base
---Scope of the `cd` action, possible values are `local|win|tab|global`.
---@field scope? string
---Change to the git root directory instead of the zoxide path.
---@field git_root? boolean
M.defaults.zoxide            = {
  multiprocess  = true, ---@type integer|boolean
  fn_transform  = [[return require("fzf-lua.make_entry").zoxide]],
  fn_preprocess = [[return require("fzf-lua.make_entry").preprocess]],
  cmd           = "zoxide query --list --score",
  scope         = "global",
  git_root      = false,
  formatter     = "path.dirname_first",
  fzf_opts      = {
    ["--no-multi"]  = true,
    ["--delimiter"] = "[\t]",
    ["--tabstop"]   = "4",
    ["--tiebreak"]  = "end,index",
    ["--nth"]       = "2..",
    ["--no-sort"]   = true, -- sort by score
  },
  actions       = { enter = actions.zoxide_cd }
}

---Complete line (all open buffers).
---@class fzf-lua.config.CompleteLine: fzf-lua.config.Blines
---@field current_buffer_only? boolean
---@field complete? (fun(s: string[], _o: fzf-lua.config.Resolved, l: string, c: integer):string?, integer?)|boolean
M.defaults.complete_line     = vim.tbl_deep_extend("force", M.defaults.blines, {
  complete = true,
})

M.defaults.file_icon_padding = ""

-- No need to sset this, already defaults to `nvim_open_win`
-- M.help_open_win              = vim.api.nvim_open_win

M.defaults.dir_icon          = ""

---@class fzf-lua.config.HLS
---Main fzf (terminal) window normal (text/bg) highlight group.
---@field normal string
---Main fzf (terminal) window border highlight group.
---@field border string
---Main fzf (terminal) window title highlight group.
---@field title string
---Main fzf (terminal) window title flags highlight group (hidden, etc).
---@field title_flags string
---Backdrop color, black by default, used to darken the background color when opening the UI.
---@field backdrop string
---Help window (F1) normal (text/bg) highlight group.
---@field help_normal string
---Help window (F1) border highlight group.
---@field help_border string
---Builtin previewer window normal (text/bg) highlight group.
---@field preview_normal string
---Builtin previewer window border highlight group.
---@field preview_border string
---Builtin previewer window title highlight group.
---@field preview_title string
---Builtin previewer window `Cursor` highlight group.
---@field cursor string
---Builtin previewer window `CursorLine` highlight group.
---@field cursorline string
---Builtin previewer window `CursorLineNr` highlight group.
---@field cursorlinenr string
---Builtin previewer window search matches highlight group.
---@field search string
---Builtin previewer window `border` scrollbar empty highlight group.
---@field scrollborder_e string
---Builtin previewer window `border` scrollbar full highlight group.
---@field scrollborder_f string
---Builtin previewer window `float` scrollbar empty highlight group.
---@field scrollfloat_e string
---Builtin previewer window `float` scrollbar full highlight group.
---@field scrollfloat_f string|false
---Interactive headers keybind highlight group, e.g. `<ctrl-g> to Disable .gitignore`.
---@field header_bind string
---Interactive headers description highlight group, e.g. `<ctrl-g> to Disable .gitignore`.
---@field header_text string
---Highlight group for the column part of paths, e.g. `file:<line>:<col>:`, used in pickers such as `buffers`, `quickfix`, `lsp`, `diagnostics`, etc.
---@field path_colnr string
---Highlight group for the line part of paths, e.g. `file:<line>:<col>:`, used in pickers such as `buffers`, `quickfix`, `lsp`, `diagnostics`, etc.
---@field path_linenr string
---Highlight group for buffer name (filepath) in `lines`.
---@field buf_name string
---Highlight group for buffer id (number) in `lines`.
---@field buf_id string
---Highlight group for buffer number in `buffers`, `tabs`.
---@field buf_nr string
---Highlight group for buffer line number in `lines`, `blines` and `treesitter`.
---@field buf_linenr string
---Highlight group for the current buffer flag in `buffers`, `tabs`.
---@field buf_flag_cur string
---Highlight group for the alternate buffer flag in `buffers`, `tabs`.
---@field buf_flag_alt string
---Highlight group for the tab title in `tabs`.
---@field tab_title string
---Highlight group for the current tab marker in `tabs`.
---@field tab_marker string
---Highlight group for the directory icon in paths that end with a separator, usually used in path completion, e.g. `complete_path`.
---@field dir_icon string
---Highlight group for the directory part when using `path.dirname_first` or `path.filename_first` formatters.
---@field dir_part string
---Highlight group for the directory part when using `path.dirname_first` or `path.filename_first` formatters.
---@field file_part string
---Highlight group for the prompt text in "live" pickers.
---@field live_prompt string
---Highlight group for the matched characters in `lsp_live_workspace_symbols`.
---@field live_sym string
---Highlight group for ex commands in `:FzfLua commands`, by default links to `Statement`.
---@field cmd_ex string
---Highlight group for buffer commands in `:FzfLua commands`, by default links to `Added`.
---@field cmd_buf string
---Highlight group for global commands in `:FzfLua commands`, by default links to `Directory`.
---@field cmd_global string
---@field fzf fzf-lua.config.fzfHLS
M.defaults.__HLS             = {
  normal         = "FzfLuaNormal",
  border         = "FzfLuaBorder",
  title          = "FzfLuaTitle",
  title_flags    = "FzfLuaTitleFlags",
  backdrop       = "FzfLuaBackdrop",
  help_normal    = "FzfLuaHelpNormal",
  help_border    = "FzfLuaHelpBorder",
  preview_normal = "FzfLuaPreviewNormal",
  preview_border = "FzfLuaPreviewBorder",
  preview_title  = "FzfLuaPreviewTitle",
  cursor         = "FzfLuaCursor",
  cursorline     = "FzfLuaCursorLine",
  cursorlinenr   = "FzfLuaCursorLineNr",
  search         = "FzfLuaSearch",
  scrollborder_e = "FzfLuaScrollBorderEmpty",
  scrollborder_f = "FzfLuaScrollBorderFull",
  scrollfloat_e  = "FzfLuaScrollFloatEmpty",
  scrollfloat_f  = "FzfLuaScrollFloatFull",
  header_bind    = "FzfLuaHeaderBind",
  header_text    = "FzfLuaHeaderText",
  path_colnr     = "FzfLuaPathColNr",
  path_linenr    = "FzfLuaPathLineNr",
  buf_name       = "FzfLuaBufName",
  buf_id         = "FzfLuaBufId",
  buf_nr         = "FzfLuaBufNr",
  buf_linenr     = "FzfLuaBufLineNr",
  buf_flag_cur   = "FzfLuaBufFlagCur",
  buf_flag_alt   = "FzfLuaBufFlagAlt",
  tab_title      = "FzfLuaTabTitle",
  tab_marker     = "FzfLuaTabMarker",
  dir_icon       = "FzfLuaDirIcon",
  dir_part       = "FzfLuaDirPart",
  file_part      = "FzfLuaFilePart",
  live_prompt    = "FzfLuaLivePrompt",
  live_sym       = "FzfLuaLiveSym",
  cmd_ex         = "FzfLuaCmdEx",
  cmd_buf        = "FzfLuaCmdBuf",
  cmd_global     = "FzfLuaCmdGlobal",
  ---@class fzf-lua.config.fzfHLS
  ---Highlight group for fzf's `fg` and `bg`, by default links to `FzfLuaNormal`.
  ---@field normal string
  ---Highlight group for fzf's `fg+` and `bg+`, by default links to `FzfLuaCursorLine`.
  ---@field cursorline string
  ---Highlight group for fzf's `hl+`, by default links to `Special`.
  ---@field match string
  ---Highlight group for fzf's `border`, by default links to `FzfLuaBorder`.
  ---@field border string
  ---Highlight group for fzf's `scrollbar`, by default links to `FzfLuaFzfBorder`.
  ---@field scrollbar string
  ---Highlight group for fzf's `separator`, by default links to `FzfLuaFzfBorder`.
  ---@field separator string
  ---Highlight group for fzf's `gutter`, by default links to `FzfLuaFzfBorder`. NOTE: `bg` property of the highlight group will be used.
  ---@field gutter string
  ---Highlight group for fzf's `header`, by default links to `FzfLuaTitle`.
  ---@field header string
  ---Highlight group for fzf's `info`, by default links to `NonText`.
  ---@field info string
  ---Highlight group for fzf's `pointer`, by default links to `Special`.
  ---@field pointer string
  ---Highlight group for fzf's `marker`, by default links to `FzfLuaFzfPointer`.
  ---@field marker string
  ---Highlight group for fzf's `spinner`, by default links to `FzfLuaFzfPointer`.
  ---@field spinner string
  ---Highlight group for fzf's `prompt`, by default links to `Special`.
  ---@field prompt string
  ---Highlight group for fzf's `query`, by default links to `FzfLuaNormal` and sets text to `regular` (non-bold).
  ---@field query string
  fzf            = {
    normal     = "FzfLuaFzfNormal",
    cursorline = "FzfLuaFzfCursorLine",
    match      = "FzfLuaFzfMatch",
    border     = "FzfLuaFzfBorder",
    scrollbar  = "FzfLuaFzfScrollbar",
    separator  = "FzfLuaFzfSeparator",
    gutter     = "FzfLuaFzfGutter",
    header     = "FzfLuaFzfHeader",
    info       = "FzfLuaFzfInfo",
    pointer    = "FzfLuaFzfPointer",
    marker     = "FzfLuaFzfMarker",
    spinner    = "FzfLuaFzfSpinner",
    prompt     = "FzfLuaFzfPrompt",
    query      = "FzfLuaFzfQuery",
  }
}

return M
