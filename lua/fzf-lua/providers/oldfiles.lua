local core = require "fzf-lua.core"
local config = require "fzf-lua.config"

local M = {}

M.oldfiles = function(opts)
  opts = config.normalize_opts(opts, config.globals.oldfiles)
  if not opts then return end

  local current_buffer = vim.api.nvim_get_current_buf()
  local current_file = vim.api.nvim_buf_get_name(current_buffer)
  local sess_tbl = {}
  local sess_map = {}

  if opts.include_current_session then
    for _, buffer in ipairs(vim.split(vim.fn.execute(':buffers! t'), "\n")) do
      local bufnr = tonumber(buffer:match('%s*(%d+)'))
      if bufnr then
        local file = vim.api.nvim_buf_get_name(bufnr)
        local fs_stat = not opts.stat_file and true or vim.loop.fs_stat(file)
        if #file>0 and fs_stat and bufnr ~= current_buffer then
          sess_map[file] = true
          table.insert(sess_tbl, file)
        end
      end
    end
  end

  local contents = function (cb)

    local entries = {}

    for _, file in ipairs(sess_tbl) do
        table.insert(entries, file)
    end
    for _, file in ipairs(vim.v.oldfiles) do
      local fs_stat = not opts.stat_file and true or vim.loop.fs_stat(file)
      if fs_stat and file ~= current_file and not sess_map[file] then
        table.insert(entries, file)
      end
    end

    for _, x in ipairs(entries) do
      x = core.make_entry_file(opts, x)
      if x then
        cb(x, function(err)
          if err then return end
          -- close the pipe to fzf, this
          -- removes the loading indicator in fzf
          cb(nil, function() end)
        end)
      end
    end
    cb(nil)
  end

  opts = core.set_header(opts, 2)
  return core.fzf_files(opts, contents)
end

return M
