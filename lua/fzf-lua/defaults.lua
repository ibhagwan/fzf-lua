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
---Height of the fzf-lua float
---between 0-1 will represent percentage of `vim.o.lines` (1: max height)
---if >= 1 will use fixed number of lines.
---@field height? number
---Width of the fzf-lua float
---between 0-1 will represent percentage of `vim.o.columns` (1: max width)
---if >= 1 will use fixed number of columns.
---@field width? number
---Screen row where to place the fzf-lua float window
---between 0-1 will represent percentage of `vim.o.lines` (0: top, 1: bottom)
---if >= 1 will attempt to place the float in the exact screen line.
---@field row? number
---Screen column where to place the fzf-lua float window
---between 0-1 will represent percentage of `vim.o.columns` (0: leftmost, 1: rightmost)
---if >= 1 will attempt to place the float in the exact screen column.
---@field col? number
---@field preview? fzf-lua.config.PreviewOpts Preview window configuration.
---@field split? string|function|false Neovim split command to use for fzf-lua interface, e.g `belowright new`.
---@field backdrop? number|boolean Backdrop opacity, 0-100, or false to disable (requires Neovim >= 0.10).
---@field fullscreen? boolean Open fzf-lua in fullscreen.
---@field treesitter? fzf-lua.config.TreesitterWinopts Use treesitter highlighting in fzf's main window.
---@field on_create? fun(e: { winid?: integer, bufnr?: integer }) Callback after the creation of the fzf-lua main terminal window.
---@field on_close? fun() Callback after closing the fzf-lua window.
---@field toggle_behavior? string Toggle behavior for fzf-lua window.
---@field winblend? boolean Enable window transparency.
---@field winhl? boolean Enable window highlight groups.
---@field cursorline? boolean Highlight the current line in main window.
---@field __winhls? { main: [string, string?][], prev: [string, string?][] } Internal window highlight mappings.

---@class fzf-lua.config.PreviewOpts
---@field default? string Default previewer for file pickers, possible values `builtin|bat|cat|head`.
---@field border? any Preview border for native fzf previewers, set to `noborder` to hide.
---@field wrap? boolean Line wrap in both native fzf and the builtin previewer.
---@field hidden? boolean Preview startup visibility in both native fzf and the builtin previewer.
---@field vertical? string Vertical preview layout, mapped to fzf's `--preview-window` flag.
---@field horizontal? string Horizontal preview layout, mapped to fzf's `--preview-window` flag.
---@field layout? string Preview layout, possible values are `horizontal|vertical|flex`.
---@field flip_columns? integer Auto-detect the preview layout based on available width.
---@field title? any Show preview title.
---@field title_pos? "center"|"left"|"right" Preview title position.
---@field scrollbar? string Preview window scrollbar (`border|float`).
---@field scrolloff? integer Preview window scrolloff.
---@field delay? integer Debounce time (milliseconds) for displaying the preview buffer in the builtin previewer.
---@field winopts fzf-lua.config.PreviewerWinopts Window options for the builtin previewer.

---missing fields are injected later, not sure how to tell luals about it
---@class fzf-lua.config.Defaults: fzf-lua.config.Base,{}
---@field nbsp string Special invisible unicode character used as text delimiter.
---@field winopts fzf-lua.config.Winopts Window options.
---@field keymap fzf-lua.config.Keymap Keymaps for builtin and fzf commands.
---@field actions table<string, fzf-lua.config.Actions> Actions to execute on selected items.
---@field fzf_bin string? Path to fzf binary.
---@field previewers fzf-lua.config.Previewers Previewer configurations.
---@field formatters table<string, any> Entry formatters.
---@field zoxide fzf-lua.config.Zoxide Zoxide integration configuration.
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
      ---@field number boolean Show line numbers in preview.
      ---@field relativenumber boolean Show relative line numbers in preview.
      ---@field cursorline boolean Highlight current line in preview.
      ---@field cursorlineopt string Cursorline option for preview.
      ---@field cursorcolumn boolean Highlight current column in preview.
      ---@field signcolumn string Sign column option for preview.
      ---@field list boolean Show invisible characters in preview.
      ---@field foldenable boolean Enable code folding in preview.
      ---@field foldmethod string Fold method for preview.
      ---@field scrolloff integer Scrolloff option for preview.
      ---@field winblend integer Window transparency for preview.
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

---@class fzf-lua.config.Files: fzf-lua.config.Base
---@field cmd? string -- default: auto detect find|fd
---@field ignore_current_file? boolean
---@field file_ignore_patterns? string[]
---@field line_query? boolean|fun(query: string): lnum: string?, new_query: string?
---@field raw_cmd? string
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
---@field git_dir? string
---@field cmd string

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
  ---@class fzf-lua.config.GitDiff: fzf-lua.config.GitBase
  diff = {
    cmd               = "git --no-pager diff --name-only {ref}",
    ref               = "HEAD",
    preview           = "git diff {ref} {file}",
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
  ---@class fzf-lua.config.GitHunks: fzf-lua.config.GitBase
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
  ---@class fzf-lua.config.GitBranches: fzf-lua.config.GitBase
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
  ---@class fzf-lua.config.GitWorktrees: fzf-lua.config.GitBase
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

---@class fzf-lua.config.Grep: fzf-lua.config.Base
---@field cmd? string default: auto detect rg|grep
---@field rg_glob? boolean|integer
---@field rg_glob_fn? fun(query: string, opts: table): string, string
---@field raw_cmd? string
---@field search? string
---@field no_esc? integer|boolean
---@field lgrep? boolean grep or lgrep
---@field search_paths? string[]
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
  _treesitter    = true,
  _headers       = { "actions", "cwd" },
}

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

---@class fzf-lua.config.Args: fzf-lua.config.Base
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

---@class fzf-lua.config.Oldfiles: fzf-lua.config.Base
---@field stat_file? boolean
---@field include_current_session? boolean
M.defaults.oldfiles              = {
  previewer         = M._default_previewer_fn,
  file_icons        = 1, ---@type integer|boolean
  color_icons       = true,
  git_icons         = false,
  stat_file         = true,
  fzf_opts          = { ["--tiebreak"] = "index", ["--multi"] = true },
  _fzf_nth_devicons = true,
  _actions          = function() return M.globals.actions.files end,
  _headers          = { "cwd" },
}

---@class fzf-lua.config.Quickfix: fzf-lua.config.Base
---@field separator string
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

---@class fzf-lua.config.QuickfixStack: fzf-lua.config.Base
---@field marker string
M.defaults.quickfix_stack        = {
  marker    = ">",
  previewer = { _ctor = previewers.builtin.quickfix, },
  fzf_opts  = { ["--no-multi"] = true },
  actions   = { ["enter"] = actions.set_qflist, },
}

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

---@class fzf-lua.config.LoclistStack : fzf-lua.config.QuickfixStack: fzf-lua.config.Base
---@field is_loclist true
M.defaults.loclist_stack         = {
  marker    = ">",
  previewer = { _ctor = previewers.builtin.quickfix, },
  fzf_opts  = { ["--no-multi"] = true },
  actions   = { ["enter"] = actions.set_qflist, },
}

---@class fzf-lua.config.Buffers: fzf-lua.config.BufferLines
---@field filename_only? boolean
---@field cwd? string
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

---@class fzf-lua.config.Tabs: fzf-lua.config.BufferLines
---@field filename_only? boolean
---@field __locate_pos? integer
---@field current_tab_only? boolean
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

---@class fzf-lua.config.Lines: fzf-lua.config.BufferLines
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

---@class fzf-lua.config.Treesitter: fzf-lua.config.Base
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

---@class fzf-lua.config.Spellcheck: fzf-lua.config.BufferLines
---@field word_separator string
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
---@field ctags_file? string auto-detect
---@field cmd? string
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

---@class fzf-lua.config.Btags : fzf-lua.config.TagsBase
---@field filename? string
---@field _btags_cmd? string
---@field ctags_bin? string
---@field ctags_args? string
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

---@class fzf-lua.config.Colorschemes: fzf-lua.config.Base
---@field colors string[] overriden colorscheme list
---@field ignore_patterns string[] lua patterns to filter colorschemes
M.defaults.colorschemes          = {
  live_preview = true,
  winopts      = { height = 0.55, width = 0.50, backdrop = false },
  fzf_opts     = { ["--no-multi"] = true },
  actions      = { ["enter"] = actions.colorscheme },
  _headers     = { "actions" },
}

---@class fzf-lua.config.Highlights: fzf-lua.config.Base
M.defaults.highlights            = {
  fzf_opts   = { ["--no-multi"] = true },
  fzf_colors = { ["hl"] = "-1:reverse", ["hl+"] = "-1:reverse" },
  previewer  = { _ctor = previewers.builtin.highlights, },
  actions    = { ["enter"] = actions.hi }
}

---@class fzf-lua.config.AwesomeColorschemes: fzf-lua.config.Base
---@field icons [string, string, string]
---@field _adm fzf-lua.AsyncDownloadManager
---@field dl_status integer
---@field _apply_awesome_theme function
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

---@class fzf-lua.config.Helptags: fzf-lua.config.Base
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

---@class fzf-lua.config.Manpages: fzf-lua.config.Base
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
---@field jump1? boolean
---@field jump1_action? fzf-lua.config.Action
---@field async_or_timeout? integer|boolean
---@field reuse_win? boolean

---@class fzf-lua.config.Lsp: fzf-lua.config.LspBase
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

---@class fzf-lua.config.LspSymbols: fzf-lua.config.LspBase
---@field lsp_query? string
---@field symbol_hl? fun(s:string):string
---@field symbol_fmt? fun(s:string, ...):string
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

---@class fzf-lua.config.LspFinder: fzf-lua.config.LspBase
---@field async boolean
---@field separator string
---@field _providers table<string, boolean>
---@field providers table
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

---@class fzf-lua.config.LspCodeActions: fzf-lua.config.LspBase
---@field post_action_cb function
---@field context lsp.CodeActionContext
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

---@class fzf-lua.config.Diagnostics: fzf-lua.config.Base
---@field signs? table
---@field severity_only? vim.diagnostic.SeverityFilter
---@field severity_limit? vim.diagnostic.Severity|1|2|3|4
---@field severity_bound? vim.diagnostic.Severity|1|2|3|4
---@field namespace? integer
---@field diag_all? boolean
---@field client_id? integer
---@field sort? integer|boolean
---@field icon_padding? boolean
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

---@class fzf-lua.config.Marks: fzf-lua.config.Base
---@field marks? string lua pattern to filter marks
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

---@class fzf-lua.config.Changes: fzf-lua.config.Jumps
M.defaults.changes               = {
  cmd       = "changes",
  h1        = "change",
  actions   = { ["enter"] = actions.goto_jump },
  previewer = { _ctor = previewers.builtin.jumps },
}

---@class fzf-lua.config.Jumps: fzf-lua.config.Base
---@field cmd string
---@field h1 string
M.defaults.jumps                 = {
  cmd       = "jumps",
  fzf_opts  = { ["--no-multi"] = true },
  actions   = { ["enter"] = actions.goto_jump },
  previewer = { _ctor = previewers.builtin.jumps },
}

---@class fzf-lua.config.Tagstack: fzf-lua.config.Base
M.defaults.tagstack              = {
  file_icons  = 1, ---@type integer|boolean
  color_icons = true,
  git_icons   = true,
  fzf_opts    = { ["--multi"] = true },
  previewer   = M._default_previewer_fn,
  _actions    = function() return M.globals.actions.files end,
}

---@class fzf-lua.config.Commands: fzf-lua.config.Base
---@field flatten table<string, boolean>
---@field include_builtin boolean
---@field sort_lastused boolean
M.defaults.commands              = {
  actions         = { ["enter"] = actions.ex_run },
  flatten         = {},
  include_builtin = true,
  _cached_hls     = { "cmd_ex", "cmd_buf", "cmd_global" },
}

---@class fzf-lua.config.Autocmds: fzf-lua.config.Base
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

---@class fzf-lua.config.Undotree: fzf-lua.config.Base
---@field __locate_pos? integer
M.defaults.undotree              = {
  previewer      = "undotree",
  locate         = true,
  fzf_opts       = { ["--no-multi"] = true },
  actions        = { ["enter"] = actions.undo },
  _cached_hls    = { "buf_linenr", "buf_name", "path_linenr", "dir_part" },
  _resume_reload = true,
  keymap         = { builtin = { ["<F8>"] = "toggle-preview-undo" } },
}

---@class fzf-lua.config.CommandHistory: fzf-lua.config.Base
M.defaults.command_history       = {
  fzf_opts    = { ["--tiebreak"] = "index", ["--no-multi"] = true },
  _treesitter = function(line) return "foo.vim", nil, line end,
  fzf_colors  = { ["hl"] = "-1:reverse", ["hl+"] = "-1:reverse" },
  actions     = {
    ["enter"]  = actions.ex_run_cr,
    ["ctrl-e"] = actions.ex_run,
  },
  _headers    = { "actions" },
}

---@class fzf-lua.config.SearchHistory : fzf-lua.config.CommandHistory
M.defaults.search_history        = {
  fzf_opts    = { ["--tiebreak"] = "index", ["--no-multi"] = true },
  _treesitter = function(line) return "", nil, line, "regex" end,
  fzf_colors  = { ["hl"] = "-1:reverse", ["hl+"] = "-1:reverse" },
  actions     = {
    ["enter"]  = actions.search_cr,
    ["ctrl-e"] = actions.search,
  },
  _headers    = { "actions" },
}

---@class fzf-lua.config.Registers: fzf-lua.config.Base
---@field filter string|function (ls: "ls")
M.defaults.registers             = {
  multiline    = true, ---@type integer|boolean
  ignore_empty = true,
  actions      = { ["enter"] = actions.paste_register },
  fzf_opts     = { ["--no-multi"] = true },
}

---@class fzf-lua.config.Keymaps: fzf-lua.config.Base
---@field ignore_patterns string[]
---@field show_desc boolean
---@field show_details boolean
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

---@class fzf-lua.config.NvimOptions: fzf-lua.config.Base
---@field separator string
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

---@class fzf-lua.config.Serverlist : fzf-lua.config.Base
---@field _screenshot string
M.defaults.serverlist            = {
  _screenshot = vim.fn.tempname(),
  previewer = { _ctor = previewers.fzf.nvim_server },
  _resume_reload = true, -- avoid list contain killed server unhide
  keymap = { fzf = { resize = "refresh-preview" } },
  actions = {
    ["enter"] = actions.serverlist_connect,
    ["ctrl-o"] = { fn = actions.serverlist_spawn, reload = true },
    ["ctrl-x"] = { fn = actions.serverlist_kill, reload = true },
  },
}


---@class fzf-lua.config.Filetypes : fzf-lua.config.Base
M.defaults.filetypes         = {
  file_icons = false, ---@type integer|boolean
  actions    = { ["enter"] = actions.set_filetype },
}

---@class fzf-lua.config.Packadd : fzf-lua.config.Base
M.defaults.packadd           = {
  actions = {
    ["enter"] = actions.packadd,
  },
}

---@class fzf-lua.config.Menus : fzf-lua.config.Base
M.defaults.menus             = {
  actions = {
    ["enter"] = actions.exec_menu,
  },
}

---@class fzf-lua.config.Tmux
---@field buffers fzf-lua.config.TmuxBuffers
---@field cmd string
M.defaults.tmux              = {
  ---@class fzf-lua.config.TmuxBuffers: fzf-lua.config.Base
  buffers = {
    cmd      = "tmux list-buffers",
    register = [["]],
    actions  = { ["enter"] = actions.tmux_buf_set_reg },
    fzf_opts = { ["--no-multi"] = true, ["--delimiter"] = "[:]" }
  },
}

---@class fzf-lua.config.DapBase: fzf-lua.config.Base
---@field commands fzf-lua.config.DapCommands
---@field configurations fzf-lua.config.DapConfigurations
---@field variables fzf-lua.config.DapVariables
---@field frames fzf-lua.config.DapFrames
---@field breakpoints fzf-lua.config.DapBreakpoints

---@class fzf-lua.config.Dap
M.defaults.dap               = {
  ---@class fzf-lua.config.DapCommands: fzf-lua.config.DapBase
  commands       = { fzf_opts = { ["--no-multi"] = true }, },
  ---@class fzf-lua.config.DapConfigurations: fzf-lua.config.DapBase
  configurations = { fzf_opts = { ["--no-multi"] = true }, },
  ---@class fzf-lua.config.DapVariables: fzf-lua.config.DapBase
  variables      = { fzf_opts = { ["--no-multi"] = true }, },
  ---@class fzf-lua.config.DapFrames: fzf-lua.config.DapBase
  frames         = { fzf_opts = { ["--no-multi"] = true }, },
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

---@class fzf-lua.config.CompletePath: fzf-lua.config.Base
---@field cmd string default: auto detect fd|rg|find
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

---@class fzf-lua.config.CompleteFile: fzf-lua.config.Base
---@field cmd string default: auto detect fd|rg|find
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

---@class fzf-lua.config.Zoxide: fzf-lua.config.Base
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
  scrollfloat_f  = "FzfLuaScrollFloatFull", ---@type string|false
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
