local core = require "fzf-lua.core"
local utils = require "fzf-lua.utils"
local config = require "fzf-lua.config"

local M = {}

M.manpages = function(opts)
  opts = config.normalize_opts(opts, "manpages")
  if not opts then return end

  if utils.__IS_WINDOWS then
    utils.warn("man is not supported on Windows.")
    return
  end

  opts.fn_transform = function(x)
    -- split by first occurence of ' - ' (spaced hyphen)
    local man, desc = x:match("^(.-) %- (.*)$")
    return string.format("%-45s %s", man, desc)
  end

  core.fzf_exec(opts.cmd, opts)
end

return M
