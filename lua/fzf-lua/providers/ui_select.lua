local core = require "fzf-lua.core"
local utils = require "fzf-lua.utils"
local config = require "fzf-lua.config"
local actions = require "fzf-lua.actions"

local M = {}

local _opts = nil
local _old_ui_select = nil

M.deregister = function()
  if not _old_ui_select then
    utils.info("vim.ui.select in not registered to fzf-lua")
  end
  vim.ui.select = _old_ui_select
  _old_ui_select = nil
  _opts = nil
end

M.register = function(opts)
  if vim.ui.select == M.ui_select then
    -- already registered
    utils.info("vim.ui.select already registered to fzf-lua")
    return
  end
  _opts = opts
  _old_ui_select = vim.ui.select
  vim.ui.select = M.ui_select
end

M.ui_select = function(items, opts, on_choice)
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

  -- exit visual mode if needed
  local mode = vim.api.nvim_get_mode()
  if not mode.mode:match("^n") then
    utils.feed_keys_termcodes("<Esc>")
  end

  local entries = {}
  for i, e in ipairs(items) do
    table.insert(entries,
      ("%s. %s"):format(utils.ansi_codes.magenta(tostring(i)),
        opts.format_item(e)))
  end

  local prompt = opts.prompt
  if not prompt then
      prompt =  "Select one of:"
  end

  _opts = _opts or {}
  _opts.fzf_opts = {
    ['--no-multi']        = '',
    ['--prompt']          = prompt:gsub(":$", "> "),
    ['--preview-window']  = 'hidden:right:0',
  }

  _opts.actions = vim.tbl_deep_extend("keep", _opts.actions or {},
    {
      ["default"] = function(selected, _)
        local idx = selected and tonumber(selected[1]:match("^(%d+).")) or nil
        on_choice(idx and items[idx] or nil, idx)
      end
    })

  config.set_action_helpstr(_opts.actions['default'], "accept-item")

  core.fzf_wrap(_opts, entries, function(selected)

    config.set_action_helpstr(_opts.actions['default'], nil)

    if not selected then
      on_choice(nil, nil)
      return
    end

    actions.act(_opts.actions, selected)

  end)()

end

return M
