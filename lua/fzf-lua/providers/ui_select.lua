local core = require "fzf-lua.core"
local utils = require "fzf-lua.utils"
local config = require "fzf-lua.config"
local actions = require "fzf-lua.actions"

local M = {}

local _OPTS = nil
local _OPTS_ONCE = nil
local _OLD_UI_SELECT = nil

M.is_registered = function()
  return vim.ui.select == M.ui_select
end

M.deregister = function(_, silent, noclear)
  if not _OLD_UI_SELECT then
    if not silent then
      utils.info("vim.ui.select in not registered to fzf-lua")
    end
    return false
  end
  vim.ui.select = _OLD_UI_SELECT
  _OLD_UI_SELECT = nil
  -- do not empty _opts in case when
  -- resume from `lsp_code_actions`
  if not noclear then
    _OPTS = nil
  end
  return true
end

M.register = function(opts, silent, opts_once)
  -- save "once" opts sent from lsp_code_actions
  _OPTS_ONCE = opts_once
  if vim.ui.select == M.ui_select then
    -- already registered
    if not silent then
      utils.info("vim.ui.select already registered to fzf-lua")
    end
    return false
  end
  _OPTS = opts
  _OLD_UI_SELECT = vim.ui.select
  vim.ui.select = M.ui_select
  return true
end

M.accept_item = function(selected, o)
  if #selected == 0 then return end
  local idx = selected and tonumber(selected[1]:match("^%s*(%d+)%.")) or nil
  o._on_choice(idx and o._items[idx] or nil, idx)
  o._on_choice_called = true
end

local resolve_preview_type = function(ui_opts, opts)
  local preview_type = ui_opts.preview_type or opts.preview_type
  if preview_type == nil then
    local profile = opts.profile or opts[1]
    local is_tmux_profile = profile == "fzf-tmux"
        or (type(profile) == "table" and vim.tbl_contains(profile, "fzf-tmux"))
    preview_type = (is_tmux_profile
          or (opts.fzf_opts and opts.fzf_opts["--tmux"]))
        and "native" or "buffer"
  end
  return preview_type
end

M.ui_select = function(items, ui_opts, on_choice)
  --[[
  -- Code Actions
  opts = {
    format_item = <function 1>,
    kind = "codeaction",
    prompt = "Code actions:"
  }
  items[1] = { 1, {
    command = {
      arguments = { {
          action = "add",
          key = "Lua.diagnostics.globals",
          uri = "file:///home/bhagwan/.dots/.config/awesome/rc.lua",
          value = "mymainmenu"
        } },
      command = "lua.setConfig",
      title = "Mark defined global"
    },
    kind = "quickfix",
    title = "Mark `mymainmenu` as defined global."
  } } ]]
  local entries = {}
  local num_width = math.ceil(math.log10(#items))
  local num_format_str = "%" .. num_width .. "d"
  local reverse_lookup = {}
  for i, e in ipairs(items) do
    local entry = ("%s. %s"):format(utils.ansi_codes.magenta(num_format_str:format(i)),
      ui_opts.format_item and ui_opts.format_item(e) or tostring(e))
    entries[#entries + 1] = entry
    -- fzf will to strip all ansi (even in item str), so we store stripped key
    reverse_lookup[utils.strip_ansi_coloring(entry)] = i
  end

  local opts = _OPTS or {}

  -- enables customization per kind (#755): the registered opts can be a
  -- function that returns an opts table based on the `ui_opts` (kind,
  -- prompt, etc.) and the `items` being selected. `config.normalize_opts`
  -- calls function opts with no args, so resolve the function here first
  -- to preserve the historical `opts(ui_opts, items)` signature (#2770).
  if vim.is_callable(opts) then
    ---@diagnostic disable-next-line: call-non-callable
    opts = opts(ui_opts, items)
  end

  opts = config.normalize_opts(opts, "ui_select")
  if not opts then return end

  -- deepcopy register opts so we don't poullute the original tbl ref (#2241)
  if type(opts) == "table" then
    opts = utils.tbl_deep_clone(opts)
  end

  -- Force override prompt or it stays cached (#786)
  local prompt = ui_opts.prompt or "Select one of:"
  opts.prompt = opts.prompt or prompt:gsub(":%s?$", "> ")

  -- save items so we can access them from the action
  opts._items = items
  opts._on_choice = on_choice
  opts._ui_select = ui_opts

  -- schedule to avoid our coroutine break external async logic #2719
  opts.fn_selected = vim.schedule_wrap(function(selected, o)
    local function exec_choice()
      if not selected then
        -- with `actions.dummy_abort` this doesn't get called anymore
        -- as the action is configured as a valid fzf "accept" (thus
        -- `selected` isn't empty), see below comment for more info
        on_choice(nil, nil)
      else
        o._on_choice_called = nil
        actions.act(selected, o)
        if not o._on_choice_called then
          -- see  comment above, `on_choice` wasn't called, either
          -- "dummy_abort" (ctrl-c/esc) or (unlikely) the user setup
          -- additional binds that aren't for "accept". Not calling
          -- with nil (no action) can cause issues, for example with
          -- dressing.nvim (#1014)
          on_choice(nil, nil)
        end
      end

      ---@diagnostic disable-next-line: undefined-field
      if opts.post_action_cb then
        ---@diagnostic disable-next-line: undefined-field
        opts.post_action_cb()
      end
    end

    if o.__CTX.mode == "i" then
      -- If called from INSERT mode we have to schedule the callback
      -- till **after** the mode is changed (#1572)
      vim.cmd [[noautocmd lua vim.api.nvim_feedkeys('i', 'n', true)]]
      vim.api.nvim_create_autocmd("ModeChanged", {
        pattern = "*:i*", once = true, callback = exec_choice
      })
    else
      exec_choice()
    end
  end)


  -- ui.select is code actions
  -- inherit from defaults if not triggered by lsp_code_actions
  ---@type 'error'|'keep'|'force'
  local opts_merge_strategy = "keep"

  -- fix error when vim.lsp.buf.code_action() called but didn't triggers vim.ui.select
  -- _OPTS_ONCE also means pending deregister
  -- since we only use it to custom codeaction preview now
  if _OPTS_ONCE and ui_opts.kind ~= "codeaction" then
    M.deregister({}, true, true)
    _OPTS_ONCE = nil
    return vim.ui.select(items, ui_opts, on_choice)
  end

  if not _OPTS_ONCE and ui_opts.kind == "codeaction" then
    ---@type fzf-lua.config.LspCodeActions
    _OPTS_ONCE = config.normalize_opts({}, "lsp.code_actions")
    if not _OPTS_ONCE then return end
    -- auto-detected code actions, prioritize the ui_select
    -- options over `lsp.code_actions` (#999)
    opts_merge_strategy = "force"
  end

  if ui_opts.preview_item then
    local preview_type = resolve_preview_type(ui_opts, opts)
    if preview_type == "native" then
      local tmpfile = vim.fn.tempname()
      opts.preview = {
        fn = function(s)
          if not s or not s[1] then return utils.shell_nop() end
          local idx = reverse_lookup[utils.strip_ansi_coloring(s[1])]
          if not idx or not items[idx] then return utils.shell_nop() end
          local res = ui_opts.preview_item(items[idx])
          if type(res) ~= "table" or not res.buf or not vim.api.nvim_buf_is_valid(res.buf) then
            return utils.shell_nop()
          end
          local fd, _ = io.open(tmpfile, "w")
          if fd then
            fd:write(table.concat(vim.api.nvim_buf_get_lines(res.buf, 0, -1, false), "\n"))
            fd:close()
          end
          local ft = vim.bo[res.buf].filetype or vim.filetype.match({ buf = res.buf })
          local cat = utils.__IS_WINDOWS and "type" or "cat"
          local nul = utils.__IS_WINDOWS and "NUL" or "/dev/null"
          local tmp_esc = require("fzf-lua.libuv").shellescape(tmpfile)
          if ft and ft ~= "" then
            return ("bat --style=numbers,changes --color=always --language=%s %s 2>%s || %s %s")
                :format(ft, tmp_esc, nul, cat, tmp_esc)
          end
          return ("bat --style=numbers,changes --color=always %s 2>%s || %s %s"):format(
            tmp_esc, nul, cat, tmp_esc)
        end,
        type = "cmd",
      }

      -- `preview_offset` is a static fzf flag, so we seed it once from
      -- the first item's `pos`. The user can scroll within fzf for
      -- per-entry offsets; the common case is one shared buffer.
      if items[1] then
        local first = ui_opts.preview_item(items[1])
        if first and first.pos and first.pos[1] then
          opts.preview_offset = ("+%d"):format(first.pos[1])
        end
      end

      opts.winopts = opts.winopts or {}
      local prev_on_close = opts.winopts.on_close
      opts.winopts.on_close = function(...)
        if prev_on_close then prev_on_close(...) end
        pcall(os.remove, tmpfile)
      end
    else
      opts.previewer = {
        _ctor = function()
          local previewer = require("fzf-lua.previewer.builtin").buffer_or_file:extend()
          ---@diagnostic disable-next-line: unused
          function previewer:parse_entry(entry_str, cb)
            local str = utils.strip_ansi_coloring(entry_str)
            local res = ui_opts.preview_item(items[reverse_lookup[str]], cb)
            if type(res) ~= "table" or (not res.buf and not res.pos) then
              return { content = { { { "No preview available", "Error" } } }, }
            end
            local pos_start, pos_end = res.pos, res.pos_end
            return {
              _scratch_buf = res.buf,
              line = pos_start and pos_start[1] or 1,
              col = pos_start and pos_start[2] or 1,
              end_line = pos_end and pos_end[1] or 1,
              end_col = pos_end and pos_end[2] or 1,
            }
          end

          return previewer
        end,
      }
    end
  elseif _OPTS_ONCE then
    -- merge and clear the once opts sent from lsp_code_actions.
    -- We also override actions to guarantee a single default
    -- action, otherwise selected[1] will be empty due to
    -- multiple keybinds trigger, sending `--expect` to fzf
    local previewer = _OPTS_ONCE.previewer
    _OPTS_ONCE.previewer = nil -- can't copy the previewer object
    ---@diagnostic disable-next-line: param-type-mismatch
    ---@diagnostic disable-next-line: assign-type-mismatch
    ---@diagnostic disable-next-line: generic-constraint-mismatch
    opts = vim.tbl_deep_extend(opts_merge_strategy, _OPTS_ONCE, opts)
    ---@cast opts table
    opts.actions = vim.tbl_deep_extend("force", opts.actions or {},
      { ["enter"] = opts.actions.enter })
    opts.previewer = previewer
    -- Callback to set the coroutine so we know if the interface
    -- was opened or not (e.g. when no code actions are present)
    opts.cb_co = (function()
      -- NOTE: use clojure  as `_OPTS_ONCE` is otherwise nullified
      local opts_once_ref = _OPTS_ONCE
      ---@diagnostic disable-next-line: inject-field
      return function(co) opts_once_ref._co = co end
    end)()
    _OPTS_ONCE = nil
  end

  -- disable hide profile unless specifically requested
  -- casues issues with abort as on_choice(nil) won't be called (#2439)
  opts.no_hide = opts.no_hide == nil and true or opts.no_hide

  core.fzf_exec(entries, opts)
end

return M
