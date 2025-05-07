-- NOTE: this script is called with `:help -l`
local MiniTest = require("mini.test")
local glob, filter = vim.env.glob, vim.env.filter
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
    return table.concat(desc, " "):match(filter)
  end
end

MiniTest.run({ collect = { find_files = find_files, filter_cases = filter_cases } })
