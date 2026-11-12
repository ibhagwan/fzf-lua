---@diagnostic disable: unused-local, unused-function, unused
local MiniTest = require("mini.test")
local helpers = require("fzf-lua.test.helpers")
local child = helpers.new_child_neovim()
local eq = helpers.expect.equality
local new_set = MiniTest.new_set
local exec_lua = child.lua

-- Helpers with child processes
-- fmt: off
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
-- fmt: on

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
        [[(FzfLua.utils.fzf_winobj() or {})._hidden_fzf_bufnr]]
      )
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

T["win"]["hide"]["preview buffers cleared when hidden win replaced (#2855)"] = function()
  reload({ "hide" })
  local bcache_size = function()
    return child.lua_get(
      [[(function()
      local win = FzfLua.utils.fzf_winobj()
      local previewer = win and win._previewer
      return previewer and previewer.bcache and vim.tbl_count(previewer.bcache.entries) or 0
    end)()]]
    )
  end
  local preview_bufs = function()
    return child.lua_get(
      [[#vim.tbl_filter(function(buf)
      return vim.bo[buf].buftype == "nofile" and vim.bo[buf].bufhidden == "hide"
    end, vim.api.nvim_list_bufs())]]
    )
  end
  local cycle = function()
    exec_lua([[FzfLua.files({ previewer = "builtin" })]])
    child.wait_until(function() return child.lua_get([[_G._fzf_load_called]]) == true end)
    -- cache a preview for each of the first five entries
    child.wait_until(function() return bcache_size() >= 1 end)
    for i = 2, 5 do
      child.type_keys("<c-n>")
      child.wait_until(function() return bcache_size() >= i end)
    end
    exec_lua([[FzfLua.hide()]])
    child.wait_until(function() return child.lua_get([[_G._fzf_lua_on_create]]) == vim.NIL end)
  end
  -- the hidden picker's cached previews must stay for `:FzfLua resume`
  cycle()
  local cached = preview_bufs()
  eq(cached, 5)
  -- replacing the hidden picker must delete the previous preview buffers
  cycle()
  eq(preview_bufs(), cached)
  cycle()
  eq(preview_bufs(), cached)
end

T["win"]["hide"]["pending preview read is safe after cache clear (#2855)"] = function()
  reload({ "hide" })
  exec_lua(
    [[
    _G._preview_dir = vim.fn.tempname()
    vim.fn.mkdir(_G._preview_dir, "p")
    vim.fn.writefile({ "a" }, _G._preview_dir .. "/a.txt")
    vim.fn.writefile({ "b" }, _G._preview_dir .. "/b.txt")
    _G._read_file_async = require("fzf-lua.utils").read_file_async
    _G._pending_reads = {}
  ]]
  )
  local bcache_size = function()
    return child.lua_get(
      [[(function()
      local win = FzfLua.utils.fzf_winobj()
      local previewer = win and win._previewer
      return previewer and previewer.bcache and vim.tbl_count(previewer.bcache.entries) or 0
    end)()]]
    )
  end
  exec_lua([[FzfLua.files({ cwd = _G._preview_dir, previewer = "builtin" })]])
  child.wait_until(function() return child.lua_get([[_G._fzf_load_called]]) == true end)
  child.wait_until(function() return bcache_size() == 1 end)
  child.type_keys("<c-n>")
  child.wait_until(function() return bcache_size() == 2 end)
  -- intercept the next read and make both cache entries stale
  exec_lua(
    [[
    require("fzf-lua.utils").read_file_async = function(path, cb)
      table.insert(_G._pending_reads, { path = path, cb = cb })
    end
    for _, name in ipairs({ "a.txt", "b.txt" }) do
      vim.uv.fs_utime(_G._preview_dir .. "/" .. name, 1700000000, 1700000000)
    end
  ]]
  )
  child.type_keys("<c-p>")
  child.wait_until(function() return child.lua_get([[#_G._pending_reads]]) == 1 end)
  exec_lua([[FzfLua.hide()]])
  child.wait_until(function() return child.lua_get([[_G._fzf_lua_on_create]]) == vim.NIL end)
  -- replacing the hidden picker clears the cached preview buffers
  exec_lua(
    [[
    require("fzf-lua.utils").read_file_async = _G._read_file_async
    FzfLua.files({ cwd = _G._preview_dir, previewer = false })
  ]]
  )
  child.wait_until(function() return child.lua_get([[_G._fzf_load_called]]) == true end)
  -- the in-flight read must not write to the deleted cached buffer
  exec_lua(
    [[
    _G._async_err = nil
    local schedule = vim.schedule
    vim.schedule = function(fn)
      return schedule(function()
        local ok, err = pcall(fn)
        if not ok then _G._async_err = err end
      end)
    end
    for _, pending in ipairs(_G._pending_reads) do
      pcall(pending.cb, "data")
    end
  ]]
  )
  sleep(100)
  eq(child.lua_get([[_G._async_err]]), vim.NIL)
end

T["win"]["hide"]["fresh pending preview read buffer is deleted (#2855)"] = function()
  reload({ "hide" })
  exec_lua(
    [[
    _G._preview_dir = vim.fn.tempname()
    vim.fn.mkdir(_G._preview_dir, "p")
    vim.fn.writefile({ "a" }, _G._preview_dir .. "/a.txt")
    _G._read_file_async = require("fzf-lua.utils").read_file_async
    _G._pending_reads = {}
    require("fzf-lua.utils").read_file_async = function(path, cb)
      table.insert(_G._pending_reads, { path = path, cb = cb })
      local attached = {}
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        attached[vim.api.nvim_win_get_buf(win)] = true
      end
      local bufs = vim.tbl_filter(function(buf)
        return not attached[buf]
            and vim.bo[buf].buftype == "nofile"
            and vim.bo[buf].bufhidden == "wipe"
            and vim.bo[buf].modeline
      end, vim.api.nvim_list_bufs())
      _G._pending_buf = bufs[#bufs]
    end
  ]]
  )
  exec_lua([[FzfLua.files({ cwd = _G._preview_dir, previewer = "builtin" })]])
  child.wait_until(function() return child.lua_get([[_G._fzf_load_called]]) == true end)
  child.wait_until(function() return child.lua_get([[#_G._pending_reads]]) == 1 end)
  eq(child.lua_get([[vim.api.nvim_buf_is_valid(_G._pending_buf)]]), true)
  exec_lua([[FzfLua.hide()]])
  child.wait_until(function() return child.lua_get([[_G._fzf_lua_on_create]]) == vim.NIL end)
  -- replacing the hidden picker discards the previewer
  exec_lua(
    [[
    require("fzf-lua.utils").read_file_async = _G._read_file_async
    FzfLua.files({ cwd = _G._preview_dir, previewer = false })
  ]]
  )
  child.wait_until(function() return child.lua_get([[_G._fzf_load_called]]) == true end)
  -- the fresh cache-miss buffer can no longer be displayed, delete it
  exec_lua(
    [[
    for _, pending in ipairs(_G._pending_reads) do
      pcall(pending.cb, "data")
    end
  ]]
  )
  sleep(100)
  eq(child.lua_get([[vim.api.nvim_buf_is_valid(_G._pending_buf)]]), false)
end

T["win"]["hide"]["superseded pending preview read buffer is deleted (#2855)"] = function()
  reload({ "hide" })
  exec_lua(
    [[
    _G._preview_dir = vim.fn.tempname()
    vim.fn.mkdir(_G._preview_dir, "p")
    vim.fn.writefile({ "a" }, _G._preview_dir .. "/a.txt")
    vim.fn.writefile({ "b" }, _G._preview_dir .. "/b.txt")
    _G._read_file_async = require("fzf-lua.utils").read_file_async
    _G._pending_reads = {}
    require("fzf-lua.utils").read_file_async = function(path, cb)
      local attached = {}
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        attached[vim.api.nvim_win_get_buf(win)] = true
      end
      local bufs = vim.tbl_filter(function(buf)
        return not attached[buf]
            and vim.bo[buf].buftype == "nofile"
            and vim.bo[buf].bufhidden == "wipe"
            and vim.bo[buf].modeline
      end, vim.api.nvim_list_bufs())
      table.insert(_G._pending_reads, { path = path, cb = cb, buf = bufs[#bufs] })
    end
  ]]
  )
  local buf_valid = function(bufnr)
    return child.lua_get(([[vim.api.nvim_buf_is_valid(%d)]]):format(bufnr))
  end
  exec_lua([[FzfLua.files({ cwd = _G._preview_dir, previewer = "builtin" })]])
  child.wait_until(function() return child.lua_get([[_G._fzf_load_called]]) == true end)
  child.wait_until(function() return child.lua_get([[#_G._pending_reads]]) == 1 end)
  local first_buf = child.lua_get([[_G._pending_reads[1].buf]])
  -- select B before A's cache-miss read completes
  child.type_keys("<c-n>")
  child.wait_until(function() return child.lua_get([[#_G._pending_reads]]) == 2 end)
  local second_buf = child.lua_get([[_G._pending_reads[2].buf]])
  eq(buf_valid(first_buf), true)
  eq(buf_valid(second_buf), true)
  exec_lua([[FzfLua.hide()]])
  child.wait_until(function() return child.lua_get([[_G._fzf_lua_on_create]]) == vim.NIL end)
  -- replacing the hidden picker discards the previewer
  exec_lua(
    [[
    require("fzf-lua.utils").read_file_async = _G._read_file_async
    FzfLua.files({ cwd = _G._preview_dir, previewer = false })
  ]]
  )
  child.wait_until(function() return child.lua_get([[_G._fzf_load_called]]) == true end)
  -- both the superseded and current pending read buffers must be cleaned up
  exec_lua(
    [[
    for _, pending in ipairs(_G._pending_reads) do
      pcall(pending.cb, "data")
    end
  ]]
  )
  sleep(100)
  eq(buf_valid(first_buf), false)
  eq(buf_valid(second_buf), false)
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
  local job = child.job
  if not job then error("child.job is nil after :wqa") end
  local job_id = job.id --[[@as integer]]
  local res = vim.fn.jobwait({ job_id }, 1000)
    [1]
  -- 0 = normal exit, -3 = already exited/invalid (acceptable race)
  local valid_res = { [0] = true, [-3] = true }
  eq(valid_res[res] or res, true) -- HACK: show the res code in the assert
end

T["win"]["hide"]["actions on multi-select but zero-match #1961"] = function()
  reload({ "hide" })
  exec_lua(
    [[FzfLua.files{
    -- profile = "hide",
    query = "README.md",
    fzf_opts = { ["--multi"] = true },
  }]]
  )
  -- not work with `profile = "hide"`?
  child.wait_until(function() return child.lua_get([[_G._fzf_load_called]]) == true end)
  child.type_keys([[<tab>]])
  child.type_keys([[a-non-exist-file]])
  child.type_keys([[<cr>]])
  child.wait_until(function() return child.lua_get([[_G._fzf_lua_on_create]]) == vim.NIL end)
  eq("README.md", vim.fs.basename(child.lua_get([[vim.api.nvim_buf_get_name(0)]])))
end

T["win"]["hide"]["nohidden"] = function()
  reload({ "hide" })
  exec_lua([[vim.o.hidden = false]])
  helpers.FzfLua.files(child, {
    __abort_key = "<esc>",
    __expect_lines = false,
    __after_open = function() if helpers.IS_WIN() then vim.uv.sleep(250) end end,
    query = "LICENSE$",
  })
end

T["win"]["keymap"] = new_set({ n_retry = not helpers.IS_LINUX() and 5 or nil })

T["win"]["keymap"]["no error"] = new_set({
  parametrize = (function()
    local builtin = require("fzf-lua.defaults")
      .defaults
      .keymap
      .builtin
    ---@cast builtin table
    local out = {}
    for key, action in pairs(builtin) do
      out[#out + 1] = { key, action }
    end
    return out
  end)(),
},
  {
    function(key, action)
      for _, event in ipairs({ "start", "load", "result" }) do
        helpers.FzfLua.files(child, {
          __no_abort = true,
          __expect_lines = false,
          __after_open = function()
            if helpers.IS_WIN() then vim.uv.sleep(250) end
            -- Press the key being tested, then give window-affecting actions
            -- (e.g. toggle-fullscreen) a moment to settle before closing.
            -- On Windows, sending the action and abort too close together can
            -- crash the child RPC channel.
            child.type_keys(key)
            sleep(100)
            if helpers.IS_WIN() then sleep(250) end
            child.type_keys("<c-c>")
            child.wait_until(function()
              return child.lua_get([[_G._fzf_lua_on_create]]) == vim.NIL
            end, 5000)
          end,
          query = "README.md",
          winopts = { preview = { wrap = false } },
          keymap = { true, fzf = { [event] = function() end } },
        })
      end
    end,
  })

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
      },
    },
    previewer = function() return require("fzf-lua.test.previewer").builtin end,
    keymap = { fzf = { resize = function() _G._fzf_resize_called = true end } },
    __after_open = function()
      if helpers.IS_WIN() then vim.uv.sleep(250) end
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
  sleep(100)
  if not helpers.IS_LINUX() then sleep(250) end
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
        hidden = true,
      },
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
T["win"]["toggle"] = new_set({
  parametrize = { { "EB" }, { "EF" }, { "B" }, { "F" } },
  n_retry = not helpers.IS_LINUX() and 5 or 2,
})
T["win"]["toggle"][""] = new_set({
  parametrize = {
    { {} },
    { { winopts = { split = "enew" } } },
    { { winopts = { split = "botright new", preview = { layout = "horizontal" } } } },
    { { profile = "border-fused" } },
    { { profile = "borderless-full", winopts = { preview = { layout = "horizontal" } } } },
    { { winopts = { border = false } } },
    { { winopts = { preview = { vertical = "down:4" } } } },
    { { winopts = { preview = { border = false } } } },
  },
},
  {
    -- Ignore terminal command line with process number
    function(a, o)
      local screen_opts = { ignore_text = { 24, 28 }, normalize_paths = helpers.IS_WIN() }
      local opts = {
        __no_abort = true,
        __expect_lines = true,
        __screen_opts = screen_opts,
        winopts = { preview = { hidden = true, delay = 0 } },
        __after_open = function()
          child.wait_until(function() return child.lua_get([[_G._fzf_load_called]]) == true end)
          if helpers.IS_WIN() then vim.uv.sleep(250) end
        end,
      }
      ---@diagnostic disable-next-line: assign-type-mismatch
      opts = vim.tbl_deep_extend("force", opts, o)
      -- don't modify o directly, otherwise it will change screenshots name
      if a:match("E") then
        ---@diagnostic disable-next-line: assign-type-mismatch
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

T["win"]["relative=cursor"] = function()
  -- Ignore terminal command line with process number
  local screen_opts = { ignore_text = { 24, 28 }, normalize_paths = helpers.IS_WIN() }
  local opts = {
    __expect_lines = true,
    __screen_opts = screen_opts,
    winopts = {
      relative = "cursor",
      preview = { layout = "horizontal", horizontal = "left:50%" },
    },
    previewer = function() return require("fzf-lua.test.previewer").builtin end,
    __after_open = function()
      child.wait_until(function() return child.lua_get([[_G._fzf_load_called]]) == true end)
      sleep(100)
      if not helpers.IS_LINUX() then sleep(250) end
    end,
  }
  helpers.FzfLua.fzf_exec(child, { "foo", "bar", "baz" }, opts)
  child.cmd([[enew]])
  set_lines({ ("a"):rep(child.o.columns) })
  type_keys("g$")
  -- pretend we closed the window to make helpers won't wait for new open
  exec_lua([[_G._fzf_lua_on_create = nil]])
  exec_lua([[_G._fzf_load_called = nil]])
  helpers.FzfLua.fzf_exec(child, { "foo", "bar", "baz" }, opts)
  child.cmd([[bwipe!]])
end

T["win"]["reuse"] = new_set({
  parametrize = {
    { {} },
    { { winopts = { split = "enew" } } },
    { { winopts = { split = "botright new", preview = { layout = "horizontal" } } } },
  },
  n_retry = not helpers.IS_LINUX() and 5 or nil,
},
  {
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
          child.wait_until(function() return child.lua_get([[_G._fzf_load_called]]) == true end)
          sleep(100)
          if not helpers.IS_LINUX() then sleep(250) end
        end,
      }
      ---@diagnostic disable-next-line: assign-type-mismatch
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
      exec_lua(
        [[
      require('fzf-lua').fzf_exec({ 'a', 'b' },{ preview = "echo builtin" })
      require('fzf-lua').fzf_exec({ 'b', 'c' }, { previewer = require('fzf-lua.test.previewer').builtin })
    ]]
      )
      toggle_preview()
    end,
  })

T["win"]["highlight"] = new_set({ n_retry = not helpers.IS_LINUX() and 5 or nil })

T["win"]["highlight"]["unchange when reuse win #2588"] = function()
  helpers.SKIP_IF_WIN() -- windows attr looks different
  local opts = {
    __no_abort = true,
    __after_open = function()
      sleep(100)
      if not helpers.IS_LINUX() then sleep(250) end
    end,
    cwd_prompt = false,
  }
  helpers.FzfLua.files(child, opts)
  -- pretend we closed the window to make helpers won't wait for new open
  exec_lua([[_G._fzf_lua_on_create = nil]])
  exec_lua([[_G._fzf_load_called = nil]])
  helpers.FzfLua.files(child, opts)
end

T["win"]["restore last window"] = new_set()

T["win"]["restore last window"]["does not trigger float autoclose (#2837)"] = function()
  exec_lua(
    [[
    _G._float_win = vim.api.nvim_open_win(vim.api.nvim_create_buf(false, true), true, {
      relative = "editor",
      width = 20,
      height = 5,
      row = 1,
      col = 1,
    })
    vim.bo[vim.api.nvim_win_get_buf(_G._float_win)].buftype = "nofile"
    -- mimic Mason's autoclose handler: close the float when a regular
    -- buffer is entered
    vim.api.nvim_create_autocmd("WinEnter", {
      callback = function()
        local buftype = vim.bo.buftype
        if buftype ~= "prompt" and buftype ~= "nofile" then
          vim.schedule(function()
            if vim.api.nvim_win_is_valid(_G._float_win) then
              vim.api.nvim_win_close(_G._float_win, true)
            end
          end)
        end
      end,
    })
  ]]
  )
  exec_lua([[FzfLua.files{ query = "README.md" }]])
  child.wait_until(function() return child.lua_get([[_G._fzf_load_called]]) == true end)
  child.type_keys("<esc>")
  child.wait_until(function() return child.lua_get([[_G._fzf_lua_on_create]]) == vim.NIL end)
  sleep(100)
  eq(true, child.lua_get([[vim.api.nvim_win_is_valid(_G._float_win)]]))
  exec_lua(
    [[if vim.api.nvim_win_is_valid(_G._float_win) then vim.api.nvim_win_close(_G._float_win, true) end]]
  )
end

T["win"]["restore last window"]["keeps events for regular windows (#2812)"] = function()
  exec_lua(
    [[
    -- Keep the original window as the intermediate target.
    vim.cmd("split")
    vim.cmd("enew")
    _G._src_win = vim.api.nvim_get_current_win()
    _G._src_win_enter = 0
    _G._src_buf_enter = 0
    vim.api.nvim_create_autocmd({ "WinEnter", "BufEnter" }, {
      callback = function(args)
        if vim.api.nvim_get_current_win() ~= _G._src_win then return end
        if args.event == "WinEnter" then
          _G._src_win_enter = _G._src_win_enter + 1
        else
          _G._src_buf_enter = _G._src_buf_enter + 1
        end
      end,
    })
  ]]
  )
  exec_lua([[FzfLua.files{ query = "README.md" }]])
  child.wait_until(function() return child.lua_get([[_G._fzf_load_called]]) == true end)
  -- only count the events fired while closing, not the ones from opening fzf
  exec_lua([[_G._src_win_enter = 0; _G._src_buf_enter = 0]])
  child.type_keys("<esc>")
  child.wait_until(function() return child.lua_get([[_G._fzf_lua_on_create]]) == vim.NIL end)
  eq(true, child.lua_get([[_G._src_win_enter > 0]]))
  eq(true, child.lua_get([[_G._src_buf_enter > 0]]))
end

T["win"]["treesitter"] = new_set()

T["win"]["treesitter"]["short lines do not break highlight parsing"] = function()
  -- Short rows (e.g. the "> " prompt and "  1/1" counter) used to produce
  -- an `end_col < start_col` region which treesitter rejects on parse
  exec_lua(
    [[
    local tsinjector = require("fzf-lua.win.tsinjector")
    _G._ts_buf = vim.api.nvim_create_buf(false, true)
    _G._ts_detach = tsinjector.attach({ winopts = {}, preview_hidden = true }, _G._ts_buf,
      function(line) return "foo.vim", nil, line end)
    vim.api.nvim_buf_set_lines(_G._ts_buf, 0, -1, false,
      { "FzfLua command_history", "> " })
  ]]
  )
  eq(
    true,
    child.lua_get(
      [[(function()
    local tsinjector = require("fzf-lua.win.tsinjector")
    local ok = pcall(function()
      tsinjector.cache[_G._ts_buf].vim.highlighter.tree:parse({ 0, 3 })
    end)
    if not ok then return false end
    -- the valid line must still produce a non-empty region
    local regions = tsinjector.cache[_G._ts_buf].vim.parser:included_regions()
    local range = regions[1] and regions[1][1]
    return #regions == 1 and range and range[5] > range[2]
  end)()]]
    )
  )
  exec_lua([[_G._ts_detach()]])
end

return T
