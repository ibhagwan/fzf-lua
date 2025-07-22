local core = require "fzf-lua.core"
local shell = require "fzf-lua.shell"
local utils = require "fzf-lua.utils"
local config = require "fzf-lua.config"

local M = {}

M.buffers = function(opts)
  ---@type fzf-lua.config.TmuxBuffers
  opts = config.normalize_opts(opts, "tmux.buffers")
  if not opts then return end

  opts.fn_transform = function(x)
    local buf, data = x:match([[^(.-):%s+%d+%s+bytes: "(.*)"$]])
    return string.format("[%s] %s", utils.ansi_codes.yellow(buf), data)
  end

  opts.fzf_opts["--preview"] = shell.stringify_cmd(function(items)
    local buf = items[1]:match("^%[(.-)%]")
    return string.format("tmux show-buffer -b %s", buf)
  end, opts, "{}")

  return core.fzf_exec(opts.cmd, opts)
end

return M
