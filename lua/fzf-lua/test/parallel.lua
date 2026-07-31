--- Parallel test runner: spawn `jobs` worker nvim processes, each running a
--- subset of the collected spec files, and stream their results live.
---
--- Called from `scripts/make_cli.lua` when `JOBS>1`; the default single
--- process path executes cases directly via `MiniTest.run`. Workers run
--- `scripts/make_cli.lua` in worker mode (`FZF_LUA_TEST_WORKER`), which
--- emits one flushed, tab-separated line per case plus a final `DONE` line.

local M = {}

-- ANSI codes matching mini.test's reporter symbols
local symbols = {
  ["Pass"] = "\27[1;32mo\27[0m",
  ["Pass with notes"] = "\27[1;32mO\27[0m",
  ["Fail"] = "\27[1;31mx\27[0m",
  ["Fail with notes"] = "\27[1;31mX\27[0m",
}

local function write(text)
  io.stdout:write(text, "\n")
  io.stdout:flush()
end

local function basename(f)
  return f:gsub("^.*/", ""):gsub("_spec%.lua$", "")
end

-- Resolve the real nvim binary. `vim.v.progpath` may point to a wrapper
-- script (e.g. `~/.bin/nvim`) that injects extra startup args into every
-- spawned instance; workers must run the actual binary instead.
local function nvim_executable()
  local exe = vim.fn.resolve("/proc/self/exe")
  if vim.loop.fs_stat(exe) then return exe end
  return vim.v.progpath
end

-- Kill a process and its whole descendant tree (used on worker timeout).
local function kill_tree(pid)
  local children = vim.fn.system("pgrep -P " .. pid)
  for child in children:gmatch("%d+") do kill_tree(child) end
  vim.fn.system("kill -TERM " .. pid)
end

--- Execute the collected spec files across `jobs` worker nvim processes.
---
--- Mirrors `MiniTest.run`'s collect-then-execute flow, but runs the cases
--- inside `jobs` child nvim instances and renders each case's result live as
--- it completes.
---@param collect table `collect` options as for `MiniTest.run`
---@param jobs integer number of parallel workers
---@return integer exit code (0 = success, 1 = failure)
function M.run(collect, jobs)
  local specs = collect.find_files()
  if #specs == 0 then return 0 end

  -- Round-robin spec files across workers for load balance
  local buckets = {}
  for i = 1, jobs do buckets[i] = {} end
  for i, f in ipairs(specs) do
    table.insert(buckets[((i - 1) % jobs) + 1], f)
  end

  local total_cases, total_fails, total_notes = 0, 0, 0

  local function handle_line(worker, line)
    local kind, rest = line:match("^(%u+)\t(.*)$")
    if not kind then return end
    local parts = vim.split(rest, "\t", { plain = true })
    if kind == "CASE" and #parts >= 3 then
      local symbol = symbols[parts[1]] or "?"
      write(string.format("[%s] %s %s", basename(parts[2]), symbol, parts[3]))
    elseif kind == "DONE" and #parts >= 3 then
      total_cases = total_cases + (tonumber(parts[1]) or 0)
      total_fails = total_fails + (tonumber(parts[2]) or 0)
      total_notes = total_notes + (tonumber(parts[3]) or 0)
      write(string.format("worker %d done: %s cases, %s fails, %s notes", worker,
        parts[1], parts[2], parts[3]))
    end
  end

  local job_ids, worker_of_job = {}, {}
  local exit_codes, n_exited = {}, 0
  local function on_exit(job_id, code)
    exit_codes[job_id] = code
    n_exited = n_exited + 1
  end
  for w, bucket in ipairs(buckets) do
    if #bucket > 0 then
      local names = vim.tbl_map(basename, bucket)
      write(string.format("--- worker %d (%d files: %s) ---", w, #bucket, table.concat(names, ", ")))
      local job_id = vim.fn.jobstart({
        nvim_executable(), "--headless", "--noplugin", "-u", "scripts/minimal_init.lua",
        "-l", "scripts/make_cli.lua",
      }, {
        env = { FZF_LUA_TEST_WORKER = "1", FZF_LUA_TEST_FILES = table.concat(bucket, "\n") },
        -- nvim delivers complete lines (trailing newlines stripped, empty
        -- elements as separators); handle each non-empty element as one line
        on_stdout = function(_, data)
          for _, line in ipairs(data) do
            if line ~= "" then handle_line(w, line) end
          end
        end,
        on_exit = on_exit,
        stdout_buffered = false,
      })
      job_ids[#job_ids + 1] = job_id
      worker_of_job[#job_ids] = w
    end
  end

  -- Wait for all workers to exit (`jobwait` returns as soon as the first job
  -- exits, so track completion via `on_exit` instead). On timeout, kill the
  -- whole process tree of any still-running worker; `jobstop` alone would
  -- orphan the worker's child nvim instances and their fzf processes.
  local timeout = tonumber(vim.env.FZF_LUA_TEST_TIMEOUT) or 900000
  local done = vim.wait(timeout, function() return n_exited >= #job_ids end)
  local failed = false
  if not done then
    failed = true
    for i, job_id in ipairs(job_ids) do
      if exit_codes[job_id] == nil then
        write(string.format("worker %d timed out, stopping", worker_of_job[i]))
        local pid = vim.fn.jobpid(job_id)
        if pid and pid > 0 then kill_tree(pid) end
      end
    end
  end
  for i, job_id in ipairs(job_ids) do
    local code = exit_codes[job_id]
    if code and code ~= 0 then
      failed = true
      write(string.format("worker %d exited with code %d", worker_of_job[i], code))
    end
  end

  write("")
  write(string.format("Total number of cases: %d", total_cases))
  write(string.format("Total number of groups: %d", #specs))
  write("")
  write(string.format("Fails (%d) and Notes (%d)", total_fails, total_notes))

  return (failed or total_fails > 0) and 1 or 0
end

return M
