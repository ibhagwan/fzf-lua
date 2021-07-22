if not pcall(require, "fzf") then
  return
end

local fzf = require "fzf"
local action = require("fzf.actions").action
local core = require "fzf-lua.core"
local config = require "fzf-lua.config"
local actions = require "fzf-lua.actions"

local M = {}

M.metatable = function(opts)

  opts = config.getopts(opts, config.builtin, {
    "prompt", "winopts", "actions",
  })

  if not opts.metatable then opts.metatable = getmetatable('').__index end

  coroutine.wrap(function ()

    local prev_act = action(function (args)
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

    opts.preview = prev_act
    opts.preview_window = 'hidden:down:10'
    opts.nomulti = true

    local selected = fzf.fzf(methods,
      core.build_fzf_cli(opts),
      config.winopts(opts.winopts))

    if not selected then return end

    actions.act(opts.actions, selected)

    -- _G.dump(methods)

  end)()

end

return M
