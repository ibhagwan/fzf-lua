---@diagnostic disable: unused-local, unused-function, unused
local MiniTest = require("mini.test")
local helpers = require("fzf-lua.test.helpers")
local child = helpers.new_child_neovim()
local eq = helpers.expect.equality
local new_set = MiniTest.new_set
local exec_lua = child.lua

local T = helpers.new_set_with_child(child)

-- `histadd` removes the older duplicate but leaves an empty slot behind,
-- `histnr` still counts it and the picker must not list it as an entry
local add_duplicate_history = function()
  exec_lua(function()
    for _, c in ipairs({ "FzfLua command_history", "FzfLua files", "FzfLua files" }) do
      vim.fn.histadd(":", c)
    end
  end)
end

local collect_history = function(opts)
  add_duplicate_history()
  exec_lua(function(history_opts)
    _G._hist_items, _G._hist_done = {}, false
    require("fzf-lua.core").fzf_exec = function(contents)
      local cb = function(item, done)
        if item == nil then
          _G._hist_done = true
        else
          table.insert(_G._hist_items, item)
        end
        if done then done() end
      end
      contents(cb, cb)
    end
    require("fzf-lua.providers.nvim").command_history(history_opts)
  end, { opts or {} })
  eq(child.lua_get([[vim.fn.histnr(":")]]), 3)
  child.wait_until(function() return child.lua_get([[_G._hist_done]]) == true end)
  return child.lua_get([[_G._hist_items]])
end

local history_entries = function()
  return child.lua_get([[(function()
    local entries = {}
    for i = 1, vim.fn.histnr(":") do
      local entry = vim.fn.histget(":", i)
      if entry ~= "" then entries[#entries + 1] = entry end
    end
    return entries
  end)()]])
end

local delete_history = function(selected, opts)
  add_duplicate_history()
  exec_lua(function(sel, hist_opts)
    require("fzf-lua.actions").ex_del(sel, hist_opts)
  end, { selected, opts or {} })
  return history_entries()
end

T["command_history"] = new_set()

T["command_history"]["skips empty slots left by removed duplicates"] = function()
  eq(collect_history(), { "FzfLua files", "FzfLua command_history" })
end

T["command_history"]["skips empty slots in reverse order"] = function()
  eq(collect_history({ reverse_list = true }), { "FzfLua command_history", "FzfLua files" })
end

T["command_history"]["delete maps picker index to the right history entry"] = function()
  -- default order: { "FzfLua files" (0), "FzfLua command_history" (1) }
  eq(delete_history({ "1" }, { reverse_list = false }), { "FzfLua files" })
end

T["command_history"]["delete maps reverse picker index to the right history entry"] = function()
  -- reverse order: { "FzfLua command_history" (0), "FzfLua files" (1) }
  eq(delete_history({ "1" }, { reverse_list = true }), { "FzfLua command_history" })
end

T["command_history"]["delete maps first reverse picker index to the right history entry"] = function()
  -- reverse order: selecting index 0 must delete the oldest entry
  eq(delete_history({ "0" }, { reverse_list = true }), { "FzfLua files" })
end

T["command_history"]["delete resolves multiple reverse picker indices before deleting"] = function()
  -- all indices are resolved against the original list, before any deletion
  eq(delete_history({ "0", "1" }, { reverse_list = true }), {})
end

return T
