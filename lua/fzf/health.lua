local M = {}

local start = vim.health.start or vim.health.report_start
local ok = vim.health.ok or vim.health.report_ok
local warn = vim.health.warn or vim.health.report_warn
local error = vim.health.error or vim.health.report_error

function M.check()
  local utils = require("fzf-lua.utils")
  local config = require("fzf-lua.config")

  local tools = { "fzf", "sk", "rg", "fd", "bat", "delta", "git" }
  for _, tool in ipairs(tools) do
    if vim.fn.executable(tool) == 0 then
      warn("'" .. tool .. "' not found")
    else
      ok("'" .. tool .. "' found")
    end
  end

  if vim.fn.executable("fzf") == 1 then
    local version = utils.fzf_version()
    if version >= 0.53 then
      ok("'fzf' >= 0.53. Your version: '" .. version .. "'")
    else
      warn("'fzf' >= 0.53 is recommended. Your version: '" .. version .. "'")
    end
  end

  if vim.fn.executable("fzf") == 0 and vim.fn.executable("sk") == 0 then
    error("fzf or skim is required")
  end

  if vim.env.FZF_DEFAULT_OPTS == nil then
    ok("'FZF_DEFAULT_OPTS' is not set")
  else
    local lines = vim.split(vim.env.FZF_DEFAULT_OPTS, "\n")
    lines = vim.tbl_map(function(line)
      return vim.trim(line)
    end, lines)
    warn("'FZF_DEFAULT_OPTS' is set to:\n" .. table.concat(lines, "\n"))
  end
end

return M
