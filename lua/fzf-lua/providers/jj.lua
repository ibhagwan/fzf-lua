local core = require "fzf-lua.core"
local path = require "fzf-lua.path"
local utils = require "fzf-lua.utils"
local config = require "fzf-lua.config"

local M = {}

local function set_jj_cwd_args(opts)
  -- verify cwd is a jj repo, override user supplied
  -- cwd if cwd isn't a jj repo, error was already
  -- printed to `:messages` by 'path.jj_root'
  local jj_root = path.jj_root(opts)
  if not opts.cwd or not jj_root then
    opts.cwd = jj_root
  end
  return opts
end

---@param opts table|{}?
---@return thread?, string?, table?
M.files = function(opts)
  opts = config.normalize_opts(opts, "jj.files")
  if not opts then return end
  opts = set_jj_cwd_args(opts)
  if not opts.cwd then return end
  return core.fzf_exec(opts.cmd, opts)
end

return M
