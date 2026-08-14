--- Output reporters: the default stdout reporter (sequential runs) and the
--- worker event reporter (parallel runs).

local state = require("fzf-lua.test.harness.state")
local util = require("fzf-lua.test.harness.util")

-- Overview reporter ----------------------------------------------------------
-- Shared by the stdout reporter and the parallel summary.

local overview_reporter = {}

overview_reporter.compute_groups = function(cases, group_depth)
  local default_symbol = util.reporter_symbols[nil]
  return vim.tbl_map(function(c)
    local desc_trunc = vim.list_slice(c.desc, 1, group_depth)
    local name = table.concat(desc_trunc, " | ")
    return { name = name, symbol = default_symbol }
  end, cases)
end

overview_reporter.start_lines = function(cases, groups)
  local unique_names = {}
  for _, g in ipairs(groups) do
    unique_names[g.name] = true
  end
  local n_groups = #vim.tbl_keys(unique_names)

  return {
    string.format("%s %s", util.add_style("Total number of cases:", "emphasis"), #cases),
    string.format("%s %s", util.add_style("Total number of groups:", "emphasis"), n_groups),
    "",
  }
end

overview_reporter.finish_lines = function(cases)
  -- Gather fails and notes (colored based on case fail/pass)
  local fails, notes = {}, {}
  local n_fails, n_notes = 0, 0
  for _, c in ipairs(cases) do
    local stringid = util.case_to_stringid(c)
    local exec = c.exec == nil and { fails = {}, notes = {} } or c.exec

    if #exec.fails > 0 then
      table.insert(fails, "")
      local fail_prefix = string.format("%s in %s: ", util.add_style("FAIL", "fail"), stringid)
      vim.list_extend(fails, util.add_prefix(exec.fails, fail_prefix))
      n_fails = n_fails + #exec.fails
    end

    if #exec.notes > 0 then
      table.insert(notes, "")
      local note_color = #exec.fails > 0 and "fail" or "pass"
      local note_prefix = string.format("%s in %s: ", util.add_style("NOTE", note_color), stringid)
      vim.list_extend(notes, util.add_prefix(exec.notes, note_prefix))
      n_notes = n_notes + #exec.notes
    end
  end

  -- Show all fails first, then all notes
  local header = string.format("Fails (%s) and Notes (%s)", n_fails, n_notes)
  local res = { util.add_style(header, "emphasis") }
  vim.list_extend(res, fails)
  vim.list_extend(res, notes)

  return vim.split(table.concat(res, "\n"), "\n")
end

local M = {}

M.gen_reporter = {}

--- Generate stdout reporter (headless default). Writes to `stdout` with ANSI
--- coloring: one symbol per case, then a summary on finish. Exiting is left
--- to the entry script (`scripts/make_cli.lua`).
---@param opts table|nil Table with options. Used fields:
---   - <group_depth> - number of first elements of case description (can be zero)
---     used for grouping. Higher values mean higher granularity of output.
---     Default: 1.
---@return table reporter with `start`/`update`/`finish`
M.gen_reporter.stdout = function(opts)
  opts = vim.tbl_deep_extend("force", { group_depth = 1 }, opts or {})

  local write = function(text)
    text = type(text) == "table" and table.concat(text, "\n") or text
    io.stdout:write(text)
    io.flush()
  end

  local all_cases, all_groups, latest_group_name
  local default_symbol = util.reporter_symbols[nil]

  local res = {}

  res.start = function(cases)
    -- Set up data
    all_cases = cases
    all_groups = overview_reporter.compute_groups(cases, opts.group_depth)

    -- Write lines
    write(overview_reporter.start_lines(all_cases, all_groups))
  end

  res.update = function(case_num)
    local cur_case = all_cases[case_num]
    local cur_group_name = all_groups[case_num].name

    -- Possibly start overview of new group
    if cur_group_name ~= latest_group_name then
      write("\n")
      write(cur_group_name)
      if cur_group_name ~= "" then write(": ") end
    end

    -- Possibly show new symbol
    local case_state = type(cur_case.exec) == "table" and cur_case.exec.state or nil
    local cur_symbol = util.reporter_symbols[case_state]
    if cur_symbol ~= default_symbol then write(cur_symbol) end

    latest_group_name = cur_group_name
  end

  res.finish = function()
    write("\n\n")
    write(overview_reporter.finish_lines(all_cases))
    write("\n")
  end

  return res
end

--- Generate worker reporter: emits one flushed, tab-separated JSON line per
--- finished case plus a final `DONE` summary line, consumed by the parallel
--- orchestrator (`harness/parallel.lua`). Payloads are JSON-encoded so multi-line
--- fail details (tracebacks, screenshot diffs) survive the pipe intact.
---@return table reporter with `start`/`update`/`finish`
M.worker_reporter = function()
  local final_states = {
    ["Pass"] = true,
    ["Pass with notes"] = true,
    ["Fail"] = true,
    ["Fail with notes"] = true,
  }

  local write = function(text)
    io.stdout:write(text, "\n")
    io.stdout:flush()
  end

  return {
    start = function() end,
    update = function()
      local case = state.current.case
      local case_state = case and case.exec and case.exec.state or nil
      if case_state and final_states[case_state] then
        local desc = case.desc or {}
        local name = table.concat(vim.list_slice(desc, 2, #desc), " > ")
        local data = {
          file = desc[1] or "",
          name = name,
          state = case_state,
          fails = case.exec.fails or {},
          notes = case.exec.notes or {},
        }
        write(("CASE\t%s"):format(vim.json.encode(data)))
      end
    end,
    finish = function()
      local cases = state.current.all_cases or {}
      local n_fails, n_notes = 0, 0
      for _, c in ipairs(cases) do
        local exec = c.exec or {}
        n_fails = n_fails + #(exec.fails or {})
        n_notes = n_notes + #(exec.notes or {})
      end
      local data = { n_cases = #cases, n_fails = n_fails, n_notes = n_notes }
      write(("DONE\t%s"):format(vim.json.encode(data)))
    end,
  }
end

return M
