local uv = vim.uv or vim.loop
local core = require "fzf-lua.core"
local shell = require "fzf-lua.shell"
local utils = require "fzf-lua.utils"
local config = require "fzf-lua.config"
local make_entry = require "fzf-lua.make_entry"

local M = {}

M.buffers = function(opts)
  opts = config.normalize_opts(opts, "tmux.buffers")
  if not opts then return end

  opts.fn_transform = function(x)
    local buf, data = x:match([[^(.-):%s+%d+%s+bytes: "(.*)"$]])
    return string.format("[%s] %s", utils.ansi_codes.yellow(buf), data)
  end

  opts.fzf_opts["--preview"] = shell.raw_preview_action_cmd(function(items)
    local buf = items[1]:match("^%[(.-)%]")
    return string.format("tmux show-buffer -b %s", buf)
  end, opts.debug)

  core.fzf_exec(opts.cmd, opts)
end

M.files = function(opts)
  opts = config.normalize_opts(opts, "tmux.files")
  if not opts then return end

  opts.fn_transform = function(item)
    item = vim.trim(item)

    local s = utils.strsplit(item, ":")
    local filepath = item
    if #s > 1 then
      filepath = s[1]
    end
    if opts.cwd_only and string.match(filepath, "%.%./") then
      return nil
    end
    if utils.path_is_directory(filepath) then return nil end
    -- FIFO blocks `fs_open` indefinitely (#908)
    if utils.file_is_fifo(filepath, uv.fs_stat(filepath)) or not utils.file_is_readable(filepath) then
      return nil
    end

    return make_entry.file(item, opts)
  end

  opts = core.set_fzf_field_index(opts)
  core.fzf_exec(opts.cmd, opts)
end

return M
