local helpers = dofile("tests/helpers.lua")

local child = helpers.new_child_neovim()
local expect, eq = helpers.expect, helpers.expect.equality
local new_set = MiniTest.new_set

-- Helpers with child processes
--stylua: ignore start
local load_module = function(config) child.load(config) end
local unload_module = function() child.unload("surround") end
local reload_module = function(config)
  unload_module(); load_module(config)
end
local set_cursor = function(...) return child.set_cursor(...) end
local get_cursor = function(...) return child.get_cursor(...) end
local set_lines = function(...) return child.set_lines(...) end
local get_lines = function(...) return child.get_lines(...) end
local type_keys = function(...) return child.type_keys(...) end
local sleep = function(ms) helpers.sleep(ms, child) end
--stylua: ignore end

local T = new_set({
  hooks = {
    pre_case = function()
      child.setup()
      load_module()

      -- Make all showed messages full width
      child.o.cmdheight = 10
    end,
    post_once = child.stop,
  },
  -- n_retry = helpers.get_n_retry(2),
})

T["setup()"] = new_set()

T["setup()"]["creates side effects"] = function()
  -- Test require
  eq(child.lua_get([[type(require "fzf-lua")]]), "table")

  -- Highlight groups
  child.cmd("hi clear")
  load_module()
  expect.match(child.cmd_capture("hi FzfLuaNormal"), "links to Normal")
end

return T
