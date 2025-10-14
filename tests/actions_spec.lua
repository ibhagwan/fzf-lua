---@diagnostic disable: unused-local, unused-function
local MiniTest = require("mini.test")
local helpers = require("fzf-lua.test.helpers")
local child = helpers.new_child_neovim()
local expect, eq = helpers.expect, helpers.expect.equality
local new_set = MiniTest.new_set

---@format disable-next
local reload = function(config) child.unload(); child.setup(config) end
local sleep = function(ms) helpers.sleep(ms, child) end
local exec_lua = child.lua
--stylua: ignore end

local T = helpers.new_set_with_child(child)

T["actions"] = new_set({ n_retry = not helpers.IS_LINUX() and 5 or nil })

T["actions"]["ui don't freeze on error"] = function()
  -- reload({ "hide" })
  local screen_opts = { ignore_text = { 28 } }
  exec_lua(
    [[FzfLua.fzf_exec({ "aaa", "bbb" }, {
      actions = { enter = { fn = error, exec_silent = true } },
    })]])
  child.wait_until(function() return child.lua_get([[_G._fzf_load_called]]) == true end)
  child.type_keys("<cr>")
  child.type_keys("ui should not freeze on action error")
  vim.uv.sleep(100 * (not helpers.IS_LINUX() and 5 or 1))
  child.expect_screen_lines(screen_opts)

  exec_lua([[FzfLua.fzf_exec(function(cb) cb(1) cb(2) error("err") end, {
      fzf_opts = { ['--no-info'] = true, ['--info'] = false },
    })]])
  child.wait_until(function() return child.lua_get([[_G._fzf_load_called]]) == true end)
  child.type_keys("ui should not freeze on content error")
  vim.uv.sleep(100 * (not helpers.IS_LINUX() and 5 or 1))
  child.expect_screen_lines(screen_opts)
  child.v.errmsg = ""
end

T["actions"]["reload"] = new_set({
  parametrize = { { "fzf_live" }, { "fzf_exec" } }
}, {
  function(api)
    local screen_opts = { ignore_text = { 28 } }
    helpers.FzfLua[api](child, api == "fzf_exec"
      and function(cb)
        local fzf_reload = _G._fzf_reload ---@type any
        ---@diagnostic disable-next-line: undefined-field
        if _G._fzf_lua_server then ---@diagnostic disable-next-line: undefined-field
          local chan_id = vim.fn.sockconnect("pipe", _G._fzf_lua_server, { rpc = true })
          fzf_reload = vim.rpcrequest(chan_id, "nvim_exec_lua", [[return _G.__fzf_lua_server]], {})
          vim.fn.chanclose(chan_id)
        end
        cb(fzf_reload and "reloaded" or "unreloaded")
        cb(nil)
      end
      or function()
        local fzf_reload = _G._fzf_reload ---@type any
        ---@diagnostic disable-next-line: undefined-field
        if _G._fzf_lua_server then ---@diagnostic disable-next-line: undefined-field
          local chan_id = vim.fn.sockconnect("pipe", _G._fzf_lua_server, { rpc = true })
          fzf_reload = vim.rpcrequest(chan_id, "nvim_exec_lua", [[return _G.__fzf_lua_server]], {})
          vim.fn.chanclose(chan_id)
        end
        return { fzf_reload and "reloaded" or "unreloaded" }
      end,
      {
        __no_abort = true,
        __expect_lines = true,
        __screen_opts = screen_opts,
        __after_open = function()
          if helpers.IS_WIN() then vim.uv.sleep(250) end
          child.type_keys("<c-a>")
          if helpers.IS_WIN() then vim.uv.sleep(250) end
          child.wait_until(function() return child.lua_get([[_G._fzf_reload]]) == true end)
        end,
        actions = {
          ["ctrl-a"] = { fn = function() _G._fzf_reload = true end, reload = true },
        },
      })
  end
})


T["actions"]["vimcmd"] = new_set({
  parametrize = {
    { "drop" },
    { "file_edit" },
    { "file_split" },
    { "file_vsplit" },
    { "file_tabedit" },
    { "file_open_in_background" },
  },
}, {
  function(action)
    local ctx = function()
      return {
        buf = child.api.nvim_get_current_buf(),
        win = child.api.nvim_get_current_win(),
        tab = child.api.nvim_get_current_tabpage(),
        name = vim.fs.basename(child.api.nvim_buf_get_name(0)),
      }
    end
    local actions = {
      ["ctrl-a"] = function(...)
        _G._fzf_info = FzfLua.get_info()
        if action == "drop" then return require("fzf-lua.actions").vimcmd_entry("drop", ...) end
        return require("fzf-lua.actions")[action](...)
      end,
    }

    helpers.FzfLua.files(child, {
      __abort_key = "<c-a>",
      __expect_lines = false,
      __after_open = function()
        if helpers.IS_WIN() then vim.uv.sleep(250) end
      end,
      query = "LICENSE$",
      actions = actions,
    })
    local _ctx = ctx()
    if action ~= "file_open_in_background" then
      eq({ "LICENSE", 1 }, { _ctx.name, child.fn.line(".") })
    end
    eq("files", exec_lua([[return _G._fzf_info.cmd]]))

    -- work with line number
    vim.cmd.tabnew()
    -- ignore tabline
    local screen_opts = {
      -- windows / -> \
      -- windows tabline is cmd.exe
      ignore_text = helpers.IS_WIN() and { 1, 3, 4, 24 } or { 24 },
      normalize_paths = helpers.IS_WIN(),
    }
    child.o.tabline = "%{%nvim_list_tabpages()->len()%} %{%expand('%:t')%}"
    helpers.FzfLua.live_grep(child, {
      __screen_opts = screen_opts,
      __abort_key = "<c-a>",
      __expect_lines = true,
      __after_open = function()
        child.wait_until(function() return child.lua_get([[_G._fzf_load_called]]) == true end)
        if helpers.IS_WIN() then vim.uv.sleep(250) end
      end,
      no_esc = true,
      search = [[Copyright \(c\) -- LICENSE]],
      actions = actions,
    })
    if action == "drop" then eq(_ctx, ctx()) end
    if action ~= "file_open_in_background" then
      eq({ "LICENSE", 3 }, { _ctx.name, child.fn.line(".") })
    end
    eq("live_grep", exec_lua([[return _G._fzf_info.cmd]]))
  end
})


return T
