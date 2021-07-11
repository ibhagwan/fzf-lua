if not pcall(require, "fzf") then
  return
end

local fzf = require "fzf"
local fzf_helpers = require("fzf.helpers")
local core = require "fzf-lua.core"
local utils = require "fzf-lua.utils"
local config = require "fzf-lua.config"
local actions = require "fzf-lua.actions"


local M = {}

local function getmanpage(line)
  -- match until comma or space
  return string.match(line, "[^, ]+")
end

M.manpages = function(opts)

  opts = config.getopts(opts, config.manpages, {
    "prompt", "actions", "winopts", "cmd",
  })

  coroutine.wrap(function ()

    -- local prev_act = action(function (args) end)

    local fzf_fn = fzf_helpers.cmd_line_transformer(opts.cmd, function(x)
      -- split by first occurence of ' - ' (spaced hyphen)
      local man, desc = x:match("^(.-) %- (.*)$")
      return string.format("%-45s %s",
        utils.ansi_codes.red(man), desc)
    end)

    local selected = fzf.fzf(fzf_fn,
      core.build_fzf_cli({
        prompt = opts.prompt,
        -- preview = prev_act,
        preview_window = 'right:0',
        actions = opts.actions,
        cli_args = "--tiebreak begin --nth 1,2",
        nomulti = true,
      }),
      config.winopts(opts.winopts))

    if not selected then return end

    if #selected > 1 then
      for i = 2, #selected do
        selected[i] = getmanpage(selected[i])
        print(selected[i])
      end
    end

    actions.act(opts.actions, selected[1], selected)

  end)()

end

return M
