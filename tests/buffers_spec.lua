---@diagnostic disable: unused-local, unused-function, unused
local MiniTest = require("mini.test")
local helpers = require("fzf-lua.test.helpers")
local child = helpers.new_child_neovim()
local eq = helpers.expect.equality
local new_set = MiniTest.new_set
local exec_lua = child.lua

local T = helpers.new_set_with_child(child)

T["buffers"] = new_set({ n_retry = not helpers.IS_LINUX() and 5 or nil })

-- Regression for #2736: `actions.buf_del` uses `reload=true`, which runs the
-- contents callback asynchronously via a separate RPC process. If the picker
-- is closed (or its context is otherwise re-created without `buflist`) before
-- that reload is processed, the old code asserted on `ctx.buflist`.
T["buffers"]["reload after picker close"] = function()
  exec_lua([[
    for i = 1, 3 do
      vim.cmd.edit(vim.fn.tempname())
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { "buffer " .. i })
    end
    vim.cmd.edit(vim.fn.tempname())
  ]])

  child.FzfLua.buffers({ previewer = false })
  child.wait_until(function() return child.lua_get([[_G._fzf_lua_on_create]]) == true end)
  child.wait_until(function() return child.lua_get([[_G._fzf_load_called]]) == true end)
  local reload_cmd = exec_lua([[return FzfLua.config.__resume_data.contents]])
  eq(type(reload_cmd), "string")

  -- closing the picker clears the global context
  child.type_keys("<c-c>")
  child.wait_until(function() return child.lua_get([[_G._fzf_lua_on_create]]) == vim.NIL end)
  child.wait_until(function() return exec_lua([[return FzfLua.utils.__CTX() == nil]]) end)

  -- deliver the pending reload, as if it was still in flight when the picker
  -- was closed
  local job = exec_lua([[
    local cmd = ...
    _G._fzf_lua_reload_exit = nil
    return vim.fn.jobstart(cmd, {
      env = { FZF_LUA_SERVER = vim.v.servername },
      on_exit = function(_, code) _G._fzf_lua_reload_exit = code end,
    })
  ]], { reload_cmd })
  eq(job > 0, true, { fail_reason = "jobstart failed: " .. tostring(job) })
  child.wait_until(function()
    return exec_lua([[return _G._fzf_lua_reload_exit ~= nil]]) == true
  end)
  eq(exec_lua([[return _G._fzf_lua_reload_exit]]), 0)

  local msgs = child.cmd_capture("messages")
  eq(msgs:match("assertion failed") == nil, true, msgs)
end

return T
