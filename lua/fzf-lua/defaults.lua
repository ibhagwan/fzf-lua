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
  return vim.fn.executable("delta") == 1 and ("delta --width=$COLUMNS --%s"):format(vim.o.bg) or
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

M.defaults                      = {
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
        -- >0 to prevent scrolling issues (#500)
        scrolloff      = 1,
      },
    },
    -- on_create  = function(_)
    --   vim.cmd("set winhl=Normal:Normal,FloatBorder:Normal")
    --   utils.keymap_set("t", "<A-Esc>", actions.hide, { nowait = true, buffer = e.bufnr })
    -- end,
  },
  keymap        = {
    builtin = {
      ["<M-Esc>"]    = "hide",
      ["<F1>"]       = "toggle-help",
      ["<F2>"]       = "toggle-fullscreen",
      -- Only valid with the 'builtin' previewer
      ["<F3>"]       = "toggle-preview-wrap",
      ["<F4>"]       = "toggle-preview",
      ["<F5>"]       = "toggle-preview-ccw",
      ["<F6>"]       = "toggle-preview-cw",
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
  fzf_bin       = nil,
  fzf_opts      = {
    ["--ansi"]           = true,
    ["--info"]           = "inline-right",
    ["--height"]         = "100%",
    ["--layout"]         = "reverse",
    ["--border"]         = "none",
    ["--highlight-line"] = true,
  },
  fzf_tmux_opts = { ["-p"] = "80%,80%", ["--margin"] = "0,0" },
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
      cmd = M._man_cmd_fn(),
    },
    man_native = {
      _ctor = previewers.fzf.man_pages,
      cmd = M._man_cmd_fn(true),
    },
    help_tags = {
      _ctor = previewers.builtin.help_tags,
    },
    help_native = {
      _ctor = previewers.fzf.help_tags,
    },
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
    codeaction = {
      _ctor     = previewers.builtin.codeaction,
      diff_opts = { ctxlen = 3 },
    },
    codeaction_native = {
      _ctor     = previewers.fzf.codeaction,
      diff_opts = { ctxlen = 3 },
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

M.defaults.files                = {
  previewer              = M._default_previewer_fn,
  cmd                    = nil, -- default: auto detect find|fd
  multiprocess           = true,
  file_icons             = 1,
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
  winopts                = { preview = { winopts = { cursorline = false } } },
}

-- Must construct our opts table in stages
-- so we can reference 'M.globals.files'
M.defaults.git                  = {
  files = {
    previewer         = M._default_previewer_fn,
    cmd               = "git ls-files --exclude-standard",
    multiprocess      = true,
    file_icons        = 1,
    color_icons       = true,
    git_icons         = true,
    fzf_opts          = { ["--multi"] = true, ["--scheme"] = "path" },
    _fzf_nth_devicons = true,
    _actions          = function() return M.globals.actions.files end,
    winopts           = { preview = { winopts = { cursorline = false } } },
  },
  status = {
    -- override `color.status=always`, technically not required
    -- since we now also call `utils.strip_ansi_coloring` (#706)
    cmd               = "git -c color.status=false --no-optional-locks status --porcelain=v1 -u",
    previewer         = "git_diff",
    multiprocess      = true,
    file_icons        = 1,
    color_icons       = true,
    fzf_opts          = { ["--multi"] = true },
    _fzf_nth_devicons = true,
    _actions          = function() return M.globals.actions.files end,
    actions           = {
      ["right"]  = { fn = actions.git_unstage, reload = true },
      ["left"]   = { fn = actions.git_stage, reload = true },
      ["ctrl-x"] = { fn = actions.git_reset, reload = true },
      -- Uncomment to test stage|unstage and backward compat
      -- ["ctrl-s"] = { fn = actions.git_stage_unstage, reload = true },
      -- ["ctrl-s"] = { actions.git_stage_unstage, actions.resume },
    },
  },
  diff = {
    cmd               = "git --no-pager diff --name-only {ref}",
    ref               = "HEAD",
    preview           = "git diff {ref} {file}",
    preview_pager     = M._preview_pager_fn,
    multiprocess      = true,
    file_icons        = 1,
    color_icons       = true,
    fzf_opts          = { ["--multi"] = true },
    _fzf_nth_devicons = true,
    _actions          = function() return M.globals.actions.files end,
  },
  hunks = {
    previewer         = M._default_previewer_fn,
    cmd               = "git --no-pager diff --color=always {ref}",
    ref               = "HEAD",
    multiprocess      = true,
    file_icons        = 1,
    color_icons       = true,
    fzf_opts          = {
      ["--multi"] = true,
      ["--delimiter"] = ":",
      ["--nth"] = "3..",
    },
    _fzf_nth_devicons = true,
    _actions          = function() return M.globals.actions.files end,
  },
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
    _multiline    = false,
  },
  bcommits = {
    cmd           = [[git log --color --pretty=format:"%C(yellow)%h%Creset ]]
        .. [[%Cgreen(%><(12)%cr%><|(12))%Creset %s %C(blue)<%an>%Creset" {file}]],
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
    _multiline    = false,
  },
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
  branches = {
    cmd        = "git branch --all --color",
    preview    = "git log --graph --pretty=oneline --abbrev-commit --color {1}",
    remotes    = "local",
    actions    = {
      ["enter"]  = actions.git_switch,
      ["ctrl-x"] = { fn = actions.git_branch_del, reload = true },
      ["ctrl-a"] = { fn = actions.git_branch_add, field_index = "{q}", reload = true },
    },
    cmd_add    = { "git", "branch" },
    cmd_del    = { "git", "branch", "--delete" },
    fzf_opts   = { ["--no-multi"] = true },
    _multiline = false,
  },
  tags = {
    cmd        = [[git for-each-ref --color --sort="-taggerdate" --format ]]
        .. [["%(color:yellow)%(refname:short)%(color:reset) ]]
        .. [[%(color:green)(%(taggerdate:relative))%(color:reset)]]
        .. [[ %(subject) %(color:blue)%(taggername)%(color:reset)" refs/tags]],
    preview    = [[git log --graph --color --pretty=format:"%C(yellow)%h%Creset ]]
        .. [[%Cgreen(%><(12)%cr%><|(12))%Creset %s %C(blue)<%an>%Creset" {1}]],
    actions    = { ["enter"] = actions.git_checkout },
    fzf_opts   = { ["--no-multi"] = true },
    _multiline = false,
  },
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
  },
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

M.defaults.grep                 = {
  previewer      = M._default_previewer_fn,
  input_prompt   = "Grep For> ",
  cmd            = nil, -- default: auto detect rg|grep
  multiprocess   = true,
  file_icons     = 1,
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
}

M.defaults.grep_curbuf          = vim.tbl_deep_extend("force", M.defaults.grep, {
  rg_glob          = false, -- meaningless for single file rg
  exec_empty_query = true,  -- makes sense to display lines immediately
  fzf_opts         = {
    ["--delimiter"] = "[:]",
    ["--with-nth"]  = "2..",
    ["--nth"]       = "2..",
  },
})

M.defaults.args                 = {
  previewer         = M._default_previewer_fn,
  files_only        = true,
  file_icons        = 1,
  color_icons       = true,
  git_icons         = false,
  fzf_opts          = { ["--multi"] = true, ["--scheme"] = "path" },
  _fzf_nth_devicons = true,
  _actions          = function() return M.globals.actions.files end,
  actions           = { ["ctrl-x"] = { fn = actions.arg_del, reload = true } },
}

M.defaults.oldfiles             = {
  previewer         = M._default_previewer_fn,
  file_icons        = 1,
  color_icons       = true,
  git_icons         = false,
  stat_file         = true,
  fzf_opts          = { ["--tiebreak"] = "index", ["--multi"] = true },
  _fzf_nth_devicons = true,
  _actions          = function() return M.globals.actions.files end,
}

M.defaults.quickfix             = {
  previewer   = M._default_previewer_fn,
  separator   = "▏",
  file_icons  = 1,
  color_icons = true,
  git_icons   = false,
  only_valid  = false,
  fzf_opts    = { ["--multi"] = true },
  _actions    = function() return M.globals.actions.files end,
  _treesitter = true,
  _cached_hls = { "path_colnr", "path_linenr" },
}

M.defaults.quickfix_stack       = {
  marker    = ">",
  previewer = { _ctor = previewers.builtin.quickfix, },
  fzf_opts  = { ["--no-multi"] = true },
  actions   = { ["enter"] = actions.set_qflist, },
}

M.defaults.loclist              = {
  previewer   = M._default_previewer_fn,
  separator   = "▏",
  file_icons  = 1,
  color_icons = true,
  git_icons   = false,
  only_valid  = false,
  fzf_opts    = { ["--multi"] = true },
  _actions    = function() return M.globals.actions.files end,
  _treesitter = true,
  _cached_hls = { "path_colnr", "path_linenr" },
}

M.defaults.loclist_stack        = {
  marker    = ">",
  previewer = { _ctor = previewers.builtin.quickfix, },
  fzf_opts  = { ["--no-multi"] = true },
  actions   = { ["enter"] = actions.set_qflist, },
}

M.defaults.buffers              = {
  previewer             = M._default_previewer_fn,
  file_icons            = 1,
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
}

M.defaults.tabs                 = {
  previewer   = M._default_previewer_fn,
  tab_title   = "Tab",
  tab_marker  = "<<",
  locate      = true,
  file_icons  = 1,
  color_icons = true,
  _actions    = function()
    return M.globals.actions.buffers or M.globals.actions.files
  end,
  actions     = {
    ["enter"]  = actions.buf_switch,
    ["ctrl-x"] = { fn = actions.buf_del, reload = true },
  },
  fzf_opts    = {
    ["--multi"]     = true,
    ["--delimiter"] = "[\\):]",
    ["--with-nth"]  = "5..",
  },
  _cached_hls = { "buf_nr", "buf_flag_cur", "buf_flag_alt", "tab_title", "tab_marker", "path_linenr" },
}

M.defaults.lines                = {
  previewer        = M._default_previewer_fn,
  file_icons       = 1,
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
      local bufnr, lnum, text = s:match("%[(%d+)%].-(%d+) (.+)$")
      if not bufnr then return "" end
      return string.format("[%s]%s%s:%s:%s",
        bufnr, utils.nbsp,
        path.tail(vim.api.nvim_buf_get_name(tonumber(bufnr))),
        lnum, text)
    end
  },
  _actions         = function()
    return M.globals.actions.buffers or M.globals.actions.files
  end,
}

M.defaults.blines               = vim.tbl_deep_extend("force", M.defaults.lines, {
  show_bufname    = false,
  show_unloaded   = true,
  show_unlisted   = true,
  no_term_buffers = false,
  fzf_opts        = {
    ["--with-nth"] = "4..",
    ["--nth"]      = "2..",
  },
})

M.defaults.treesitter           = {
  previewer        = M._default_previewer_fn,
  file_icons       = false,
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

M.defaults.tags                 = {
  previewer    = { _ctor = previewers.builtin.tags },
  input_prompt = "[tags] Grep For> ",
  ctags_file   = nil, -- auto-detect
  rg_opts      = "--no-heading --color=always --smart-case",
  grep_opts    = "--color=auto --perl-regexp",
  multiprocess = true,
  file_icons   = 1,
  git_icons    = false,
  color_icons  = true,
  fzf_opts     = {
    ["--no-multi"]  = true,
    ["--delimiter"] = string.format("[:%s]", utils.nbsp),
    ["--tiebreak"]  = "begin",
  },
  _actions     = function() return M.globals.actions.files end,
  actions      = { ["ctrl-g"] = { actions.grep_lgrep } },
  formatter    = false,
}

M.defaults.btags                = {
  previewer     = { _ctor = previewers.builtin.tags },
  ctags_file    = nil, -- auto-detect
  rg_opts       = "--color=never --no-heading",
  grep_opts     = "--color=never --perl-regexp",
  multiprocess  = true,
  file_icons    = false,
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

M.defaults.colorschemes         = {
  live_preview = true,
  winopts      = { height = 0.55, width = 0.50, backdrop = false },
  fzf_opts     = { ["--no-multi"] = true },
  actions      = { ["enter"] = actions.colorscheme },
}

M.defaults.highlights           = {
  fzf_opts   = { ["--no-multi"] = true },
  fzf_colors = { ["hl"] = "-1:reverse", ["hl+"] = "-1:reverse" },
  previewer  = { _ctor = previewers.builtin.highlights, },
  actions    = { ["enter"] = actions.hi }
}

M.defaults.awesome_colorschemes = {
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
    return path.join({ vim.fn.stdpath("cache"), "fzf-lua" })
  end,
  actions      = {
    ["enter"]  = actions.colorscheme,
    ["ctrl-g"] = { fn = actions.toggle_bg, exec_silent = true },
    ["ctrl-r"] = { fn = actions.cs_update, reload = true },
    ["ctrl-x"] = { fn = actions.cs_delete, reload = true },
  }
}

M.defaults.helptags             = {
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

M.defaults.manpages             = {
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

M.defaults.lsp                  = {
  previewer        = M._default_previewer_fn,
  file_icons       = 1,
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
}

M.defaults.lsp.symbols          = {
  previewer        = M._default_previewer_fn,
  file_icons       = 1,
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
  async_or_timeout = true,
  exec_empty_query = true,
  -- new formatting options with symbol name at the start
  fzf_opts         = {
    ["--delimiter"] = string.format("[:%s]", utils.nbsp),
    ["--tiebreak"]  = "begin",
    ["--multi"]     = true,
  },
  line_field_index = "{-2}", -- line field index
  field_index_expr = "{}",   -- entry field index
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
  _actions         = function() return M.globals.actions.files end,
  actions          = { ["ctrl-g"] = { actions.sym_lsym } },
  _cached_hls      = { "live_sym", "path_colnr", "path_linenr" },
  _uri             = true,
}

M.defaults.lsp.finder           = {
  previewer   = M._default_previewer_fn,
  file_icons  = 1,
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
  },
  fzf_opts    = { ["--multi"] = true },
  _treesitter = true,
  _cached_hls = { "path_colnr", "path_linenr" },
  _uri        = true,
}

M.defaults.lsp.code_actions     = {
  async_or_timeout = 5000,
  previewer        = "codeaction",
  -- previewer        = "codeaction_native",
  fzf_opts         = { ["--no-multi"] = true },
  -- NOTE: we don't need an action as code actions are executed by the ui.select
  -- callback but we setup an empty table to indicate to `globals.__index` that
  -- we need to inherit from the global defaults (#1232)
  actions          = {},
}

M.defaults.diagnostics          = {
  previewer      = M._default_previewer_fn,
  file_icons     = false,
  color_icons    = true,
  color_headings = true,
  git_icons      = false,
  diag_icons     = true,
  diag_source    = true,
  diag_code      = true,
  multiline      = 2,
  fzf_opts       = {
    ["--multi"] = true,
    ["--wrap"]  = true,
  },
  _actions       = function() return M.globals.actions.files end,
  _cached_hls    = { "path_colnr", "path_linenr" },
  -- signs = {
  --   ["Error"] = { text = "e", texthl = "DiagnosticError" },
  --   ["Warn"]  = { text = "w", texthl = "DiagnosticWarn" },
  --   ["Info"]  = { text = "i", texthl = "DiagnosticInfo" },
  --   ["Hint"]  = { text = "h", texthl = "DiagnosticHint" },
  -- },
}

M.defaults.builtin              = {
  winopts  = {
    height = 0.65,
    width  = 0.50,
  },
  fzf_opts = { ["--no-multi"] = true },
  actions  = { ["enter"] = actions.run_builtin },
}

M.defaults.profiles             = {
  previewer = M._default_previewer_fn,
  fzf_opts  = {
    ["--delimiter"] = "[:]",
    ["--with-nth"]  = "-1..",
    ["--tiebreak"]  = "begin",
    ["--no-multi"]  = true,
  },
  actions   = { ["enter"] = actions.apply_profile },
}

M.defaults.marks                = {
  fzf_opts  = { ["--no-multi"] = true },
  actions   = {
    ["enter"] = actions.goto_mark,
    ["ctrl-x"] = { fn = actions.mark_del, reload = true }
  },
  previewer = { _ctor = previewers.builtin.marks },
}

M.defaults.changes              = {
  cmd = "changes",
  h1 = "change",
}

M.defaults.jumps                = {
  cmd       = "jumps",
  fzf_opts  = { ["--no-multi"] = true },
  actions   = { ["enter"] = actions.goto_jump },
  previewer = { _ctor = previewers.builtin.jumps },
}

M.defaults.tagstack             = {
  file_icons  = 1,
  color_icons = true,
  git_icons   = true,
  fzf_opts    = { ["--multi"] = true },
  previewer   = M._default_previewer_fn,
  _actions    = function() return M.globals.actions.files end,
}

M.defaults.commands             = {
  actions         = { ["enter"] = actions.ex_run },
  flatten         = {},
  include_builtin = true,
}

M.defaults.autocmds             = {
  show_desc = true,
  previewer = { _ctor = previewers.builtin.autocmds },
  _actions  = function() return M.globals.actions.files end,
  fzf_opts  = {
    ["--delimiter"] = "[│]",
    ["--with-nth"]  = "2..",
    ["--no-multi"]  = true,
  },
}

M.defaults.command_history      = {
  fzf_opts    = { ["--tiebreak"] = "index", ["--no-multi"] = true },
  _treesitter = function(line) return "foo.vim", nil, line end,
  fzf_colors  = { ["hl"] = "-1:reverse", ["hl+"] = "-1:reverse" },
  actions     = {
    ["enter"]  = actions.ex_run_cr,
    ["ctrl-e"] = actions.ex_run,
  },
}

M.defaults.search_history       = {
  fzf_opts = { ["--tiebreak"] = "index", ["--no-multi"] = true },
  actions  = {
    ["enter"]  = actions.search_cr,
    ["ctrl-e"] = actions.search,
  },
}

M.defaults.registers            = {
  multiline    = true,
  ignore_empty = true,
  actions      = { ["enter"] = actions.paste_register },
  fzf_opts     = { ["--no-multi"] = true },
}

M.defaults.keymaps              = {
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

M.defaults.nvim_options         = {
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

M.defaults.spell_suggest        = {
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

M.defaults.filetypes            = {
  file_icons = false,
  actions    = { ["enter"] = actions.set_filetype },
}

M.defaults.packadd              = {
  actions = {
    ["enter"] = actions.packadd,
  },
}

M.defaults.menus                = {
  actions = {
    ["enter"] = actions.exec_menu,
  },
}

M.defaults.tmux                 = {
  buffers = {
    cmd      = "tmux list-buffers",
    register = [["]],
    actions  = { ["enter"] = actions.tmux_buf_set_reg },
    fzf_opts = { ["--no-multi"] = true, ["--delimiter"] = "[:]" }
  },
}

M.defaults.dap                  = {
  commands       = { fzf_opts = { ["--no-multi"] = true }, },
  configurations = { fzf_opts = { ["--no-multi"] = true }, },
  variables      = { fzf_opts = { ["--no-multi"] = true }, },
  frames         = { fzf_opts = { ["--no-multi"] = true }, },
  breakpoints    = {
    file_icons  = 1,
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
  },
}

M.defaults.complete_path        = {
  cmd               = nil, -- default: auto detect fd|rg|find
  file_icons        = false,
  git_icons         = false,
  color_icons       = true,
  multiprocess      = true,
  word_pattern      = nil,
  fzf_opts          = { ["--no-multi"] = true },
  _fzf_nth_devicons = true,
  actions           = { ["enter"] = actions.complete },
}

M.defaults.complete_file        = {
  cmd               = nil, -- default: auto detect rg|fd|find
  multiprocess      = true,
  file_icons        = 1,
  color_icons       = true,
  git_icons         = false,
  word_pattern      = nil,
  _actions          = function() return M.globals.actions.files end,
  actions           = { ["enter"] = actions.complete },
  previewer         = M._default_previewer_fn,
  winopts           = { preview = { hidden = true } },
  fzf_opts          = { ["--no-multi"] = true },
  _fzf_nth_devicons = true,
}

M.defaults.zoxide               = {
  multiprocess = true,
  cmd          = "zoxide query --list --score",
  git_root     = false,
  formatter    = "path.dirname_first",
  fzf_opts     = {
    ["--no-multi"]  = true,
    ["--delimiter"] = "[\t]",
    ["--tabstop"]   = "4",
    ["--tiebreak"]  = "end,index",
    ["--nth"]       = "2..",
    ["--no-sort"]   = true, -- sort by score
  },
  actions      = { enter = actions.cd }
}

M.defaults.complete_line        = { complete = true }

M.defaults.file_icon_padding    = ""

-- No need to sset this, already defaults to `nvim_open_win`
-- M.help_open_win              = vim.api.nvim_open_win

M.defaults.dir_icon             = ""

M.defaults.__HLS                = {
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
