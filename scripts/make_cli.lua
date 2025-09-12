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
    -- https://github.com/echasnovski/mini.nvim/blob/200df25c9f62d8b803a7aec6127abfc0c6f536ef/lua/mini/test.lua#L1960
    local args = vim.inspect(case.args, { newline = "", indent = "" })
    desc[#desc + 1] = args
    -- local ok, reg = pcall(vim.regex, filter)
    -- return ok and reg:match_str(table.concat(desc, " "))
    return table.concat(desc, " "):match(filter)
  end
end

MiniTest.run({ collect = { find_files = find_files, filter_cases = filter_cases } })
