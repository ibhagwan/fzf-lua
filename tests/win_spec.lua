---@diagnostic disable: unused-local, unused-function
local MiniTest = require("mini.test")
local helpers = require("fzf-lua.test.helpers")
local child = helpers.new_child_neovim()
local expect, eq = helpers.expect, helpers.expect.equality
local new_set = MiniTest.new_set

-- Helpers with child processes
--stylua: ignore start
---@format disable-next
local reload = function(config) child.unload(); child.setup(config) end
local set_cursor = function(...) return child.set_cursor(...) end
local get_cursor = function(...) return child.get_cursor(...) end
local set_lines = function(...) return child.set_lines(...) end
local get_lines = function(...) return child.get_lines(...) end
local type_keys = function(...) return child.type_keys(...) end
local sleep = function(ms) helpers.sleep(ms, child) end
--stylua: ignore end

local T = helpers.new_set_with_child(child)

T["win"] = new_set()

T["win"]["hide"] = new_set()

T["win"]["hide"]["ensure gc called after win hidden (#1782)"] = function()
  child.lua([[
    _G._gc_called = nil
    local utils = FzfLua.utils
    utils.setmetatable__gc = function(t, mt)
      local prox = newproxy(true)
      getmetatable(prox).__gc = function()
        _G._gc_called = true
        mt.__gc(t)
      end
      t[prox] = true
      return setmetatable(t, mt)
    end
  ]])
  child.wait_until(function()
    if helpers.IS_WIN() then
      local hidden_fzf_bufnr = child.lua_get(
        [[(FzfLua.utils.fzf_winobj() or {})._hidden_fzf_bufnr]])
      if hidden_fzf_bufnr ~= vim.NIL then
        local chan = child.lua_get(([=[vim.bo[%s].channel]=]):format(hidden_fzf_bufnr))
        child.api.nvim_chan_send(chan, vim.keycode("<c-c>"))
      end
    end
    child.lua([[FzfLua.files{ previewer = 'builtin' }]])
    child.wait_until(function()
      return child.lua_get([[_G._fzf_load_called]]) == true
    end)
    child.lua([[FzfLua.hide()]])
    child.wait_until(function()
      return child.lua_get([[_G._fzf_load_called]]) == vim.NIL
    end)
    child.lua([[collectgarbage('collect')]])
    return child.lua_get([[_G._gc_called]]) == true
  end)
end

T["win"]["hide"]["buffer deleted after win hidden (#1783)"] = function()
  eq(child.lua_get([[_G._fzf_lua_on_create]]), vim.NIL)
  child.lua([[FzfLua.files()]])
  child.wait_until(function()
    return child.lua_get([[_G._fzf_lua_on_create]]) == true
  end)
  child.lua([[FzfLua.hide()]])
  child.wait_until(function()
    return child.lua_get([[_G._fzf_lua_on_create]]) == vim.NIL
  end)
  child.lua([[
    vim.cmd("%bd!")
    FzfLua.files()
  ]])
  child.wait_until(function()
    return child.lua_get([[_G._fzf_lua_on_create]]) == true
  end)
end

T["win"]["hide"]["can resume after close CTX win (#1936)"] = function()
  eq(child.lua_get([[_G._fzf_lua_on_create]]), vim.NIL)
  child.cmd([[new]])
  child.lua([[FzfLua.files()]])
  child.wait_until(function()
    return child.lua_get([[_G._fzf_lua_on_create]]) == true
  end)
  child.lua([[FzfLua.hide()]])
  child.wait_until(function()
    return child.lua_get([[_G._fzf_lua_on_create]]) == vim.NIL
  end)
  child.cmd([[close]])
  child.lua([[FzfLua.unhide()]])
  child.wait_until(function()
    return child.lua_get([[_G._fzf_lua_on_create]]) == true
  end)
  child.type_keys("<c-j>")
  child.type_keys("<c-j>")

  -- `:quit` on other window should not kill fzf job #2011
  child.lua([[FzfLua.hide()]])
  child.wait_until(function()
    return child.lua_get([[_G._fzf_lua_on_create]]) == vim.NIL
  end)
  child.cmd([[new]])
  child.cmd([[quit]])
  child.lua([[FzfLua.unhide()]])
  child.wait_until(function()
    return child.lua_get([[_G._fzf_lua_on_create]]) == true
  end)
  child.lua([[FzfLua.hide()]])
  child.wait_until(function()
    return child.lua_get([[_G._fzf_lua_on_create]]) == vim.NIL
  end)

  -- can :wqa when there're hide job #1817
  pcall(child.cmd, [[wqa]])
  -- child.is_running() didn't work as expected
  eq(vim.fn.jobwait({ child.job.id }, 1000)[1], 0)
end

T["win"]["hide"]["actions on multi-select but zero-match #1961"] = function()
  reload({ "hide" })
  child.lua([[FzfLua.files{
    -- profile = "hide",
    query = "README.md",
    fzf_opts = { ["--multi"] = true },
  }]])
  -- not work with `profile = "hide"`?
  child.wait_until(function() return child.lua_get([[_G._fzf_load_called]]) == true end)
  child.type_keys([[<tab>]])
  child.type_keys([[a-non-exist-file]])
  child.type_keys([[<cr>]])
  child.wait_until(function() return child.lua_get([[_G._fzf_lua_on_create]]) == vim.NIL end)
  eq("README.md", vim.fs.basename(child.lua_get([[vim.api.nvim_buf_get_name(0)]])))
end


T["win"]["actions"] = new_set()

T["win"]["actions"]["no error"] = function()
  for file in ipairs({ "README.md", "^tests-", ".lua$" }) do
    child.lua([[FzfLua.files { query = "README.md" }]])
    -- not work with `profile = "hide"`?
    child.wait_until(function()
      return child.lua_get([[_G._fzf_load_called]]) == true
    end)
    for key, _actions in pairs({
      ["<F1>"]       = "toggle-help",
      ["<F2>"]       = "toggle-fullscreen",
      ["<F3>"]       = "toggle-preview-wrap",
      ["<F4>"]       = "toggle-preview",
      ["<F5>"]       = "toggle-preview-ccw",
      ["<F6>"]       = "toggle-preview-cw",
      ["<S-Left>"]   = "preview-reset",
      ["<S-down>"]   = "preview-page-down",
      ["<S-up>"]     = "preview-page-up",
      ["<M-S-down>"] = "preview-down",
      ["<M-S-up>"]   = "preview-up",
    }) do
      child.type_keys(key)
      child.type_keys(key)
    end
  end
end

return T
