---@diagnostic disable: unused-local, unused-function
local MiniTest = require("mini.test")
local helpers = require("fzf-lua.test.helpers")
local child = helpers.new_child_neovim()
local expect, eq = helpers.expect, helpers.expect.equality
local new_set = MiniTest.new_set
local exec_lua = child.lua

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
  exec_lua([[
    _G._gc_called = nil
    FzfLua.utils.setmetatable__gc = function(t, mt)
      local prox = newproxy(true)
      getmetatable(prox).__gc = function()
        _G._gc_called = true
        mt.__gc(t)
      end
      t[prox] = true
      return setmetatable(t, mt)
    end
  ]])
  -- Reduce cache size to 20 so functions get evicted quicker
  -- otherwise opts refs that are stored in the funcs are never
  -- cleared preventing the win object's __gc from being called
  exec_lua([[FzfLua.shell.cache_set_size(20)]])
  child.wait_until(function()
    if helpers.IS_WIN() then
      local hidden_fzf_bufnr = child.lua_get(
        [[(FzfLua.utils.fzf_winobj() or {})._hidden_fzf_bufnr]])
      if hidden_fzf_bufnr ~= vim.NIL then
        local chan = child.lua_get(([=[vim.bo[%s].channel]=]):format(hidden_fzf_bufnr))
        child.api.nvim_chan_send(chan, vim.keycode("<c-c>"))
      end
    end
    exec_lua([[FzfLua.files{ previewer = 'builtin' }]])
    child.wait_until(function()
      return child.lua_get([[_G._fzf_load_called]]) == true
    end)
    exec_lua([[FzfLua.hide()]])
    child.wait_until(function()
      return child.lua_get([[_G._fzf_load_called]]) == vim.NIL
    end)
    exec_lua([[collectgarbage('collect')]])
    return child.lua_get([[_G._gc_called]]) == true
  end)
  -- Restore original cache size
  exec_lua([[FzfLua.shell.cache_set_size(50)]])
end

T["win"]["hide"]["buffer deleted after win hidden (#1783)"] = function()
  eq(child.lua_get([[_G._fzf_lua_on_create]]), vim.NIL)
  exec_lua([[FzfLua.files()]])
  child.wait_until(function()
    return child.lua_get([[_G._fzf_lua_on_create]]) == true
  end)
  exec_lua([[FzfLua.hide()]])
  child.wait_until(function()
    return child.lua_get([[_G._fzf_lua_on_create]]) == vim.NIL
  end)
  exec_lua([[
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
  exec_lua([[FzfLua.files()]])
  child.wait_until(function()
    return child.lua_get([[_G._fzf_lua_on_create]]) == true
  end)
  exec_lua([[FzfLua.hide()]])
  child.wait_until(function()
    return child.lua_get([[_G._fzf_lua_on_create]]) == vim.NIL
  end)
  child.cmd([[close]])
  exec_lua([[FzfLua.unhide()]])
  child.wait_until(function()
    return child.lua_get([[_G._fzf_lua_on_create]]) == true
  end)
  child.type_keys("<c-j>")
  child.type_keys("<c-j>")

  -- `:quit` on other window should not kill fzf job #2011
  exec_lua([[FzfLua.hide()]])
  child.wait_until(function()
    return child.lua_get([[_G._fzf_lua_on_create]]) == vim.NIL
  end)
  child.cmd([[new]])
  child.cmd([[quit]])
  exec_lua([[FzfLua.unhide()]])
  child.wait_until(function()
    return child.lua_get([[_G._fzf_lua_on_create]]) == true
  end)
  exec_lua([[FzfLua.hide()]])
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
  exec_lua([[FzfLua.files{
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

T["win"]["keymap"] = new_set({ n_retry = not helpers.IS_LINUX() and 5 or nil })

T["win"]["keymap"]["no error"] = function()
  local builtin = child.lua_get [[FzfLua.defaults.keymap.builtin]]
  for _, event in ipairs({ "start", "load", "result" }) do
    for key, actions in pairs(builtin) do
      exec_lua([[
        FzfLua.files {
          query = "README.md",
          winopts = { preview = { wrap = false } },
          keymap = { true, fzf = { [...] = function() end } },
        }
      ]], { event })
      child.wait_until(function()
        return child.lua_get([[_G._fzf_load_called]]) == true
      end)
      child.type_keys(key)
      if helpers.IS_WIN() then child.type_keys("<c-c>") end
    end
  end
end

T["win"]["previewer"] = new_set({ n_retry = not helpers.IS_LINUX() and 5 or nil })

T["win"]["previewer"]["split flex layout resize"] = function()
  -- Ignore terminal command line with process number
  local screen_opts = { ignore_text = { 24, 28 }, normalize_paths = helpers.IS_WIN() }
  helpers.FzfLua.fzf_exec(child, [==[{ "foo", "bar", "baz" }]==], {
    __no_abort = true,
    __expect_lines = true,
    __screen_opts = screen_opts,
    winopts = {
      split = "enew",
      preview = {
        -- default test screen size is 28,64
        flip_columns = 64,
      }
    },
    previewer = [[require('fzf-lua.test.previewer')]],
    keymap = {
      fzf = {
        resize = function()
          _G._fzf_resize_called = true
        end
      }
    },
    __after_open = function()
      child.wait_until(function()
        return child.lua_get([[FzfLua.utils.fzf_winobj()._previewer.last_entry]]) == "foo"
      end)
    end,
  })
  -- increase size by 1, should flip to vertical preview
  child.set_size(28, 65)
  child.wait_until(function()
    return child.lua_get([[_G._fzf_resize_called]]) == true
  end)
  if helpers.IS_WIN() then vim.uv.sleep(250) end
  child.expect_screen_lines(screen_opts)
  -- abort and wait for winopts.on_close
  child.type_keys("<c-c>")
  child.wait_until(function()
    return child.lua_get([[_G._fzf_lua_on_create]]) == vim.NIL
  end)
end

T["win"]["previewer"]["split flex hidden"] = function()
  -- Ignore terminal command line with process number
  local screen_opts = { ignore_text = { 24, 28 }, normalize_paths = helpers.IS_WIN() }
  helpers.FzfLua.fzf_exec(child, [==[{ "foo", "bar", "baz" }]==], {
    __no_abort = true,
    __expect_lines = true,
    __screen_opts = screen_opts,
    winopts = {
      split = "enew",
      preview = {
        -- default test screen size is 28,64
        flip_columns = 64,
        -- start hidden
        hidden = true
      }
    },
    previewer = [[require('fzf-lua.test.previewer')]],
    __after_open = function()
      if helpers.IS_WIN() then vim.uv.sleep(250) end
    end,
  })
  -- increase size by 1, should flip to vertical preview
  child.set_size(28, 65)
  exec_lua([[require("fzf-lua.win").toggle_preview()]])
  child.wait_until(function()
    return child.lua_get([[FzfLua.utils.fzf_winobj()._previewer.last_entry]]) == "foo"
  end)
  if helpers.IS_WIN() then vim.uv.sleep(250) end
  child.expect_screen_lines(screen_opts)
  -- abort and wait for winopts.on_close
  child.type_keys("<c-c>")
  child.wait_until(function()
    return child.lua_get([[_G._fzf_lua_on_create]]) == vim.NIL
  end)
end

return T
