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
  return child.lua_get(
    [[(function()
    local entries = {}
    for i = 1, vim.fn.histnr(":") do
      local entry = vim.fn.histget(":", i)
      if entry ~= "" then entries[#entries + 1] = entry end
    end
    return entries
  end)()]]
  )
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

T["registers"] = new_set()

T["registers"]["ctrl-x clears and reloads by default"] = function()
  eq(
    child.lua_get(
      [[(function()
    local action = require("fzf-lua.defaults").defaults.registers.actions["ctrl-x"]
    return action.fn == require("fzf-lua.actions").reg_clear and action.reload == true
  end)()]]
    ), true
  )
end

T["registers"]["clear action empties the selected register"] = function()
  exec_lua(function()
    vim.fn.setreg("a", "alpha")
    require("fzf-lua.actions").reg_clear({ "[A] [c] alpha" })
  end)
  eq(child.lua_get([[vim.fn.getreg("a")]]), "")
end

T["registers"]["clear action ignores empty or malformed selections"] = function()
  eq(
    child.lua_get(
      [[pcall(function()
    local actions = require("fzf-lua.actions")
    actions.reg_clear({})
    actions.reg_clear({ "not a register row" })
    return true
  end)]]
    ), true
  )
end

T["registers"]["clear action skips read-only registers"] = function()
  local results = exec_lua(function()
    local actions = require("fzf-lua.actions")
    local utils = require("fzf-lua.utils")
    local original_info, original_setreg = utils.info, vim.fn.setreg
    local res = {}
    for _, reg in ipairs({ "%", ":", "." }) do
      local messages, writes = {}, 0
      utils.info = function(msg, ...)
        table.insert(messages, string.format(msg, ...))
      end
      vim.fn.setreg = function()
        writes = writes + 1
      end
      actions.reg_clear({ "[" .. reg .. "] [c] value" })
      res[reg] = { messages = messages, writes = writes }
    end
    utils.info, vim.fn.setreg = original_info, original_setreg
    return res
  end)

  for _, reg in ipairs({ "%", ":", "." }) do
    eq(results[reg].messages, { "Register `" .. reg .. "` is read-only.\n" })
    eq(results[reg].writes, 0)
  end
end

T["registers"]["clear action resolves the unnamed register"] = function()
  local points_to = exec_lua(function()
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "alpha" })
    vim.cmd([[normal! "ayy]])
    local reg_info = vim.fn.getreginfo('"')
    return reg_info.points_to
  end)
  eq(points_to, "a")

  exec_lua(function()
    require("fzf-lua.actions").reg_clear({ '["] [c] alpha' })
  end)
  eq(child.lua_get([[vim.fn.getreg("a")]]), "")
  eq(child.lua_get([[vim.fn.getreg('"')]]), "")
end

T["registers"]["provider regenerates entries after a register changes"] = function()
  exec_lua(function()
    local core = require("fzf-lua.core")
    core.fzf_exec = function(contents)
      _G._reg_contents = contents
    end
    vim.fn.setreg("z", "first")
    require("fzf-lua.providers.nvim").registers({})
  end)

  local collect = function()
    return child.lua_get(
      [[(function()
      local entries = {}
      _G._reg_contents(function(item)
        if item then
          table.insert(entries, (require("fzf-lua.utils").strip_ansi_coloring(item)))
        end
      end)
      return entries
    end)()]]
    )
  end

  eq(vim.tbl_contains(collect(), "[Z] [c] first"), true)

  exec_lua(function()
    vim.fn.setreg("z", "second")
  end)
  eq(vim.tbl_contains(collect(), "[Z] [c] second"), true)
end

return T
