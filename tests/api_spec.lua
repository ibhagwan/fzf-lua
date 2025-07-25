---@diagnostic disable: unused-local, unused-function
local MiniTest = require("mini.test")
local helpers = require("fzf-lua.test.helpers")
local child = helpers.new_child_neovim()
local expect, eq = helpers.expect, helpers.expect.equality
local new_set = MiniTest.new_set

local T = helpers.new_set_with_child(child)

T["api"] = new_set({ n_retry = not helpers.IS_LINUX() and 5 or nil })

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
      [['rg --files -g !.git -g !tests/** --sort=path']],
      {
        __expect_lines = true,
        -- __postprocess_wait = multiprocess ~= 1,
        debug = 1,
        multiprocess = multiprocess,
      })
  end
})

T["api"]["fzf_exec"]["fn_transform"] = new_set({ parametrize = { { true }, { false } } })

T["api"]["fzf_exec"]["fn_transform"]["filter"] = new_set(
  { parametrize = { { 0 }, { 13 }, { 24 } } }, {
    function(multiprocess, filter)
      local AND = helpers.IS_WIN() and "&" or "&&"
      helpers.FzfLua.fzf_exec(child,
        string.format([["echo one%secho two%secho three%secho four"]], AND, AND, AND),
        {
          -- __postprocess_wait = multiprocess ~= 1,
          __expect_lines = true,
          multiprocess = multiprocess,
          fn_transform = filter == 13 and function(item)
                if vim.tbl_contains({ "one", "three" }, item) then return end
                return string.format("TRANSFORMED: %s, base64: %s", item, vim.base64.encode(item))
              end
              or filter == 24 and function(item)
                if vim.tbl_contains({ "two", "four" }, item) then return end
                return string.format("TRANSFORMED: %s, base64: %s", item, vim.base64.encode(item))
              end
              or function(item)
                return string.format("TRANSFORMED: %s, base64: %s", item, vim.base64.encode(item))
              end
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
          multiprocess = false,
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

T["api"]["events"] = new_set(
  { parametrize = { { "fzf_exec" }, { "fzf_live" } } },
  {
    function(api)
      local prompt = "EventsPrompt>"
      helpers.FzfLua[api](child,
        api == "fzf_exec"
        and [[(function() return { "foo", "bar", "baz" } end)()]]
        or [[function() return { "foo", "bar", "baz" } end ]],
        {
          __expect_lines = true,
          prompt = prompt,
          exec_empty_query = true,
          actions = {
            start = {
              fn = function(s) _G._fzf_prompt = s[1] end,
              field_index = helpers.IS_WIN()
                  and "{fzf:prompt}"
                  -- TODO: env vars do not work on Windows in the CI
                  -- they also mess up all other ui_spec tests as lists
                  -- will have the env var output propagated, how??!
                  -- and "%FZF_PROMPT% %FZF_TOTAL_COUNT%"
                  or "$FZF_PROMPT $FZF_TOTAL_COUNT",
              exec_silent = true,
            },
            load = not helpers.IS_WIN() and {
              fn = function(s) _G._fzf_total_count = tonumber(s[2]) end,
              field_index = helpers.IS_WIN()
                  and "%FZF_PROMPT% %FZF_TOTAL_COUNT%"
                  or "$FZF_PROMPT $FZF_TOTAL_COUNT",
              exec_silent = true,
            } or nil,
          },
          __after_open = function()
            child.wait_until(function()
              return child.lua_get([[_G._fzf_prompt]]) == prompt
            end)
            -- See above note in "start" why we skip this on Win
            if not helpers.IS_WIN() then
              child.wait_until(function()
                return child.lua_get([[_G._fzf_total_count]]) == 3
              end)
            end
          end,
        })
    end
  }
)

return T
