local M = {}

M.get_stdout = function(cmd)
  local stdout = {}
  for h in io.popen(cmd, "r"):lines() do
    stdout[#stdout + 1] = h
  end
  return stdout
end

return M
