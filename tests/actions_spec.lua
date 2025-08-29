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

  exec_lua([[FzfLua.fzf_exec(function(cb) cb(1) cb(2) error("eff") end)]])
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
      and [[function(cb) cb(_G._fzf_reload and 'reloaded' or 'unreloaded') cb(nil) end]]
      or [[function() return { _G._fzf_reload and 'reloaded' or 'unreloaded' } end ]],
      {
        __no_abort = true,
        __expect_lines = false,
        __after_open = function()
          if helpers.IS_WIN() then vim.uv.sleep(250) end
        end,
        actions = {
          ["ctrl-a"] = { fn = function() _G._fzf_reload = true end, reload = true },
        },
      })
    child.type_keys("<c-a>")
    child.wait_until(function() return child.lua_get([[_G._fzf_reload]]) == true end)
    if helpers.IS_WIN() then vim.uv.sleep(250) end
    child.expect_screen_lines(screen_opts)
  end
})

return T
