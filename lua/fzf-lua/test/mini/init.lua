--- fzf-lua test framework core.
---
--- Refactored from vendored `mini.test` (upstream single file) into logical
--- modules under `mini/`. Parallel execution is a first-class feature: with
--- `config.jobs > 1`, `run()` spawns worker nvim processes and streams their
--- results live; worker mode (`FZF_LUA_TEST_WORKER=1`) executes only the spec
--- subset listed in `FZF_LUA_TEST_FILES` and emits machine-readable events.
---
--- Public surface is exported via `fzf-lua.test.harness`; nothing else should
--- require this module directly.

local H = require("fzf-lua.test.mini.util")
require("fzf-lua.test.mini.case")
local expect = require("fzf-lua.test.mini.expect")
local child = require("fzf-lua.test.mini.child")
local reporter = require("fzf-lua.test.mini.reporter")
local run_parallel = require("fzf-lua.test.mini.parallel")

local MiniTest = {}

-- Defaults ~
MiniTest.config = {
  -- Options for collection of test cases. See `MiniTest.collect()`.
  collect = {
    -- Temporarily emulate functions from 'busted' testing framework
    -- (`describe`, `it`, `before_each`, `after_each`, and more)
    emulate_busted = true,

    -- Function returning array of file paths to be collected.
    -- Default: all Lua spec files in 'tests' directory.
    find_files = function()
      return vim.fn.globpath("tests", "**/*_spec.lua", true, true)
    end,

    -- Predicate function indicating if test case should be executed
    filter_cases = function(case) return true end,
  },

  -- Options for execution of test cases. See `MiniTest.execute()`.
  execute = {
    -- Table with callable fields `start()`, `update()`, and `finish()`.
    -- Default: stdout reporter.
    reporter = nil,

    -- Whether to stop execution after first error
    stop_on_error = false,
  },

  -- Number of parallel worker processes. 1 (default) runs cases in the
  -- current process; `>1` spawns that many worker nvim processes.
  jobs = 1,
}

-- Module data ~
MiniTest.current = H.current

-- Create test set ~
MiniTest.new_set = function(opts, tbl)
  opts = opts or {}
  tbl = tbl or {}

  -- Keep track of new elements order. This allows to iterate through elements
  -- in order they were added.
  local metatbl = { class = "testset", key_order = vim.tbl_keys(tbl), opts = opts }
  metatbl.__newindex = function(t, key, value)
    table.insert(metatbl.key_order, key)
    rawset(t, key, value)
  end

  return setmetatable(tbl, metatbl)
end

-- Run tests ~
---@param opts table|nil Options with structure similar to |MiniTest.config|.
---   Absent values are inferred from there.
---@return integer exit code (0 = success, 1 = failure)
MiniTest.run = function(opts)
  opts = H.get_config(opts)

  if vim.env.FZF_LUA_TEST_WORKER then
    -- Worker mode: execute own spec subset and emit event lines for the
    -- parallel orchestrator (`mini/parallel.lua`).
    return H.run_worker(opts)
  end

  local jobs = tonumber(opts.jobs) or 1
  if jobs > 1 then
    -- Parallel mode: run cases inside `jobs` worker nvim processes. Pass the
    -- collect function so the orchestrator can bucket cases by global index
    -- without a cyclic require (parallel.lua loads before this module is done).
    return run_parallel(MiniTest.collect, opts.collect, jobs)
  end

  local cases = MiniTest.collect(opts.collect)
  MiniTest.execute(cases, opts.execute)
  H.wait_for_execution()

  return H.has_fails(cases) and 1 or 0
end

-- Collect test cases ~
---@param opts table|nil Options controlling case collection. Possible fields:
---   - <emulate_busted> - whether to emulate `lunarmodules/busted` interface.
---     It emulates these global functions: `describe`, `it`, `setup`, `teardown`,
---     `before_each`, `after_each`.
---   - <find_files> - function which when called without arguments returns
---     array with file paths. Each file should be a Lua file returning single
---     test set or `nil`.
---   - <filter_cases> - function which when called with single test case
---     returns `false` if this case should be filtered out; `true` otherwise.
---@return table Array of test cases ready to be used by |MiniTest.execute()|.
MiniTest.collect = function(opts)
  opts = vim.tbl_deep_extend("force", H.get_config().collect, opts or {})

  -- Make single test set
  local set = MiniTest.new_set()

  for _, file in ipairs(opts.find_files()) do
    -- Possibly emulate 'busted' with current file. This allows to wrap all
    -- implicit cases from that file into single set with file's name.
    if opts.emulate_busted then
      set[file] = MiniTest.new_set()
      H.busted_emulate(set[file])
    end

    -- Execute file
    local ok, t = pcall(dofile, file)

    -- Catch errors
    if not ok then
      local msg = string.format("Sourcing %s resulted into following error: %s", vim.inspect(file), t)
      H.error(msg)
    end
    local is_output_correct = (opts.emulate_busted and vim.tbl_count(set[file]) > 0) or H.is_instance(t, "testset")
    if not is_output_correct then
      local msg = string.format(
        [[%s does not define a test set. Did you return `MiniTest.new_set()` or created 'busted' tests?]],
        vim.inspect(file)
      )
      H.error(msg)
    end

    -- If output is test set, always use it (even if 'busted' tests were added)
    if H.is_instance(t, "testset") then set[file] = t end
  end

  H.busted_deemulate()

  -- Convert to test cases. This also creates separate aligned array of hooks
  -- which should be executed once regarding test case. This is needed to
  -- correctly inject those hooks after filtering is done.
  local raw_cases, raw_hooks_once = H.set_to_testcases(set)

  -- Filter cases (at this stage don't have injected `hooks_once`)
  local cases, hooks_once = {}, {}
  for i, c in ipairs(raw_cases) do
    if opts.filter_cases(c) then
      table.insert(cases, c)
      table.insert(hooks_once, raw_hooks_once[i])
    end
  end

  -- Inject `hooks_once` into appropriate cases
  H.inject_hooks_once(cases, hooks_once)

  return cases
end

-- Execute array of test cases ~
---@param cases table Array of test cases (see |MiniTest-test-case|).
---@param opts table|nil Options controlling case execution. Possible fields:
---   - <reporter> - table with possible callable fields `start`, `update`,
---     `finish`. Default: |MiniTest.gen_reporter.stdout()|.
---   - <stop_on_error> - whether to stop execution (see |MiniTest.stop()|)
---     after first error. Default: `false`.
MiniTest.execute = function(cases, opts)
  H.check_type("cases", cases, "table")

  MiniTest.current.all_cases = cases

  -- Verify correct arguments
  if #cases == 0 then
    H.message("No cases to execute.")
    return
  end

  opts = vim.tbl_deep_extend("force", H.get_config().execute, opts or {})
  local reporter = opts.reporter or H.gen_reporter.stdout()
  if type(reporter) ~= "table" then
    H.message("`opts.reporter` should be table or `nil`.")
    return
  end
  opts.reporter = reporter

  -- Plan execution in order
  H.cache = { is_executing = true }

  local queue = {}
  table.insert(queue, function() H.exec_callable(reporter.start, cases) end)
  for case_num, cur_case in ipairs(cases) do
    table.insert(queue, H.make_case(cur_case, case_num, opts))
  end
  table.insert(queue, function() H.exec_callable(reporter.finish) end)
  -- - Use separate call to ensure that `reporter.finish` error won't interfere
  table.insert(queue, function() H.cache.is_executing = false end)

  -- Execute queue ensuring order
  -- NOTE: Directly `vim.schedule` each step without an explicit queue handling
  -- is possible, but it might interfere with async-adjacent yet synchronous
  -- functions (as `vim.wait()`) callsed inside cases outside of child process.
  local exec_queue_step, n_queue = function(_) end, #queue
  exec_queue_step = function(n)
    queue[n]()
    if n < n_queue then vim.schedule(function() exec_queue_step(n + 1) end) end
  end
  vim.schedule(function() exec_queue_step(1) end)
end

-- Stop test execution ~
---@param opts table|nil Options with fields:
---   - <close_all_child_neovim> - whether to close all child neovim processes
---     created with |MiniTest.new_child_neovim()|. Default: `true`.
MiniTest.stop = function(opts)
  opts = vim.tbl_deep_extend("force", { close_all_child_neovim = true }, opts or {})

  -- Register intention to stop execution
  H.cache.should_stop_execution = true

  -- Possibly stop all child Neovim processes
  if not opts.close_all_child_neovim then return end

  for _, child in ipairs(H.child_neovim_registry) do
    pcall(child.stop)
  end
  H.child_neovim_registry = {}
end

--- Check if tests are being executed
---@return boolean
MiniTest.is_executing = function() return H.cache.is_executing == true end

-- Internal helpers (referenced from `mini/case.lua` and worker mode) ---------

--- Worker mode: collect own spec subset (from `FZF_LUA_TEST_FILES`), execute
--- with the event reporter, and wait for completion. Exiting happens in the
--- entry script via the returned code.
---@param opts table resolved run options
---@return integer exit code
H.run_worker = function(opts)
  local cases = MiniTest.collect(opts.collect)
  MiniTest.execute(cases, { reporter = H.worker_reporter() })
  H.wait_for_execution()

  return H.has_fails(cases) and 1 or 0
end

--- Block until the scheduled execution queue has fully drained. Safe because
--- `vim.wait()` pumps the event loop, letting scheduled steps run.
H.wait_for_execution = function()
  while H.cache.is_executing do vim.wait(20) end
end

H.get_config = function(opts)
  return vim.tbl_deep_extend("force", MiniTest.config, opts or {})
end

-- Busted emulation ~
-- The linter flags `_G.describe`/`_G.it`/... as duplicated with the nil
-- assignments in `H.busted_deemulate`; both sets are intentional.
---@diagnostic disable: duplicate-set-field
H.busted_emulate = function(set)
  local cur_set = set

  _G.describe = function(name, f)
    local cur_set_parent = cur_set
    cur_set_parent[name] = MiniTest.new_set()
    cur_set = cur_set_parent[name]
    f()
    cur_set = cur_set_parent
  end

  _G.it = function(name, f) cur_set[name] = f end

  local setting_hook = function(hook_name)
    return function(hook)
      local metatbl = getmetatable(cur_set)
      metatbl.opts.hooks = metatbl.opts.hooks or {}
      metatbl.opts.hooks[hook_name] = hook
    end
  end

  _G.setup = setting_hook("pre_once")
  _G.before_each = setting_hook("pre_case")
  _G.after_each = setting_hook("post_case")
  _G.teardown = setting_hook("post_once")
end

H.busted_deemulate = function()
  local fun_names = { "describe", "it", "setup", "before_each", "after_each", "teardown" }
  for _, f_name in ipairs(fun_names) do
    _G[f_name] = nil
  end
end

-- Assemble public surface ~
MiniTest.skip = H.skip
MiniTest.add_note = H.add_note
MiniTest.finally = H.finally
MiniTest.expect = H.expect
MiniTest.new_expectation = H.new_expectation
MiniTest.new_child_neovim = H.new_child_neovim
MiniTest.gen_reporter = H.gen_reporter

-- Expose the shared helper table for the harness bridge (`fzf-lua.test.harness`)
MiniTest._internals = H

return MiniTest
