local M = {}

local lua_io

---Set whether to use io or not
---@param bool boolean
M.set_flag = function(bool)
  lua_io = bool
end

---Run the shell command and get the standard output.
---If failure, it returns an empty string and true.
---@param cmd string
---@return string|table
---@return boolean
M.get_stdout = function(cmd)
  local stdout = {}

  if lua_io then
    local handle = io.popen(cmd, "r")
    if handle == nil then
      return "", true
    end
    for h in handle:lines() do
      stdout[#stdout + 1] = h
    end
  else
    stdout = vim.fn.systemlist(cmd)
    -- vim.fn.systemlist returns an empty string on error.
    if vim.v.shell_error ~= 0 then
      return "", true
    end
  end

  return stdout, false
end

return M
