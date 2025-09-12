local fzf = require("fzf-lua")
local builtin = require("fzf-lua.previewer.builtin")
local M = {}
M.builtin = builtin.base:extend()
M.fzf = require("fzf-lua.previewer.fzf").base:extend()

function M.builtin:new(o, opts, fzf_win)
  self.super.new(self, o, opts, fzf_win)
  setmetatable(self, M.builtin)
  return self
end

function M.builtin:populate_preview_buf(entry_str)
  local entry = fzf.path.entry_to_file(entry_str, self.opts)
  local fname = fzf.path.tail(entry.path)
  local buf = self:get_tmp_buffer()
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
    string.format("SELECTED FILE: %s", fname)
  })
  self:set_preview_buf(buf)
  self.win:update_preview_title(fname)
end

function M.fzf:new(o, opts, fzf_win)
  self.super.new(self, o, opts, fzf_win)
  setmetatable(self, M.fzf)
  return self
end

function M.fzf:cmdline(_)
  return fzf.shell.stringify_data(function(items, _, _)
    return items[1]
  end, self.opts, self.opts.field_index_expr or "{}")
end

return M
