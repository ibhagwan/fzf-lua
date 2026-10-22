---@diagnostic disable: unused-local, unused-function, unused
local MiniTest = require("mini.test")
local helpers = require("fzf-lua.test.helpers")
local child = helpers.new_child_neovim()
local eq = helpers.expect.equality
local new_set = MiniTest.new_set
local exec_lua = child.lua

local T = helpers.new_set_with_child(child)

T["command_history"] = new_set()

T["command_history"]["skips empty slots left by removed duplicates"] = function()
  -- `histadd` removes the older duplicate but leaves an empty slot behind,
  -- `histnr` still counts it and the picker must not list it as an entry
  exec_lua([[
    for _, c in ipairs({ "FzfLua command_history", "FzfLua files", "FzfLua files" }) do
      vim.fn.histadd(":", c)
    end
    _G._hist_items, _G._hist_done = {}, false
    require("fzf-lua.core").fzf_exec = function(contents)
      contents(function(item, done)
        if item == nil then
          _G._hist_done = true
        else
          table.insert(_G._hist_items, item)
        end
        if done then done() end
      end)
    end
    require("fzf-lua.providers.nvim").command_history({})
  ]])
  child.wait_until(function() return child.lua_get([[_G._hist_done]]) == true end)
  eq(child.lua_get([[vim.fn.histnr(":")]]), 3)
  eq(child.lua_get([[_G._hist_items]]), { "FzfLua files", "FzfLua command_history" })
end

return T
