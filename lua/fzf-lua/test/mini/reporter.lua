--- Output reporters: the default stdout reporter (sequential runs) and the
--- worker event reporter (parallel runs).

local H = require("fzf-lua.test.mini.util")

H.gen_reporter = {}

--- Generate stdout reporter (headless default). Writes to `stdout` with ANSI
--- coloring: one symbol per case, then a summary on finish. Exiting is left
--- to the entry script (`scripts/make_cli.lua`).
---@param opts table|nil Table with options. Used fields:
---   - <group_depth> - number of first elements of case description (can be zero)
---     used for grouping. Higher values mean higher granularity of output.
---     Default: 1.
---@return table reporter with `start`/`update`/`finish`
H.gen_reporter.stdout = function(opts)
  opts = vim.tbl_deep_extend("force", { group_depth = 1 }, opts or {})

  local write = function(text)
    text = type(text) == "table" and table.concat(text, "\n") or text
    io.stdout:write(text)
    io.flush()
  end

  local all_cases, all_groups, latest_group_name
  local default_symbol = H.reporter_symbols[nil]

  local res = {}

  res.start = function(cases)
    -- Set up data
    all_cases = cases
    all_groups = H.overview_reporter.compute_groups(cases, opts.group_depth)

    -- Write lines
    write(H.overview_reporter.start_lines(all_cases, all_groups))
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
    local state = type(cur_case.exec) == "table" and cur_case.exec.state or nil
    local cur_symbol = H.reporter_symbols[state]
    if cur_symbol ~= default_symbol then write(cur_symbol) end

    latest_group_name = cur_group_name
  end

  res.finish = function()
    write("\n\n")
    write(H.overview_reporter.finish_lines(all_cases))
    write("\n")
  end

  return res
end

--- Generate worker reporter: emits one flushed, tab-separated JSON line per
--- finished case plus a final `DONE` summary line, consumed by the parallel
--- orchestrator (`mini/parallel.lua`). Payloads are JSON-encoded so multi-line
--- fail details (tracebacks, screenshot diffs) survive the pipe intact.
---@return table reporter with `start`/`update`/`finish`
H.worker_reporter = function()
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
      local case = H.current.case
      local state = case and case.exec and case.exec.state or nil
      if state and final_states[state] then
        local desc = case.desc or {}
        local name = table.concat(vim.list_slice(desc, 2, #desc), " > ")
        local data = {
          file = desc[1] or "",
          name = name,
          state = state,
          fails = case.exec.fails or {},
          notes = case.exec.notes or {},
        }
        write(("CASE\t%s"):format(vim.json.encode(data)))
      end
    end,
    finish = function()
      local cases = H.current.all_cases or {}
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

return H
