-- NOTE: this script is called with `:help -l` (headless `-l`)
local MiniTest = require("fzf-lua.test.harness")
local files = vim.env.FZF_LUA_TEST_FILES

-- Worker mode (`mini/parallel.lua`): find_files reads the spec subset the
-- orchestrator assigned via `FZF_LUA_TEST_FILES`. Must take precedence over
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

-- https://github.com/neovim/neovim/pull/36557
local sig = assert(vim.uv.new_signal())
sig:start(vim.uv.constants.SIGINT, function() MiniTest.stop() end)

local code = MiniTest.run({
  collect = { find_files = find_files, filter_cases = filter_cases },
  jobs = tonumber(vim.env.JOBS or "") or 1,
})
vim.cmd("cq " .. code)
