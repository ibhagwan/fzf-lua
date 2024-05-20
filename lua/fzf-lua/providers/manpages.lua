local core = require "fzf-lua.core"
local utils = require "fzf-lua.utils"
local config = require "fzf-lua.config"
local libuv = require "fzf-lua.libuv"

local M = {}

--- E.g. mandoc: "perlfork(1, 1p)             - Perl's fork() emulation"                 -> "perlfork, 1"
--- E.g. mandoc: "vsnprintf, vsprintf(3P, 3p) - format output of a stdarg argument list" -> "vsnprintf", "3P"
--- E.g. man-db: "vsnprintf (3p)              - format output of a stdarg argument list" -> "vsnprintf", "3p"
--- @param apropos_line string a selected output line from `man -k`
--- @return string page, string and section
local function parse_apropos(apropos_line)
  return apropos_line:match("^([^, (]+)[^(]*%(([^), ]*)")
end
--- @param apropos_line string
--- @return string arg without shellescape
M.manpage_vim_arg = function(apropos_line)
  local page, section = parse_apropos(apropos_line)
  return string.format("%s(%s)", page, section)
end
--- @param apropos_line string
--- @return string arg with shellescape
M.manpage_sh_arg = function(apropos_line)
  local page, section = parse_apropos(apropos_line)
  return libuv.shellescape(section) .. " " .. libuv.shellescape(page)
end

M.manpages = function(opts)
  opts = config.normalize_opts(opts, "manpages")
  if not opts then return end

  if utils.__IS_WINDOWS then
    utils.warn("man is not supported on Windows.")
    return
  end

  opts.fn_transform = function(x)
    -- split by first occurrence of ' - ' (spaced hyphen)
    local man, desc = x:match("^(.-) %- (.*)$")
    return string.format("%-45s %s", man, desc)
  end

  core.fzf_exec(opts.cmd, opts)
end

return M
