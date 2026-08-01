--- Shared runtime state for the fzf-lua test framework.
---
--- The single mutable module: holds the per-run cache, the current case, and
--- the child-process registry. Case execution reads/writes these through this
--- module, so `expect`/`case`/`reporter`/`child` stay stateless otherwise.

---@class fzf-lua.test.harness.state
local M = {}

-- Cache for various data, reset per `execute()` run
---@type table<string, any>
M.cache = {
  -- Message with which case is meant to be skipped
  skip_message = nil,
  -- Queue of callables to be executed after step (hook or test function)
  finally = {},
  -- Whether to stop async execution
  should_stop_execution = false,
  -- Whether the execution queue is still draining
  is_executing = false,
  -- Number of screenshots made in current case
  n_screenshots = 0,
}

-- Registry of all Neovim child processes (stopped on `stop()`)
M.child_neovim_registry = {}

-- Current run state, aliased as `harness.current`. Loosely typed so any
-- module can read/write `case` without the linter pinning its shape.
---@type table<string, any>
M.current = { all_cases = nil, case = nil }

--- Skip the rest of current case, adding `msg` to its notes.
---@param msg string|nil
M.skip = function(msg)
  M.cache.skip_message = msg or "Skip test"
  error(M.cache.skip_message, 0)
end

--- Add note to currently executed test case.
---@param msg string
M.add_note = function(msg)
  local case = M.current.case
  case.exec = case.exec or {}
  case.exec.notes = case.exec.notes or {}
  table.insert(case.exec.notes, msg)
end

--- Register callable execution after current callable finishes (regardless of
--- whether it ended with error or not).
---@param f function|table
M.finally = function(f) table.insert(M.cache.finally, f) end

--- Check if tests are being executed
---@return boolean
M.is_executing = function() return M.cache.is_executing == true end

return M
