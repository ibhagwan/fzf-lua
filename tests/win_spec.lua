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
  exec_lua([[_G._fzf_lua_gc_called = nil]])
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
    return child.lua_get([[_G._fzf_lua_gc_called]]) == true
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

T["win"]["keymap"]["no error"] = new_set({
  parametrize = vim.iter(require("fzf-lua.defaults").defaults.keymap.builtin)
      :map(function(key, action) return { key, action } end)
      :totable()
}, {
  function(key, _action)
    local builtin = child.lua_get [[FzfLua.defaults.keymap.builtin]]
    for _, event in ipairs({ "start", "load", "result" }) do
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
      child.type_keys("<c-c>")
      child.wait_until(function()
        return child.lua_get([[_G._fzf_load_called]]) == vim.NIL
      end)
    end
  end })

T["win"]["previewer"] = new_set({ n_retry = not helpers.IS_LINUX() and 5 or nil })

T["win"]["previewer"]["split flex layout resize"] = function()
  -- Ignore terminal command line with process number
  local screen_opts = { ignore_text = { 24, 28 }, normalize_paths = helpers.IS_WIN() }
  helpers.FzfLua.fzf_exec(child, { "foo", "bar", "baz" }, {
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
    previewer = function() return require("fzf-lua.test.previewer").builtin end,
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

local toggle_preview = function(opts, screen_opts)
  opts = opts or {}
  child.wait_until(function() return child.api.nvim_get_mode().mode == "t" end)
  exec_lua([[require("fzf-lua.win").toggle_preview()]])
  if helpers.IS_WIN() then
    vim.uv.sleep(250)
  elseif opts.preview then
    vim.uv.sleep(100)
  else
    vim.uv.sleep(100)
    -- child.wait_until(function()
    --   return child.lua_get([[FzfLua.utils.fzf_winobj()._previewer.last_entry]]) == "foo"
    -- end)
  end
  if screen_opts then child.expect_screen_lines(screen_opts) end
  -- abort and wait for winopts.on_close
  child.type_keys("<c-c>")
  child.wait_until(function()
    return child.lua_get([[_G._fzf_lua_on_create]]) == vim.NIL
  end)
end

T["win"]["previewer"]["split flex hidden"] = function()
  -- Ignore terminal command line with process number
  local screen_opts = { ignore_text = { 24, 28 }, normalize_paths = helpers.IS_WIN() }
  local opts = {
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
    previewer = function() return require("fzf-lua.test.previewer").builtin end,
    __after_open = function()
      if helpers.IS_WIN() then vim.uv.sleep(250) end
    end,
  }
  helpers.FzfLua.fzf_exec(child, { "foo", "bar", "baz" }, opts)
  -- increase size by 1, should flip to vertical preview
  child.set_size(28, 65)
  toggle_preview(opts, screen_opts)
end

-- E: toggle_behavior=extend, B: builtin previewer, F: "echo {}" preview
T["win"]["toggle"] = new_set({ parametrize = { { "EB" }, { "EF" }, { "B" }, { "F" } } })
T["win"]["toggle"][""] = new_set(
  {
    parametrize = {
      { {} },
      { { winopts = { split = "enew", } } },
      { { winopts = { split = "botright new", preview = { layout = "horizontal" } } } },
      { { profile = "border-fused" } },
      { { profile = "borderless-full", winopts = { preview = { layout = "horizontal" } }, } },
      { { winopts = { border = false } } },
      { { winopts = { preview = { vertical = "down:4" } } } },
      { { winopts = { preview = { border = false } } } },
    }
  }, {
    -- Ignore terminal command line with process number
    function(a, o)
      local screen_opts = { ignore_text = { 24, 28 }, normalize_paths = helpers.IS_WIN() }
      local opts = {
        __no_abort = true,
        __expect_lines = true,
        __screen_opts = screen_opts,
        winopts = { preview = { hidden = true, delay = 0 } },
        __after_open = function()
          if helpers.IS_WIN() then vim.uv.sleep(250) end
        end,
      }
      opts = vim.tbl_deep_extend("force", opts, o)
      -- don't modify o directly, otherwise it will change screenshots name
      if a:match("E") then
        opts = vim.tbl_deep_extend("force", opts, { winopts = { toggle_behavior = "extend" } })
      end
      if a:match("B") then
        opts.previewer = function() return require("fzf-lua.test.previewer").builtin end
      elseif a:match("F") then
        opts.previewer = function() return require("fzf-lua.test.previewer").fzf end
      else
        error("unreachable")
      end
      helpers.FzfLua.fzf_exec(child, { "foo", "bar", "baz" }, opts)
      toggle_preview(opts, screen_opts)
    end
  })

T["win"]["reuse"] = new_set({
  parametrize = {
    { {} },
    { { winopts = { split = "enew", } } },
    { { winopts = { split = "botright new", preview = { layout = "horizontal" } } } },
  }
}, {
  function(o)
    -- Ignore terminal command line with process number
    local screen_opts = { ignore_text = { 24, 28 }, normalize_paths = helpers.IS_WIN() }
    local opts = {
      __no_abort = true,
      __expect_lines = false,
      __screen_opts = screen_opts,
      winopts = {
        toggle_behavior = "extend",
        preview = { hidden = false, delay = 0 },
      },
      previewer = function() return require("fzf-lua.test.previewer").builtin end,
      __after_open = function()
        if helpers.IS_WIN() then vim.uv.sleep(250) end
      end,
    }
    opts = vim.tbl_deep_extend("force", opts, o)
    helpers.FzfLua.fzf_exec(child, { "foo", "bar", "baz" }, opts)
    -- change to fzf preview
    opts.previewer = nil
    opts.preview = "echo resue windows, change from builtin to fzf preview"
    opts.__expect_lines = true
    opts.__no_abort = nil
    exec_lua([[_G._fzf_lua_on_create = nil]])
    exec_lua([[_G._fzf_load_called = nil]])
    helpers.FzfLua.fzf_exec(child, { "foo", "bar", "baz" }, opts)

    -- toggle_preview on hide profile
    reload({ "hide" })
    exec_lua([[
      require('fzf-lua').fzf_exec({ 'a', 'b' },{ preview = "echo builtin" })
      require('fzf-lua').fzf_exec({ 'b', 'c' }, { previewer = require('fzf-lua.test.previewer').builtin })
    ]])
    toggle_preview()
  end
})

return T
