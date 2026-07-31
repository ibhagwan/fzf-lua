--- Test case conversion and execution internals.
---
--- Converts hierarchical test sets into flat arrays of cases, injects `*_once`
--- hooks, and builds the scheduled per-case execution step used by both the
--- sequential and worker execution paths.

local H = require("fzf-lua.test.mini.util")

--- Convert test set to array of test cases.
---@param set table test set to convert
---@param template table|nil accumulated case template (args/desc/hooks/data)
---@param hooks_once table|nil aligned once-only hooks so far
---@return table[] test cases
---@return table[] aligned `hooks_once` entries
H.set_to_testcases = function(set, template, hooks_once)
  template = template or { args = {}, desc = {}, hooks = { pre = {}, post = {} }, data = {}, n_retry = 1 }
  hooks_once = hooks_once or { pre = {}, post = {} }

  local metatbl = getmetatable(set)
  local opts, key_order = metatbl.opts, metatbl.key_order
  local hooks, parametrize, data, n_retry = opts.hooks or {}, opts.parametrize or { {} }, opts.data or {}, opts.n_retry

  -- Convert to steps only callable or test set nodes
  -- Ensure that all elements of `set` are being considered (might not be the
  -- case if `table.insert` was used, for example)
  key_order = H.ensure_all_vals(key_order, vim.tbl_keys(set))
  local node_keys = vim.tbl_filter(function(key)
    local node = set[key]
    return vim.is_callable(node) or H.is_instance(node, "testset")
  end, key_order)

  if #node_keys == 0 then return {}, {} end

  -- Ensure that newly added hooks are represented by new functions.
  -- This is needed to count them later only within current set. Example: use
  -- the same function in several `_once` hooks. In `H.inject_hooks_once` it
  -- will be injected only once overall whereas it should be injected only once
  -- within corresponding test set.
  hooks_once =
      H.extend_hooks(hooks_once, { pre = H.wrap_callable(hooks.pre_once), post = H.wrap_callable(hooks.post_once) })

  local testcase_arr, hooks_once_arr = {}, {}
  -- Process nodes in order they were added as `T[...] = x`
  for _, key in ipairs(node_keys) do
    local node = set[key]
    for _, args in ipairs(parametrize) do
      if type(args) ~= "table" then H.error("`parametrize` should have only tables. Got " .. vim.inspect(args)) end

      local cur_template = H.extend_template(template, {
        args = args,
        desc = type(key) == "string" and key:gsub("\n", "\\n") or key,
        hooks = { pre = hooks.pre_case, post = hooks.post_case },
        data = data,
        n_retry = n_retry,
      })

      if vim.is_callable(node) then
        table.insert(testcase_arr, H.new_testcase(cur_template, node))
        table.insert(hooks_once_arr, hooks_once)
      elseif H.is_instance(node, "testset") then
        local nest_testcase_arr, nest_hooks_once_arr = H.set_to_testcases(node, cur_template, hooks_once)
        vim.list_extend(testcase_arr, nest_testcase_arr)
        vim.list_extend(hooks_once_arr, nest_hooks_once_arr)
      end
    end
  end

  return testcase_arr, hooks_once_arr
end

H.ensure_all_vals = function(arr_subset, arr_all)
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

H.inject_hooks_once = function(cases, hooks_once)
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

H.new_testcase = function(template, test)
  template.test = test
  return template
end

H.extend_template = function(template, layer)
  local res = vim.deepcopy(template)

  vim.list_extend(res.args, layer.args)
  table.insert(res.desc, layer.desc)
  res.hooks = H.extend_hooks(res.hooks, layer.hooks, false)
  res.data = vim.tbl_deep_extend("force", res.data, layer.data)
  res.n_retry = layer.n_retry or res.n_retry or 1

  return res
end

H.extend_hooks = function(hooks, layer, do_deepcopy)
  local res = hooks
  if do_deepcopy == nil or do_deepcopy then res = vim.deepcopy(hooks) end

  -- Closer (in terms of nesting) hooks should be closer to test callable
  if vim.is_callable(layer.pre) then table.insert(res.pre, layer.pre) end
  if vim.is_callable(layer.post) then table.insert(res.post, 1, layer.post) end

  return res
end

--- Build a filename-safe string id for a test case.
---@param case table
---@return string
H.case_to_stringid = function(case)
  local desc = table.concat(case.desc, " | ")
  if #case.args == 0 then return desc end
  local args = vim.inspect(case.args, { newline = "", indent = "" })
  return ("%s + args %s"):format(desc, args)
end

H.case_final_state = function(case)
  local pass_fail = #case.exec.fails == 0 and "Pass" or "Fail"
  local with_notes = #case.exec.notes == 0 and "" or " with notes"
  return string.format("%s%s", pass_fail, with_notes)
end

-- Execution ---------------------------------------------------------------

--- Build the scheduled step that executes `case`, calling
--- `opts.reporter.update` after every state change.
---@param case table
---@param case_num integer
---@param opts table execute options (with `reporter`)
---@return function scheduled step
H.make_case = function(case, case_num, opts)
  local update_state = function(state)
    case.exec.state = state
    H.exec_callable(opts.reporter.update, case_num)
  end

  local is_case_executed = false
  local on_err = function(e)
    if H.cache.skip_message ~= nil then
      -- Add skip message to notes (not fails) only during main case execution
      if is_case_executed then
        table.insert(case.exec.notes, H.cache.skip_message)
        H.cache.skip_message = nil
      end
      return true
    end

    -- Append traceback to error message and indent lines for pretty print
    local error_lines = { tostring(e), "Traceback:", unpack(H.traceback()) }
    local error_msg = table.concat(error_lines, "\n"):gsub("\n", "\n  ")
    table.insert(case.exec.fails, error_msg)

    return false
  end

  local exec_step = function(f, state)
    update_state(state)

    H.cache.finally, H.cache.n_screenshots = {}, 0
    local ok_f, ok_err = xpcall(f, on_err)

    for _, fin in ipairs(H.cache.finally) do
      H.exec_callable(fin)
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
    if H.cache.should_stop_execution then return end

    case.exec = { fails = {}, notes = {} }
    H.current.case = case

    exec_hooks("pre", "once")
    local exec_data = case.exec

    local ok_case
    for _ = 1, case.n_retry do
      -- Ensure that fails and notes are not accumulated during retries
      case.exec = vim.deepcopy(exec_data)

      -- Ensure that `skip()` affects only `pre_case` hooks and case
      H.cache.skip_message = nil

      -- Executing `*_case` hooks on every retry should ensure same case setup
      -- (like cleanly restarted child process)
      exec_hooks("pre", "case")

      local case_f = function() case.test(unpack(case.args)) end
      if #case.exec.fails > 0 then
        case_f = function() table.insert(case.exec.notes, "Skip case due to error(s) in hooks.") end
      end
      if H.cache.skip_message ~= nil then case_f = function() H.skip(H.cache.skip_message) end end

      is_case_executed = true
      ok_case = exec_step(case_f, "Executing test")
      is_case_executed = false

      exec_hooks("post", "case")

      if ok_case then break end
    end

    exec_hooks("post", "once")

    update_state(H.case_final_state(case))

    if not ok_case and opts.stop_on_error then MiniTest.stop() end
  end
end

-- Overview reporter ----------------------------------------------------------
-- Shared by the stdout reporter and the parallel summary.

H.overview_reporter = {}

H.overview_reporter.compute_groups = function(cases, group_depth)
  local default_symbol = H.reporter_symbols[nil]
  return vim.tbl_map(function(c)
    local desc_trunc = vim.list_slice(c.desc, 1, group_depth)
    local name = table.concat(desc_trunc, " | ")
    return { name = name, symbol = default_symbol }
  end, cases)
end

H.overview_reporter.start_lines = function(cases, groups)
  local unique_names = {}
  for _, g in ipairs(groups) do
    unique_names[g.name] = true
  end
  local n_groups = #vim.tbl_keys(unique_names)

  return {
    string.format("%s %s", H.add_style("Total number of cases:", "emphasis"), #cases),
    string.format("%s %s", H.add_style("Total number of groups:", "emphasis"), n_groups),
    "",
  }
end

H.overview_reporter.finish_lines = function(cases)
  -- Gather fails and notes (colored based on case fail/pass)
  local fails, notes = {}, {}
  local n_fails, n_notes = 0, 0
  for _, c in ipairs(cases) do
    local stringid = H.case_to_stringid(c)
    local exec = c.exec == nil and { fails = {}, notes = {} } or c.exec

    if #exec.fails > 0 then
      table.insert(fails, "")
      local fail_prefix = string.format("%s in %s: ", H.add_style("FAIL", "fail"), stringid)
      vim.list_extend(fails, H.add_prefix(exec.fails, fail_prefix))
      n_fails = n_fails + #exec.fails
    end

    if #exec.notes > 0 then
      table.insert(notes, "")
      local note_color = #exec.fails > 0 and "fail" or "pass"
      local note_prefix = string.format("%s in %s: ", H.add_style("NOTE", note_color), stringid)
      vim.list_extend(notes, H.add_prefix(exec.notes, note_prefix))
      n_notes = n_notes + #exec.notes
    end
  end

  -- Show all fails first, then all notes
  local header = string.format("Fails (%s) and Notes (%s)", n_fails, n_notes)
  local res = { H.add_style(header, "emphasis") }
  vim.list_extend(res, fails)
  vim.list_extend(res, notes)

  return vim.split(table.concat(res, "\n"), "\n")
end

return H
