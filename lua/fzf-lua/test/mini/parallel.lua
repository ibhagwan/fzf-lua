--- Parallel orchestrator: spawn `jobs` worker nvim processes, each running a
--- subset of the collected spec files, and stream their results live.
---
--- Called from `MiniTest.run()` when `config.jobs > 1`. Workers run
--- `scripts/make_cli.lua` in worker mode (`FZF_LUA_TEST_WORKER=1`), where
--- `find_files` reads `FZF_LUA_TEST_FILES` so each worker executes only its
--- assigned bucket. Results arrive as one flushed, tab-separated JSON line per
--- case (`CASE`) plus a final `DONE` summary (`mini/reporter.lua`).

local H = require("fzf-lua.test.mini.util")

local write = function(text)
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

-- Kill a process and its whole descendant tree (used on worker timeout);
-- `jobstop` alone would orphan the worker's child nvim instances and their
-- fzf processes.
local function kill_tree(pid)
  local children = vim.fn.system("pgrep -P " .. pid)
  for child in children:gmatch("%d+") do kill_tree(tonumber(child)) end
  vim.uv.kill(pid, vim.uv.constants.SIGTERM)
end

--- Render one worker event line. `CASE` lines carry JSON with
--- `file`/`name`/`state` plus `fails`/`notes` detail arrays; `DONE` lines
--- carry the worker totals.
local function handle_line(worker, line, total)
  local kind, rest = line:match("^(%u+)\t(.*)$")
  if not kind then return end
  local ok, data = pcall(vim.json.decode, rest)
  if not ok or type(data) ~= "table" then return end

  if kind == "CASE" then
    local symbol = H.reporter_symbols[data.state] or "?"
    local short_file = basename(data.file)
    write(string.format("[%s] %s %s", short_file, symbol, data.name))

    local n_fails = #(data.fails or {})
    local n_notes = #(data.notes or {})
    if n_fails > 0 then
      local stringid = ("%s | %s"):format(short_file, data.name)
      write("  " .. H.add_style("FAIL in " .. stringid .. ":", "fail"))
      for _, fail in ipairs(data.fails) do
        for fail_line in fail:gmatch("[^\n]+") do
          write("    " .. fail_line)
        end
      end
    end
    if n_notes > 0 then
      local stringid = ("%s | %s"):format(short_file, data.name)
      write("  " .. H.add_style("NOTE in " .. stringid .. ":", n_fails > 0 and "fail" or "pass"))
      for _, note in ipairs(data.notes) do
        for note_line in note:gmatch("[^\n]+") do
          write("    " .. note_line)
        end
      end
    end
  elseif kind == "DONE" then
    total.n_cases = total.n_cases + (tonumber(data.n_cases) or 0)
    total.n_fails = total.n_fails + (tonumber(data.n_fails) or 0)
    total.n_notes = total.n_notes + (tonumber(data.n_notes) or 0)
    write(string.format("worker %d done: %s cases, %s fails, %s notes", worker,
      data.n_cases, data.n_fails, data.n_notes))
  end
end

--- Execute `collect`'s spec files across `jobs` worker nvim processes,
--- rendering each case's result (including fail details) live as it completes.
---@param collect table `collect` options as for `MiniTest.run`
---@param jobs integer number of parallel workers
---@return integer exit code (0 = success, 1 = failure)
local function run_parallel(collect, jobs)
  local specs = collect.find_files()
  if #specs == 0 then return 0 end

  -- Round-robin spec files across workers for load balance
  local buckets = {}
  for i = 1, jobs do buckets[i] = {} end
  for i, f in ipairs(specs) do
    table.insert(buckets[((i - 1) % jobs) + 1], f)
  end

  local total = { n_cases = 0, n_fails = 0, n_notes = 0 }

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
            if line ~= "" then handle_line(w, line, total) end
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
  -- whole process tree of any still-running worker.
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
  write(string.format("Total number of cases: %d", total.n_cases))
  write(string.format("Total number of groups: %d", #specs))
  write("")
  write(string.format("Fails (%d) and Notes (%d)", total.n_fails, total.n_notes))

  return (failed or total.n_fails > 0) and 1 or 0
end

return run_parallel
