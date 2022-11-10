local core = require "fzf-lua.core"
local utils = require "fzf-lua.utils"
local config = require "fzf-lua.config"

local M = {}

M.manpages = function(opts)
  opts = config.normalize_opts(opts, config.globals.manpages)
  if not opts then return end

  opts.fn_transform = function(x)
    -- split by first occurence of ' - ' (spaced hyphen)
    local man, desc = x:match("^(.-) %- (.*)$")
    return string.format("%-45s %s",
      utils.ansi_codes.magenta(man), desc)
  end

  opts.fzf_opts["--no-multi"] = ""

  core.fzf_exec(opts.cmd, opts)
end

return M
