local PATH_SEPARATOR = vim.loop.os_uname().sysname:match("Windows") and "\\" or "/"
local ECHOHL = {
  ["ERROR"] = "ErrorMsg",
  ["WARN"] = "ErrorMsg",
  ["INFO"] = "None",
  ["DEBUG"] = "Comment",
}
local DEFAULTS = {
  level = "DEBUG",
  name = "fzf-lua:",
  console = false,
  file = true,
  file_name = "fzf-lua.log",
  file_dir = vim.fn.stdpath("data"),
  file_path = nil,
}
local config = {
  level = "DEBUG",
  name = "fzf-lua:",
  console = false,
  file = true,
  file_name = "fzf-lua.log",
  file_dir = vim.fn.stdpath("data"),
  file_path = string.format("%s%s%s", vim.fn.stdpath("data"), PATH_SEPARATOR, "fzf-lua.log"),
}

local M = {}

M.setup = function(option)
  config = vim.tbl_deep_extend("force", vim.deepcopy(DEFAULTS), option or {})
  if config.file_name and string.len(config.file_name) > 0 then
    -- For Windows: $env:USERPROFILE\AppData\Local\nvim-data\lsp-progress.log
    -- For *NIX: ~/.local/share/nvim/lsp-progress.log
    if config.file_dir then
      config.file_path = string.format("%s%s%s", config.file_dir, PATH_SEPARATOR, config.file_name)
    else
      config.file_path = config.file_name
    end
  end
  assert(type(config.name) == "string" and string.len(config.name) > 0)
  assert(
    type(config.level) == "string"
      and (
        config.level == "ERROR"
        or config.level == "WARN"
        or config.level == "INFO"
        or config.level == "DEBUG"
      )
  )
  if config.file then
    assert(type(config.file_name) == "string" and string.len(config.file_name) > 0)
  end
end

local function log(level, msg)
  if vim.log.levels[level] < vim.log.levels[config.level] then
    return
  end

  local msg_lines = vim.split(msg, "\n")
  if config.console then
    vim.cmd("echohl " .. ECHOHL[level])
    for _, line in ipairs(msg_lines) do
      vim.cmd(
        string.format('echom "%s"', vim.fn.escape(string.format("%s %s", config.name, line), '"'))
      )
    end
    vim.cmd("echohl None")
  end
  if config.file then
    local fp = io.open(config.file_path, "a")
    if fp then
      for _, line in ipairs(msg_lines) do
        fp:write(
          string.format("%s %s [%s]: %s\n", config.name, os.date("%Y-%m-%d %H:%M:%S"), level, line)
        )
      end
      fp:close()
    end
  end
end

M.debug = function(fmt, ...)
  log("DEBUG", string.format(fmt, ...))
end

M.info = function(fmt, ...)
  log("INFO", string.format(fmt, ...))
end

M.warn = function(fmt, ...)
  log("WARN", string.format(fmt, ...))
end

M.error = function(fmt, ...)
  log("ERROR", string.format(fmt, ...))
end

return M
