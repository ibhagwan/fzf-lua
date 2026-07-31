-- NOTE: this script is called with `:help -l` (headless `-l`)
local MiniTest = require("fzf-lua.test.harness")
local files = vim.env.FZF_LUA_TEST_FILES

-- Parallel worker mode (`mini/parallel.lua`): find_files reads the full
-- resolved spec list the orchestrator assigned via `FZF_LUA_TEST_FILES`, so
-- the worker re-collects the identical case array. Must take precedence over
-- `glob`/`filter`, which are inherited from the orchestrator environment.
local find_files
if files then
  find_files = function()
    return vim.split(files, "\n", { plain = true, trimempty = true })
  end
else
  local glob = vim.env.glob
  if glob then
    -- Find both "tests/glob**/*_spec.lua" and "tests/glob*_spec.lua"
    find_files = function()
      local ret = vim.fn.globpath("tests", glob .. "*_spec.lua", true, true)
      for _, f in ipairs(vim.fn.globpath("tests", glob .. "**/*_spec.lua", true, true)) do
        table.insert(ret, f)
      end
      return ret
    end
  else
    find_files = function()
      return vim.fn.globpath("tests", "**/*_spec.lua", true, true)
    end
  end
end

local filter_cases
if vim.env.filter then
  local filter = vim.env.filter
  filter_cases = function(case)
    local desc = vim.deepcopy(case.desc)
    table.remove(desc, 1)
    local args = vim.inspect(case.args, { newline = "", indent = "" })
    desc[#desc + 1] = args
    return table.concat(desc, " "):match(filter)
  end
end

-- Parallel worker mode: `FZF_LUA_TEST_CASES` holds the comma-separated global
-- case indices (in the post-filter array) the orchestrator assigned to this
-- worker. The user filter is applied first, then the surviving cases are
-- counted and kept only when their index is in the allowed set.
if vim.env.FZF_LUA_TEST_CASES then
  local allowed = {}
  for idx in vim.env.FZF_LUA_TEST_CASES:gmatch("%d+") do
    allowed[tonumber(idx)] = true
  end
  local user_filter = filter_cases
  local n = 0
  filter_cases = function(case)
    if user_filter and not user_filter(case) then return false end
    n = n + 1
    return allowed[n] == true
  end
end

-- https://github.com/neovim/neovim/pull/36557
local sig = assert(vim.uv.new_signal())
sig:start(vim.uv.constants.SIGINT, function() MiniTest.stop() end)

local code = MiniTest.run({
  collect = { find_files = find_files, filter_cases = filter_cases },
  jobs = tonumber(vim.env.JOBS or "") or 1,
})
vim.cmd("cq " .. code)
