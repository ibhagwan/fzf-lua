-- scripts/parallel_test.lua
-- Run with:
--   nvim -l scripts/parallel_test.lua [opts] NVIM_EXEC [NVIM_EXEC ...]
--
-- Spawns `nvim -l scripts/make_cli.lua` once per spec file with up to
-- `--jobs` concurrent workers, using `vim.system`. Each worker's output
-- is buffered and printed in full as one contiguous block so the log
-- of a single spec file stays readable even when workers run in
-- parallel. Exit code is the count of failing nvim invocations across
-- every requested nvim binary, so CI correctly fails when any spec
-- fails.

---@class parallel_test.worker
---@field id integer
---@field spec string
---@field cmd string[]
---@field env table<string, string>
---@field buf string[]
---@field started boolean
---@field finished boolean
---@field code integer
---@field signal integer

---@class parallel_test.opts
---@field jobs integer
---@field glob? string
---@field filter? string
---@field serial boolean
---@field nvim_execs string[]

---@param args string[]
---@return parallel_test.opts
local function parse_args(args)
  ---@type parallel_test.opts
  local opts = { jobs = 0, serial = false, nvim_execs = {} }
  local i = 1
  while i <= #args do
    local a = args[i]
    if a == "--jobs" or a == "-j" then
      i = i + 1
      local raw = args[i] and tonumber(args[i]) or nil
      ---@cast raw integer?
      opts.jobs = raw or 0
    elseif a == "--glob" then
      i = i + 1
      opts.glob = args[i]
    elseif a == "--filter" then
      i = i + 1
      opts.filter = args[i]
    elseif a == "--serial" then
      opts.serial = true
    elseif a == "--help" or a == "-h" then
      io.stderr:write([[
Usage: nvim -l scripts/parallel_test.lua [opts] NVIM_EXEC [NVIM_EXEC ...]

Options:
  --jobs N, -j N   Parallelism factor (default: nproc / NUMBER_OF_PROCESSORS)
  --glob PATTERN   Forward to make_cli.lua as `vim.env.glob`
  --filter REGEX   Forward to make_cli.lua as `vim.env.filter`
  --serial         Run one nvim for all spec files (legacy single-process mode)
  --help, -h       Show this help
]])
      os.exit(0)
    elseif type(a) == "string" and a:sub(1, 1) == "-" then
      io.stderr:write("parallel_test: unknown option: " .. a .. "\n")
      os.exit(2)
    elseif type(a) == "string" then
      table.insert(opts.nvim_execs, a)
    end
    i = i + 1
  end

  if opts.jobs <= 0 then
    local env = vim.uv and vim.uv.os_getenv("NUMBER_OF_PROCESSORS") or nil
    if env then
      local raw = tonumber(env)
      ---@cast raw integer?
      opts.jobs = raw or 1
    elseif jit and jit.os == "Windows" then
      -- mini.test does not support parallel child Neovim on Windows;
      -- default to one worker unless --jobs is explicitly passed.
      opts.jobs = 1
    else
      local count = 0
      local f = io.open("/proc/cpuinfo", "r")
      if f then
        for line in f:lines() do
          if type(line) == "string" and line:match("^processor%s*:") then
            count = count + 1
          end
        end
        f:close()
      end
      opts.jobs = count > 0 and count or 4
    end
  end
  if opts.jobs < 1 then opts.jobs = 1 end
  return opts
end

---@param root string
---@param pattern? string
---@return string[]
local function list_specs(root, pattern)
  local p = pattern and (pattern .. "*_spec.lua") or "**/*_spec.lua"
  local out = {}
  for _, f in ipairs(vim.fn.globpath(root, p, true, true)) do
    table.insert(out, f)
  end
  -- Sort for stable ordering across runs.
  table.sort(out)
  return out
end

---@param nvim_exec string
---@return string[]
local function build_cmd(nvim_exec)
  return {
    nvim_exec, "--headless", "--noplugin",
    "-u", "./scripts/minimal_init.lua",
    "-l", "./scripts/make_cli.lua",
  }
end

---@param w parallel_test.worker
---@return fun(_err: string?, data: string?)
local function make_data_cb(w)
  return function(_err, data)
    if data then table.insert(w.buf, data) end
  end
end

---@param w parallel_test.worker
---@return fun(obj: vim.SystemCompleted)
local function make_exit_cb(w)
  return vim.schedule_wrap(function(obj)
    w.finished = true
    w.code = obj.code
    w.signal = obj.signal
  end)
end

---@param workers parallel_test.worker[]
---@param jobs integer
local function drive(workers, jobs)
  local next_idx = 1
  local in_flight = 0

  local function spawn_one()
    while in_flight < jobs and next_idx <= #workers do
      local w = workers[next_idx]
      if w then
        next_idx = next_idx + 1
        in_flight = in_flight + 1
        w.started = true
        vim.system(w.cmd, {
          cwd = ".",
          text = true,
          env = w.env,
          stdout = make_data_cb(w),
          stderr = make_data_cb(w),
        }, vim.schedule_wrap(function(obj)
          w.finished = true
          w.code = obj.code
          w.signal = obj.signal
          in_flight = in_flight - 1
        end))
      else
        next_idx = next_idx + 1
      end
    end
  end

  spawn_one()
  -- Pump the event loop until all workers are finished. The short
  -- timeout (200ms) lets on_exit callbacks (wrapped in `vim.schedule`)
  -- run between ticks without busy-spinning.
  while true do
    local all_done = true
    for _, w in ipairs(workers) do
      if w and not w.finished then all_done = false; break end
    end
    if all_done then break end
    vim.wait(200, function()
      for _, w in ipairs(workers) do
        if w and not w.finished then return false end
      end
      return true
    end)
    spawn_one()
  end
  vim.wait(50)
end

---@param workers parallel_test.worker[]
---@return integer fails
local function print_and_collect(workers)
  local fails = 0
  for _, w in ipairs(workers) do
    io.write(string.format("\n----- %s -----\n", w.spec))
    if w.started then
      for _, chunk in ipairs(w.buf) do io.write(chunk) end
      local status = w.code == 0 and "ok" or ("FAIL exit=" .. tostring(w.code))
      io.write(string.format("\n----- %s: %s -----\n", w.spec, status))
      if w.code ~= 0 then fails = fails + 1 end
    else
      io.write("(not started)\n")
      io.write(string.format("----- %s: FAIL not started -----\n", w.spec))
      fails = fails + 1
    end
  end
  io.flush()
  return fails
end

---@param opts parallel_test.opts
---@param nvim_exec string
---@return integer fails
local function run_one_nvim(opts, nvim_exec)
  local specs = list_specs("tests", opts.glob)
  if #specs == 0 then
    io.stderr:write(string.format(
      "parallel_test: no spec files matched (root=tests glob=%s)\n",
      tostring(opts.glob)))
    return 1
  end

  io.write(string.format("Found %d spec file(s) (jobs=%d)\n", #specs, opts.jobs))
  io.flush()

  ---@type parallel_test.worker[]
  local workers = {}
  for i, spec in ipairs(specs) do
    -- Derive the per-spec `glob` (a basename prefix consumed by
    -- `scripts/make_cli.lua`) so each worker re-discovers exactly this
    -- one spec file from its glob query.
    local base = spec:match("([^/\\]+)_spec%.lua$") or spec
    local env = {
      glob = base,
      filter = opts.filter or "",
      update_screenshots = vim.env.update_screenshots or "",
    }
    workers[i] = {
      id = i,
      spec = spec,
      cmd = build_cmd(nvim_exec),
      env = env,
      buf = {},
      started = false,
      finished = false,
      code = -1,
      signal = 0,
    }
  end

  if opts.serial then
    for _, w in ipairs(workers) do
      w.started = true
      vim.system(w.cmd, {
        cwd = ".",
        text = true,
        env = w.env,
        stdout = make_data_cb(w),
        stderr = make_data_cb(w),
      }, make_exit_cb(w))
      vim.wait(2000, function() return w.finished end)
    end
  else
    drive(workers, opts.jobs)
  end

  local fails = print_and_collect(workers)
  io.write(string.format("\n[parallel_test] fails=%d/%d\n", fails, #workers))
  io.flush()
  return fails
end

---@param opts parallel_test.opts
local function main(opts)
  local total_fails = 0
  for _, nvim_exec in ipairs(opts.nvim_execs) do
    io.write(string.format("\n====== %s ======\n",
      vim.fn.system({ nvim_exec, "--version" }):gsub("\n.*$", "")))
    io.flush()
    total_fails = total_fails + run_one_nvim(opts, nvim_exec)
  end

  if total_fails > 0 then
    io.write(string.format("FAIL: %d spec file(s) failed\n", total_fails))
    os.exit(1)
  end
  io.write("PASS: all spec files green\n")
end

local opts = parse_args(_G.arg)
if #opts.nvim_execs == 0 then
  io.stderr:write("parallel_test: at least one NVIM_EXEC is required\n")
  os.exit(2)
end
main(opts)