local core = require "fzf-lua.core"
local utils = require "fzf-lua.utils"
local config = require "fzf-lua.config"
local libuv = require "fzf-lua.libuv"

local M = {}

---E.g. mandoc: "perlfork(1, 1p)             - Perl's fork() emulation"                 -> "perlfork, 1"
---E.g. mandoc: "vsnprintf, vsprintf(3P, 3p) - format output of a stdarg argument list" -> "vsnprintf", "3P"
---E.g. man-db: "vsnprintf (3p)              - format output of a stdarg argument list" -> "vsnprintf", "3p"
---@param apropos_line string a selected output line from `man -k`
---@return string?, string?
local function parse_apropos(apropos_line)
  return apropos_line:match("^([^, (]+)[^(]*%(([^), ]*)")
end
---@param apropos_line string
---@return string? arg without shellescape, nil for malformed lines
M.manpage_vim_arg = function(apropos_line)
  local page, section = parse_apropos(apropos_line)
  if not (page and section) then return end
  return string.format("%s(%s)", page, section)
end
---@param apropos_line string
---@return string? arg with shellescape, nil for malformed lines
M.manpage_sh_arg = function(apropos_line)
  local page, section = parse_apropos(apropos_line)
  if not (page and section) then return end
  return libuv.shellescape(section) .. " " .. libuv.shellescape(page)
end

---@param opts fzf-lua.config.Manpages|{ }?
---@return thread?, string?, table?
M.manpages = function(opts)
  ---@type fzf-lua.config.Manpages
  opts = config.normalize_opts(opts, "manpages")
  if not opts then return end

  if utils.__IS_WINDOWS then
    utils.warn("man is not supported on Windows.")
    return
  end

  if vim.fn.executable("man") ~= 1 then
    utils.warn("'man' executable not found.")
    return
  end

  -- Run `opts.cmd` once, streaming into the picker. If it fails (e.g. empty
  -- man-db cache, #2572), echo a warning to stderr once the command exits;
  -- with `stderr_to_stdout` the warning shows up as an entry in the picker.
  -- This avoids the blocking pre-run added in #2572 (reworked in #2859) while
  -- keeping the contents a command string, so streaming and the user's
  -- `multiprocess` choice are left untouched.
  if opts.stderr_to_stdout then
    opts.cmd = ("{ %s; rc=$?; if [ $rc -ne 0 ]; then echo %s >&2; fi; }"):format(
      opts.cmd,
      libuv.shellescape "'man -k' returned no results, try running 'sudo mandb' to populate the cache."
    )
  end

  opts.fn_transform = function(x)
    -- split by first occurrence of ' - ' (spaced hyphen)
    local man, desc = x:match("^(.-) %- (.*)$")
    -- keep unexpected lines (e.g. the warning above) as-is
    if not man then return x end
    return string.format("%-45s %s", man, desc)
  end

  return core.fzf_exec(opts.cmd, opts)
end

return M
