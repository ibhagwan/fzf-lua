---@diagnostic disable: deprecated
local M = {}

local start = vim.health.start or vim.health.report_start
local ok = vim.health.ok or vim.health.report_ok
local warn = vim.health.warn or vim.health.report_warn
local error = vim.health.error or vim.health.report_error
local uv = vim.uv or vim.loop

function M.check()
  local is_win = jit.os:find("Windows")
  local utils = require("fzf-lua.utils")

  local function have(tool, nowarn)
    if vim.fn.executable(tool) == 0 then
      if not nowarn then
        warn("'" .. tool .. "' not found")
      end
    else
      local version = vim.fn.system(tool .. " --version") or ""
      version = vim.trim(vim.split(version, "\n")[1])
      ok("'" .. tool .. "' `" .. version .. "`")
      return true
    end
  end

  start("fzf-lua [required]")
  local required = {
    { "fzf", "sk" },
    { "git" },
    is_win and { "rg" } or { "rg", "grep" },
    is_win and { "fd", "find", "dir" } or { "fd", "fdfind", "find" },
  }

  for _, reqs in ipairs(required) do
    local found = false
    for _, tool in ipairs(reqs) do
      if have(tool, true) then
        found = true
        break
      end
    end
    if not found then
      local str = table.concat(
        vim.tbl_map(function(tool)
          return "`" .. tool .. "`"
        end, reqs),
        ", "
      )
      error("One of " .. str .. " is required")
    end
  end

  local run = vim.fn.stdpath("run")
  if not uv.fs_access(run, "rwx") then
    error(
      "Your 'run' directory is invalid `"
      .. run
      .. "`.\nPlease make sure `XDG_RUNTIME_DIR` is set correctly."
    )
  end

  local srv_ok, srv_pipe = pcall(vim.fn.serverstart)
  if srv_ok then
    vim.fn.delete(srv_pipe)
  else
    error(string.format(
      "`vim.fn.serverstart()` failed with '%s'\n%s",
      srv_ok,
      "Please make sure `XDG_RUNTIME_DIR` is writeable."
    ))
  end

  if vim.fn.executable("fzf") == 1 then
    local version = utils.fzf_version()
    if version < 0.53 then
      warn("'fzf' `>= 0.53` is recommended.")
    end
  end

  start("fzf-lua [optional]")
  if pcall(require, "nvim-web-devicons") then
    ok("`nvim-web-devicons` found")
  else
    warn("`nvim-web-devicons` not found")
  end
  for _, tool in ipairs({ "rg", "fd", "fdfind", "bat", "batcat", "delta" }) do
    have(tool, true)
  end

  if not is_win then
    start("fzf-lua [optional:media]")
    for _, tool in ipairs({ "viu", "chafa", "ueberzugpp" }) do
      have(tool)
    end
  end

  start("fzf-lua [env]")
  if vim.env.FZF_DEFAULT_OPTS == nil then
    ok("`FZF_DEFAULT_OPTS` is not set")
  else
    ok("`$FZF_DEFAULT_OPTS` is set to:\n" .. M.format(vim.env.FZF_DEFAULT_OPTS))
  end
  if vim.env.FZF_DEFAULT_OPTS_FILE == nil then
    ok("`FZF_DEFAULT_OPTS_FILE` is not set")
  else
    ok("`FZF_DEFAULT_OPTS_FILE` is set to `" .. vim.env.FZF_DEFAULT_OPTS_FILE .. "`")
  end
end

---@param str string
function M.format(str)
  str = str:gsub("%s+", " ")
  local options = vim.split(vim.trim(str), " -", { plain = true })
  local lines = {}
  for o, opt in ipairs(options) do
    opt = o == 1 and opt or ("-" .. opt)
    opt = vim.trim(opt)
    opt = opt .. string.rep(" ", math.ceil(#opt / 30) * 30 - #opt)
    if #lines == 0 or #lines[#lines] > 80 then
      table.insert(lines, opt)
    else
      lines[#lines] = lines[#lines] .. "" .. opt
    end
  end
  lines = vim.tbl_map(function(line)
    return vim.trim(line)
  end, lines)
  return table.concat(lines, "\n")
end

return M
