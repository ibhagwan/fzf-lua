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
  helpers.FzfLua.fzf_exec(child, [==[(function()
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
        end))]==],
        { __expect_lines = true, __postprocess_wait = true })
    end
  end,
})

T["api"]["fzf_exec"]["rg"] = new_set({ parametrize = { { true }, { false }, { 1 } } }, {
  function(multiprocess)
    helpers.FzfLua.fzf_exec(child,
      [['rg --files -g "!.git" --sort=path']],
      {
        __expect_lines = true,
        debug = 1,
        multiprocess = multiprocess,
      })
  end
})


T["api"]["fzf_live"] = new_set()

T["api"]["fzf_live"]["table"] = function()
  helpers.FzfLua.fzf_live(child, [==[function(args)
      local q = args[1]
      if not tonumber(q) then
        return { "Invalid number: " .. tostring(q) }
      end
      local lines = {}
      for i = 1, tonumber(q) do
        for j, s in ipairs({ "foo", "bar", "baz" }) do
          table.insert(lines, tostring((i - 1) * 3 + j) .. ": " .. s)
        end
      end
      return lines
    end]==],
    {
      __expect_lines = true,
      __postprocess_wait = true,
      query = 100,
    })
end

T["api"]["fzf_live"]["function"] = new_set({ parametrize = { { "sync" }, { "async" } } }, {
  function(type)
    if type == "sync" then
      helpers.FzfLua.fzf_live(child, [==[function(args)
          local q = args[1]
          return function(fzf_cb)
            if not tonumber(q) then
              fzf_cb("Invalid number: " .. tostring(q))
            else
              for i = 1, tonumber(q) do
                for j, s in ipairs({ "foo", "bar", "baz" }) do
                  fzf_cb(tostring((i - 1) * 3 + j) .. ": " .. s)
                end
              end
            end
            fzf_cb(nil)
          end
        end]==],
        {
          __expect_lines = true,
          __postprocess_wait = true,
          query = 100,
        })
    else
      helpers.FzfLua.fzf_live(child, [==[function(args)
          local q = args[1]
          return coroutine.wrap(function(fzf_cb)
            local co = coroutine.running()
            if not tonumber(q) then
              fzf_cb("Invalid number: " .. tostring(q), function() coroutine.resume(co) end)
              coroutine.yield()
            else
              for i = 1, tonumber(q) do
                for j, s in ipairs({ "foo", "bar", "baz" }) do
                  fzf_cb(tostring((i - 1) * 3 + j) .. ": " .. s, function() coroutine.resume(co) end)
                  coroutine.yield()
                end
              end
            end
            fzf_cb(nil)
          end)
        end]==],
        {
          __expect_lines = true,
          __postprocess_wait = true,
          query = 100,
        })
    end
  end,
})

T["api"]["fzf_live"]["rg"] = new_set()

T["api"]["fzf_live"]["rg"]["error"] = new_set({ parametrize = { { true }, { false }, { 1 } } }, {
  function(multiprocess)
    helpers.FzfLua.fzf_live(child, [["rg --column --line-number --smart-case"]], {
      __expect_lines = true,
      -- multiprocess==1 should fallback to native (no [DEBUG] line)
      -- as no fn_transform or fn_preprocess are present
      multiprocess = multiprocess,
      debug = 1,
      query = "["
      -- fzf_opts = { ["--wrap"] = true },
    })
  end
})

T["api"]["fzf_live"]["rg"]["no error"] = new_set(
  { parametrize = { { "[" }, { [[table of cont]] } } },
  {
    function(query)
      helpers.FzfLua.fzf_live(child,
        string.format(
          [["rg --column --line-number --smart-case --sort=path -g !tests/ -- <query> 2> %s"]],
          helpers.IS_WIN() and "nul" or "/dev/null"
        ),
        {
          __expect_lines = true,
          debug = 1,
          query = query,
          -- Windows fails due to the spaced query term with the native
          -- exec_empty_query shell condition, disable empty query to
          -- remove the empty query condition from the shell command
          exec_empty_query = true,
        })
    end
  }
)

return T
