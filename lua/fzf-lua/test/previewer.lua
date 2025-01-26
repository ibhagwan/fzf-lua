local fzf = require("fzf-lua")
local builtin = require("fzf-lua.previewer.builtin")
local M = builtin.base:extend()

function M:new(o, opts, fzf_win)
  M.super.new(self, o, opts, fzf_win)
  setmetatable(self, M)
  return self
end

function M:populate_preview_buf(entry_str)
  local entry = fzf.path.entry_to_file(entry_str, self.opts)
  local fname = fzf.path.tail(entry.path)
  local buf = self:get_tmp_buffer()
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
    string.format("SELECTED FILE: %s", fname)
  })
  self:set_preview_buf(buf)
  self.win:update_preview_title(fname)
end

return M
