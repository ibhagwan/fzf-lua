---@diagnostic disable: unused-local, unused-function
local MiniTest = require("mini.test")
local helpers = require("fzf-lua.test.helpers")
local child = helpers.new_child_neovim()
local expect, eq = helpers.expect, helpers.expect.equality
local new_set = MiniTest.new_set

local T = helpers.new_set_with_child(child)

T["api"] = new_set()

T["api"]["fzf_exec"] = new_set()

T["api"]["fzf_exec"]["table"] = function()
  helpers.FzfLua.fzf_exec(child,
    [==[(function()
      local contents = {}
      for i = 1, 100 do
        for j, s in ipairs({ "foo", "bar", "baz" }) do
          table.insert(contents, tostring((i - 1) * 3 + j) .. ": " .. s)
        end
      end
      return contents
    end)()]==],
    { __expect_lines = true, __postprocess_wait = true })
end

T["api"]["fzf_exec"]["function"] = new_set({ parametrize = { { "sync" }, { "async" } } }, {
  function(type)
    if type == "sync" then
      helpers.FzfLua.fzf_exec(child, [==[(function(fzf_cb)
          for i=1, 1000 do
            fzf_cb(tostring(i))
          end
          fzf_cb(nil)
        end)
        ]==],
        { __expect_lines = true, __postprocess_wait = true })
    else
      helpers.FzfLua.fzf_exec(child, [==[(coroutine.wrap(function(fzf_cb)
          local co = coroutine.running()
          for i=1, 1000 do
            fzf_cb(tostring(i), function() coroutine.resume(co) end)
            coroutine.yield()
          end
          fzf_cb(nil)
        end))
        ]==],
        { __expect_lines = true, __postprocess_wait = true })
    end
  end,
})

return T
