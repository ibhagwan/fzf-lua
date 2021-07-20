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

    opts.cli_args = opts.cli_args or "--tiebreak begin --nth 1,2"
    opts.preview_window = opts.preview_window or 'right:0'
    opts.nomulti = utils._if(opts.nomulti~=nil, opts.nomulti, true)

    local selected = fzf.fzf(fzf_fn,
      core.build_fzf_cli(opts),
      config.winopts(opts.winopts))

    if not selected then return end

    if #selected > 1 then
      for i = 2, #selected do
        selected[i] = getmanpage(selected[i])
      end
    end

    actions.act(opts.actions, selected[1], selected)

  end)()

end

return M
