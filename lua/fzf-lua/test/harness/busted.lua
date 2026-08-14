--- Busted interface emulation (`describe`, `it`, `setup`, ...).
---
--- Collection calls `emulate()` before sourcing a spec file and `deemulate()`
--- afterwards so the globals exist only while specs run.

local util = require("fzf-lua.test.harness.util")

local M = {}

--- Install busted globals, recording subsequent definitions into `set`.
---@param set table test set to receive the definitions
M.emulate = function(set)
  local cur_set = set

  -- The linter flags `_G.describe`/`_G.it`/... as duplicated with the nil
  -- assignments in `M.deemulate`; both sets are intentional.
  ---@diagnostic disable: duplicate-set-field
  _G.describe = function(name, f)
    local cur_set_parent = cur_set
    cur_set_parent[name] = util.new_set()
    cur_set = cur_set_parent[name]
    f()
    cur_set = cur_set_parent
  end

  _G.it = function(name, f) cur_set[name] = f end

  local setting_hook = function(hook_name)
    return function(hook)
      local metatbl = getmetatable(cur_set)
      metatbl.opts.hooks = metatbl.opts.hooks or {}
      metatbl.opts.hooks[hook_name] = hook
    end
  end

  _G.setup = setting_hook("pre_once")
  _G.before_each = setting_hook("pre_case")
  _G.after_each = setting_hook("post_case")
  _G.teardown = setting_hook("post_once")
end

--- Remove the busted globals installed by `emulate()`.
M.deemulate = function()
  local fun_names = { "describe", "it", "setup", "before_each", "after_each", "teardown" }
  for _, f_name in ipairs(fun_names) do
    _G[f_name] = nil
  end
end

return M
