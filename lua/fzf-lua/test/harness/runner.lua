--- Collection, execution, and run orchestration for the fzf-lua test
--- framework.
---
--- Public entry is `harness.run()`; parallel mode delegates to
--- `harness/parallel.lua`, worker mode runs the subset in `FZF_LUA_TEST_FILES`
--- and emits machine-readable events, and the default path executes cases in
--- the current process with the stdout reporter.

local state = require("fzf-lua.test.harness.state")
local util = require("fzf-lua.test.harness.util")
local busted = require("fzf-lua.test.harness.busted")
local case_mod = require("fzf-lua.test.harness.case")
local reporter_mod = require("fzf-lua.test.harness.reporter")
local child_mod = require("fzf-lua.test.harness.child")
local run_parallel = require("fzf-lua.test.harness.parallel")

local M = {}

-- Defaults ~
M.config = {
  -- Options for collection of test cases. See `M.collect()`.
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

  -- Options for execution of test cases. See `M.execute()`.
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

M.get_config = function(opts)
  return vim.tbl_deep_extend("force", M.config, opts or {})
end

-- Run tests ~
---@param opts table|nil Options with structure similar to |M.config|.
---   Absent values are inferred from there.
---@return integer exit code (0 = success, 1 = failure)
M.run = function(opts)
  opts = M.get_config(opts)

  if vim.env.FZF_LUA_TEST_WORKER then
    -- Worker mode: execute own spec subset and emit event lines for the
    -- parallel orchestrator (`harness/parallel.lua`).
    return M.run_worker(opts)
  end

  local jobs = tonumber(opts.jobs) or 1
  if jobs > 1 then
    -- Parallel mode: run cases inside `jobs` worker nvim processes. Pass the
    -- collect function so the orchestrator can bucket cases by global index
    -- without a cyclic require (parallel.lua loads before this module is done).
    return run_parallel(M.collect, opts.collect, jobs)
  end

  local cases = M.collect(opts.collect)
  M.execute(cases, opts.execute)
  M.wait_for_execution()

  return util.has_fails(cases) and 1 or 0
end

-- Collect test cases ~
---@param opts table|nil Options controlling case collection. Possible fields:
---   - <emulate_busted> - whether to emulate `lunarmodules/busted` interface.
---   - <find_files> - function which when called without arguments returns
---     array with file paths. Each file should be a Lua file returning single
---     test set or `nil`.
---   - <filter_cases> - function which when called with single test case
---     returns `false` if this case should be filtered out; `true` otherwise.
---@return table Array of test cases ready to be used by |M.execute()|.
M.collect = function(opts)
  opts = vim.tbl_deep_extend("force", M.get_config().collect, opts or {})

  -- Make single test set
  local set = util.new_set()

  for _, file in ipairs(opts.find_files()) do
    -- Possibly emulate 'busted' with current file. This allows to wrap all
    -- implicit cases from that file into single set with file's name.
    if opts.emulate_busted then
      set[file] = util.new_set()
      busted.emulate(set[file])
    end

    -- Execute file
    local ok, t = pcall(dofile, file)

    -- Catch errors
    if not ok then
      local msg = string.format("Sourcing %s resulted into following error: %s", vim.inspect(file), t)
      util.error(msg)
    end
    local is_output_correct = (opts.emulate_busted and vim.tbl_count(set[file]) > 0) or util.is_instance(t, "testset")
    if not is_output_correct then
      local msg = string.format(
        [[%s does not define a test set. Did you return `MiniTest.new_set()` or created 'busted' tests?]],
        vim.inspect(file)
      )
      util.error(msg)
    end

    -- If output is test set, always use it (even if 'busted' tests were added)
    if util.is_instance(t, "testset") then set[file] = t end
  end

  busted.deemulate()

  -- Convert to test cases. This also creates separate aligned array of hooks
  -- which should be executed once regarding test case. This is needed to
  -- correctly inject those hooks after filtering is done.
  local raw_cases, raw_hooks_once = case_mod.set_to_testcases(set)

  -- Filter cases (at this stage don't have injected `hooks_once`)
  local cases, hooks_once = {}, {}
  for i, c in ipairs(raw_cases) do
    if opts.filter_cases(c) then
      table.insert(cases, c)
      table.insert(hooks_once, raw_hooks_once[i])
    end
  end

  -- Inject `hooks_once` into appropriate cases
  case_mod.inject_hooks_once(cases, hooks_once)

  return cases
end

-- Execute array of test cases ~
---@param cases table Array of test cases.
---@param opts table|nil Options controlling case execution. Possible fields:
---   - <reporter> - table with possible callable fields `start`, `update`,
---     `finish`. Default: |M.gen_reporter.stdout()|.
---   - <stop_on_error> - whether to stop execution (see |M.stop()|)
---     after first error. Default: `false`.
M.execute = function(cases, opts)
  util.check_type("cases", cases, "table")

  state.current.all_cases = cases

  -- Verify correct arguments
  if #cases == 0 then
    util.message("No cases to execute.")
    return
  end

  opts = vim.tbl_deep_extend("force", M.get_config().execute, opts or {})
  local reporter = opts.reporter or reporter_mod.gen_reporter.stdout()
  if type(reporter) ~= "table" then
    util.message("`opts.reporter` should be table or `nil`.")
    return
  end
  opts.reporter = reporter

  -- Plan execution in order
  state.cache = { is_executing = true }

  local queue = {}
  table.insert(queue, function() util.exec_callable(reporter.start, cases) end)
  for case_num, cur_case in ipairs(cases) do
    table.insert(queue, case_mod.make_case(cur_case, case_num, opts))
  end
  table.insert(queue, function() util.exec_callable(reporter.finish) end)
  -- - Use separate call to ensure that `reporter.finish` error won't interfere
  table.insert(queue, function() state.cache.is_executing = false end)

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
---     created with |M.new_child_neovim()|. Default: `true`.
M.stop = function(opts)
  opts = vim.tbl_deep_extend("force", { close_all_child_neovim = true }, opts or {})

  -- Register intention to stop execution
  state.cache.should_stop_execution = true

  -- Possibly stop all child Neovim processes
  if not opts.close_all_child_neovim then return end

  child_mod.stop_all()
end

--- Block until the scheduled execution queue has fully drained. Safe because
--- `vim.wait()` pumps the event loop, letting scheduled steps run.
M.wait_for_execution = function()
  while state.cache.is_executing do vim.wait(20) end
end

--- Worker mode: collect own spec subset (from `FZF_LUA_TEST_FILES`), execute
--- with the event reporter, and wait for completion. Exiting happens in the
--- entry script via the returned code.
---@param opts table resolved run options
---@return integer exit code
M.run_worker = function(opts)
  local cases = M.collect(opts.collect)
  M.execute(cases, { reporter = reporter_mod.worker_reporter() })
  M.wait_for_execution()

  return util.has_fails(cases) and 1 or 0
end

return M
