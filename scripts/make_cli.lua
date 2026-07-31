-- NOTE: this script is called with `:help -l`
local MiniTest = require("fzf-lua.test.harness")
local glob, filter = vim.env.glob, vim.env.filter
local files = vim.env.FZF_LUA_TEST_FILES
local find_files, filter_cases


if glob then
  -- Find both "tests/glob**/*_spec.lua" and "test/glob*_spec.lua"
  find_files = function()
    local ret = vim.fn.globpath("tests", glob .. "*_spec.lua", true, true)
    for _, f in ipairs(vim.fn.globpath("tests", glob .. "**/*_spec.lua", true, true)) do
      table.insert(ret, f)
    end
    return ret
  end
elseif files then
  -- Explicit spec list set by `scripts/parallel_test.lua` workers
  find_files = function()
    return vim.split(files, "\n", { plain = true, trimempty = true })
  end
else
  -- All test files
  find_files = function()
    return vim.fn.globpath("tests", "**/*_spec.lua", true, true)
  end
end

if filter then
  filter_cases = function(case)
    local desc = vim.deepcopy(case.desc)
    table.remove(desc, 1)
    -- https://github.com/echasnovski/mini.nvim/blob/200df25c9f62d8b803a7aec6127abfc0c6f536ef/lua/mini/test.lua#L1960
    local args = vim.inspect(case.args, { newline = "", indent = "" })
    desc[#desc + 1] = args
    return table.concat(desc, " "):match(filter)
  end
end

-- https://github.com/neovim/neovim/pull/36557
local sig = assert(vim.uv.new_signal())
sig:start(vim.uv.constants.SIGINT, function() MiniTest.stop() end)

if vim.env.FZF_LUA_TEST_WORKER then
  -- Parallel worker mode (`scripts/parallel_test.lua`): emit one flushed,
  -- tab-separated line per case plus a final `DONE` summary, so the
  -- orchestrator can render results live.
  local write = function(text)
    io.stdout:write(text, "\n")
    io.stdout:flush()
  end

  local final_states = {
    ["Pass"] = true,
    ["Pass with notes"] = true,
    ["Fail"] = true,
    ["Fail with notes"] = true,
  }

  local reporter = {
    start = function() end,
    update = function()
      local case = MiniTest.current.case
      local state = case and case.exec and case.exec.state or nil
      if state and final_states[state] then
        local desc = case.desc or {}
        local name = table.concat(vim.list_slice(desc, 2, #desc), " > ")
        write(("CASE\t%s\t%s\t%s"):format(state, desc[1] or "", name))
      end
    end,
    finish = function()
      local cases = MiniTest.current.all_cases or {}
      local n_fails, n_notes = 0, 0
      for _, c in ipairs(cases) do
        local exec = c.exec or {}
        n_fails = n_fails + #(exec.fails or {})
        n_notes = n_notes + #(exec.notes or {})
      end
      write(("DONE\t%d\t%d\t%d"):format(#cases, n_fails, n_notes))
    end,
  }

  MiniTest.run({
    collect = { find_files = find_files, filter_cases = filter_cases },
    execute = { reporter = reporter },
  })

  while MiniTest.is_executing() do vim.wait(20) end
  local n_fails = 0
  for _, c in ipairs(MiniTest.current.all_cases or {}) do
    n_fails = n_fails + #((c.exec or {}).fails or {})
  end
  vim.cmd("cq " .. (n_fails > 0 and 1 or 0))
else
  local jobs = tonumber(vim.env.JOBS or "") or 1
  if jobs > 1 and not glob and not filter then
    -- Parallel mode: run cases inside `jobs` worker nvim processes
    local code = MiniTest.run_parallel({ find_files = find_files, filter_cases = filter_cases }, jobs)
    vim.cmd("cq " .. code)
  else
    MiniTest.run({ collect = { find_files = find_files, filter_cases = filter_cases } })
  end
end
