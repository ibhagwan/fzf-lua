--- Test case conversion and execution internals.
---
--- Converts hierarchical test sets into flat arrays of cases, injects `*_once`
--- hooks, and builds the scheduled per-case execution step used by both the
--- sequential and worker execution paths.

local state = require("fzf-lua.test.harness.state")
local util = require("fzf-lua.test.harness.util")
local child_mod = require("fzf-lua.test.harness.child")

local M = {}

local function ensure_all_vals(arr_subset, arr_all)
  local vals_registry = {}
  for _, v in ipairs(arr_subset) do
    vals_registry[v] = true
  end

  for _, v in ipairs(arr_all) do
    if not vals_registry[v] then
      table.insert(arr_subset, v)
      vals_registry[v] = true
    end
  end

  return arr_subset
end

local function extend_hooks(hooks, layer, do_deepcopy)
  local res = hooks
  if do_deepcopy == nil or do_deepcopy then res = vim.deepcopy(hooks) end

  -- Closer (in terms of nesting) hooks should be closer to test callable
  if vim.is_callable(layer.pre) then table.insert(res.pre, layer.pre) end
  if vim.is_callable(layer.post) then table.insert(res.post, 1, layer.post) end

  return res
end

local function extend_template(template, layer)
  local res = vim.deepcopy(template)

  vim.list_extend(res.args, layer.args)
  table.insert(res.desc, layer.desc)
  res.hooks = extend_hooks(res.hooks, layer.hooks, false)
  res.data = vim.tbl_deep_extend("force", res.data, layer.data)
  res.n_retry = layer.n_retry or res.n_retry or 1

  return res
end

local function new_testcase(template, test)
  template.test = test
  return template
end

--- Convert test set to array of test cases.
---@param set table test set to convert
---@param template table|nil accumulated case template (args/desc/hooks/data)
---@param hooks_once table|nil aligned once-only hooks so far
---@return table[] test cases
---@return table[] aligned `hooks_once` entries
function M.set_to_testcases(set, template, hooks_once)
  template = template or { args = {}, desc = {}, hooks = { pre = {}, post = {} }, data = {}, n_retry = 1 }
  hooks_once = hooks_once or { pre = {}, post = {} }

  local metatbl = getmetatable(set)
  local opts, key_order = metatbl.opts, metatbl.key_order
  local hooks, parametrize, data, n_retry = opts.hooks or {}, opts.parametrize or { {} }, opts.data or {}, opts.n_retry

  -- Convert to steps only callable or test set nodes
  -- Ensure that all elements of `set` are being considered (might not be the
  -- case if `table.insert` was used, for example)
  key_order = ensure_all_vals(key_order, vim.tbl_keys(set))
  local node_keys = vim.tbl_filter(function(key)
    local node = set[key]
    return vim.is_callable(node) or util.is_instance(node, "testset")
  end, key_order)

  if #node_keys == 0 then return {}, {} end

  -- Ensure that newly added hooks are represented by new functions.
  -- This is needed to count them later only within current set. Example: use
  -- the same function in several `_once` hooks. In `M.inject_hooks_once` it
  -- will be injected only once overall whereas it should be injected only once
  -- within corresponding test set.
  hooks_once =
      extend_hooks(hooks_once, { pre = util.wrap_callable(hooks.pre_once), post = util.wrap_callable(hooks.post_once) })

  local testcase_arr, hooks_once_arr = {}, {}
  -- Process nodes in order they were added as `T[...] = x`
  for _, key in ipairs(node_keys) do
    local node = set[key]
    for _, args in ipairs(parametrize) do
      if type(args) ~= "table" then util.error("`parametrize` should have only tables. Got " .. vim.inspect(args)) end

      local cur_template = extend_template(template, {
        args = args,
        desc = type(key) == "string" and key:gsub("\n", "\\n") or key,
        hooks = { pre = hooks.pre_case, post = hooks.post_case },
        data = data,
        n_retry = n_retry,
      })

      if vim.is_callable(node) then
        table.insert(testcase_arr, new_testcase(cur_template, node))
        table.insert(hooks_once_arr, hooks_once)
      elseif util.is_instance(node, "testset") then
        local nest_testcase_arr, nest_hooks_once_arr = M.set_to_testcases(node, cur_template, hooks_once)
        vim.list_extend(testcase_arr, nest_testcase_arr)
        vim.list_extend(hooks_once_arr, nest_hooks_once_arr)
      end
    end
  end

  return testcase_arr, hooks_once_arr
end

function M.inject_hooks_once(cases, hooks_once)
  -- NOTE: this heavily relies on the equivalence of "have same object id" and
  -- "are same hooks"
  local already_injected, n = {}, #cases

  -- Inject 'pre' hooks moving forwards
  for i = 1, n do
    local case, hooks = cases[i], hooks_once[i].pre
    case.hooks.pre_source = vim.tbl_map(function() return "case" end, case.hooks.pre)
    local target_tbl_id = 1
    for j = 1, #hooks do
      local h = hooks[j]
      if not already_injected[h] then
        table.insert(case.hooks.pre, target_tbl_id, h)
        table.insert(case.hooks.pre_source, target_tbl_id, "once")
        target_tbl_id, already_injected[h] = target_tbl_id + 1, true
      end
    end
  end

  -- Inject 'post' hooks moving backwards
  for i = n, 1, -1 do
    local case, hooks = cases[i], hooks_once[i].post
    case.hooks.post_source = vim.tbl_map(function() return "case" end, case.hooks.post)
    local target_tbl_id = #case.hooks.post + 1
    for j = #hooks, 1, -1 do
      local h = hooks[j]
      if not already_injected[h] then
        table.insert(case.hooks.post, target_tbl_id, h)
        table.insert(case.hooks.post_source, target_tbl_id, "once")
        already_injected[h] = true
      end
    end
  end

  return cases
end

--- Build the scheduled step that executes `case`, calling
--- `opts.reporter.update` after every state change.
---@param case table
---@param case_num integer
---@param opts table execute options (with `reporter`)
---@return function scheduled step
function M.make_case(case, case_num, opts)
  local update_state = function(state_str)
    case.exec.state = state_str
    util.exec_callable(opts.reporter.update, case_num)
  end

  local is_case_executed = false
  local on_err = function(e)
    if state.cache.skip_message ~= nil then
      -- Add skip message to notes (not fails) only during main case execution
      if is_case_executed then
        table.insert(case.exec.notes, state.cache.skip_message)
        state.cache.skip_message = nil
      end
      return true
    end

    -- Append traceback to error message and indent lines for pretty print
    local error_lines = { tostring(e), "Traceback:", unpack(util.traceback()) }
    local error_msg = table.concat(error_lines, "\n"):gsub("\n", "\n  ")
    table.insert(case.exec.fails, error_msg)

    return false
  end

  local exec_step = function(f, state_str)
    update_state(state_str)

    state.cache.finally, state.cache.n_screenshots = {}, 0
    local ok_f, ok_err = xpcall(f, on_err)

    for _, fin in ipairs(state.cache.finally) do
      util.exec_callable(fin)
    end

    return ok_f or ok_err
  end

  local exec_hooks = function(name, source)
    local source_arr = case.hooks[name .. "_source"]
    local state_prefix = "Executing '" .. name .. "' hook #"
    for i, h in ipairs(case.hooks[name]) do
      if source_arr[i] == source then exec_step(h, state_prefix .. i) end
    end
  end

  return function()
    if state.cache.should_stop_execution then return end

    case.exec = { fails = {}, notes = {} }
    state.current.case = case

    exec_hooks("pre", "once")
    local exec_data = case.exec

    local ok_case
    for _ = 1, case.n_retry do
      -- Ensure that fails and notes are not accumulated during retries
      case.exec = vim.deepcopy(exec_data)

      -- Ensure that `skip()` affects only `pre_case` hooks and case
      state.cache.skip_message = nil

      -- Executing `*_case` hooks on every retry should ensure same case setup
      -- (like cleanly restarted child process)
      exec_hooks("pre", "case")

      local case_f = function() case.test(unpack(case.args)) end
      if #case.exec.fails > 0 then
        case_f = function() table.insert(case.exec.notes, "Skip case due to error(s) in hooks.") end
      end
      if state.cache.skip_message ~= nil then case_f = function() state.skip(state.cache.skip_message) end end

      is_case_executed = true
      ok_case = exec_step(case_f, "Executing test")
      is_case_executed = false

      exec_hooks("post", "case")

      if ok_case then break end
    end

    exec_hooks("post", "once")

    update_state(util.case_final_state(case))

    if not ok_case and opts.stop_on_error then child_mod.stop_all() end
  end
end

return M
