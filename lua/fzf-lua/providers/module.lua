local core = require "fzf-lua.core"
local shell = require "fzf-lua.shell"
local config = require "fzf-lua.config"
local actions = require "fzf-lua.actions"

local M = {}

M.metatable = function(opts)

  opts = config.normalize_opts(opts, config.globals.builtin)
  if not opts then return end

  if not opts.metatable then opts.metatable = getmetatable('').__index end

  local prev_act = shell.action(function (args)
    -- TODO: retreive method help
    local help = ''
    return string.format("%s:%s", args[1], help)
  end)

  local methods = {}
  for k, _ in pairs(opts.metatable) do
    if not opts.metatable_exclude or opts.metatable_exclude[k] == nil then
      table.insert(methods, k)
    end
  end

  table.sort(methods, function(a, b) return a<b end)

  opts.fzf_opts['--preview'] = prev_act
  opts.fzf_opts['--preview-window'] = 'hidden:down:10'
  opts.fzf_opts['--no-multi'] = ''

  if opts.no_global_resume == nil then
    -- builtin is excluded by from global resume
    -- as the behavior might confuse users (#267)
    opts.no_global_resume = true
  end

  core.fzf_wrap(opts, methods, function(selected)

    if not selected then return end

    actions.act(opts.actions, selected)

  end)()

end

return M
