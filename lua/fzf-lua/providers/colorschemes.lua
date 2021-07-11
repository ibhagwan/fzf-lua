if not pcall(require, "fzf") then
  return
end

local fzf = require "fzf"
local action = require("fzf.actions").action
local core = require "fzf-lua.core"
local utils = require "fzf-lua.utils"
local config = require "fzf-lua.config"
local actions = require "fzf-lua.actions"

local function get_current_colorscheme()
  if vim.g.colors_name then
    return vim.g.colors_name
  else
    return 'default'
  end
end

local M = {}

M.colorschemes = function(opts)

  opts = config.getopts(opts, config.colorschemes, {
    "prompt", "actions", "winopts", "live_preview", "post_reset_cb",
  })

  coroutine.wrap(function ()
    local prev_act = action(function (args)
      if opts.live_preview and args then
        local colorscheme = args[1]
        vim.cmd("colorscheme " .. colorscheme)
      end
    end)

    local current_colorscheme = get_current_colorscheme()
    local current_background = vim.o.background
    local colors = vim.list_extend(opts.colors or {}, vim.fn.getcompletion('', 'color'))
    local selected = fzf.fzf(colors,
      core.build_fzf_cli({
        prompt = opts.prompt,
        preview = prev_act, preview_window = 'right:0',
        actions = opts.actions,
        nomulti = true,
      }),
      config.winopts(opts.winopts))

    if not selected then
      vim.o.background = current_background
      vim.cmd("colorscheme " .. current_colorscheme)
      vim.o.background = current_background
    else
      actions.act(opts.actions, selected[1], selected)
    end

    if opts.post_reset_cb then
      opts.post_reset_cb()
    end

  end)()

end

return M
