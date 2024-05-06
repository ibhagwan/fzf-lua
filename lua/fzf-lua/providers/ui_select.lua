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
  local idx = selected and tonumber(selected[1]:match("^(%d+)%.")) or nil
  o._on_choice(idx and o._items[idx] or nil, idx)
  o._on_choice_called = true
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
  for i, e in ipairs(items) do
    table.insert(entries,
      ("%s. %s"):format(utils.ansi_codes.magenta(tostring(i)),
        ui_opts.format_item and ui_opts.format_item(e) or tostring(e)))
  end

  local opts = _OPTS or {}

  -- enables customization per kind (#755)
  if type(opts) == "function" then
    opts = opts(ui_opts, items)
  end

  opts.fzf_opts = vim.tbl_extend("keep", opts.fzf_opts or {}, {
    ["--no-multi"]       = true,
    ["--preview-window"] = "hidden:right:0",
  })

  -- Force override prompt or it stays cached (#786)
  local prompt = ui_opts.prompt or "Select one of:"
  opts.fzf_opts["--prompt"] = prompt:gsub(":%s?$", "> ")

  -- save items so we can access them from the action
  opts._items = items
  opts._on_choice = on_choice
  opts._ui_select = ui_opts

  opts.actions = vim.tbl_deep_extend("keep",
    opts.actions or {}, { ["default"] = M.accept_item })

  config.set_action_helpstr(M.accept_item, "accept-item")

  opts.fn_selected = function(selected, o)
    config.set_action_helpstr(opts.actions["default"], nil)

    if not selected then
      -- with `actions.dummy_abort` this doesn't get called anymore
      -- as the action is configured as a valid fzf "accept" (thus
      -- `selected` isn't empty), see below comment for more info
      on_choice(nil, nil)
    else
      o._on_choice_called = nil
      actions.act(o.actions, selected, o)
      if not o._on_choice_called then
        -- see  comment above, `on_choice` wasn't called, either
        -- "dummy_abort" (ctrl-c/esc) or (unlikely) the user setup
        -- additional binds that aren't for "accept". Not calling
        -- with nil (no action) can cause issues, for example with
        -- dressing.nvim (#1014)
        on_choice(nil, nil)
      end
    end

    if opts.post_action_cb then
      opts.post_action_cb()
    end
  end


  -- ui.select is code actions
  -- inherit from defaults if not triggered by lsp_code_actions
  local opts_merge_strategy = "keep"
  if not _OPTS_ONCE and ui_opts.kind == "codeaction" then
    _OPTS_ONCE = config.normalize_opts({}, "lsp.code_actions")
    -- auto-detected code actions, prioritize the ui_select
    -- options over `lsp.code_actions` (#999)
    opts_merge_strategy = "force"
  end
  if _OPTS_ONCE then
    -- merge and clear the once opts sent from lsp_code_actions.
    -- We also override actions to guarantee a single default
    -- action, otherwise selected[1] will be empty due to
    -- multiple keybinds trigger, sending `--expect` to fzf
    local previewer = _OPTS_ONCE.previewer
    _OPTS_ONCE.previewer = nil -- can't copy the previewer object
    opts = vim.tbl_deep_extend(opts_merge_strategy, _OPTS_ONCE, opts)
    opts.actions = { ["default"] = opts.actions["default"] }
    opts.previewer = previewer
    _OPTS_ONCE = nil
  end

  core.fzf_exec(entries, opts)
end

return M
