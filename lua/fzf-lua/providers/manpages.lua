if not pcall(require, "fzf") then
  return
end

local fzf_helpers = require("fzf.helpers")
local core = require "fzf-lua.core"
local utils = require "fzf-lua.utils"
local config = require "fzf-lua.config"
local actions = require "fzf-lua.actions"


local M = {}

M.getmanpage = function(line)
  --[[ -- extract section from the last pair of parentheses
  local name, section = line:match("^(.*)%((.-)%)[^()]-$")
  if name:sub(-1) == " " then
    -- man-db
    name = name:sub(1, -2)
  else
    -- mandoc
    name = name:match("^[^, ]+")
    section = section:match("^[^, ]+")
  end
  return name .. "(" .. section .. ")" ]]
  return line:match("[^[,( ]+")
end

M.manpages = function(opts)

  opts = config.normalize_opts(opts, config.globals.manpages)
  if not opts then return end

  coroutine.wrap(function ()

    -- local prev_act = action(function (args) end)

    local fzf_fn = fzf_helpers.cmd_line_transformer(opts.cmd, function(x)
      -- split by first occurence of ' - ' (spaced hyphen)
      local man, desc = x:match("^(.-) %- (.*)$")
      return string.format("%-45s %s",
        utils.ansi_codes.magenta(man), desc)
    end)

    opts.fzf_opts['--no-multi'] = ''
    opts.fzf_opts['--preview-window'] = 'hidden:right:0'
    opts.fzf_opts['--tiebreak'] = 'begin'
    opts.fzf_opts['--nth'] = '1,2'

    local selected = core.fzf(opts, fzf_fn)

    if not selected then return end

    if #selected > 1 then
      for i = 2, #selected do
        selected[i] = M.getmanpage(selected[i])
      end
    end

    actions.act(opts.actions, selected)

  end)()

end

return M
