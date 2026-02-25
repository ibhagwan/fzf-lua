local api = vim.api
local utils = require "fzf-lua.utils"

---@class fzf-lua.win.backdrop
local M = {}

---@param backdrop any
---@param zindex integer
---@param hls fzf-lua.config.HLS
---@return function? close
function M.open(backdrop, zindex, hls)
  -- Called from redraw?
  if M.win then
    if api.nvim_win_is_valid(M.win) then
      api.nvim_win_set_config(M.win, { width = vim.o.columns, height = vim.o.lines })
    end
    return function() M.close() end
  end

  -- Validate backdrop hlgroup and opacity
  hls.backdrop = type(hls.backdrop) == "string" and hls.backdrop or "FzfLuaBackdrop"
  backdrop = utils.tointeger(backdrop) or (backdrop == true and 60 or 100)
  if backdrop < 0 or backdrop > 99 then return end

  -- Neovim bg has no color, will look weird
  if #utils.hexcol_from_hl("Normal", "bg") == 0 then return end

  -- Code from lazy.nvim (#1344)
  M.buf = api.nvim_create_buf(false, true)
  M.win = utils.nvim_open_win0(M.buf, false, {
    relative = "editor",
    width = vim.o.columns,
    height = vim.o.lines,
    row = 0,
    col = 0,
    style = "minimal",
    focusable = false,
    -- -2 as preview border is -1
    zindex = zindex - 2,
    border = "none",
    -- NOTE: backdrop shoulnd't be hidden with winopts.hide
    -- hide = self.winopts.hide,
  })
  local wo = utils.wo[M.win]
  wo.eventignorewin = "FileType"
  wo.winhl = "Normal:" .. hls.backdrop
  wo.winblend = backdrop

  local bo = vim.bo[M.buf]
  bo.buftype = "nofile"
  bo.filetype = "fzflua_backdrop"
  return function() M.close() end
end

function M.close()
  if M.win and api.nvim_win_is_valid(M.win) then api.nvim_win_close(M.win, true) end
  if M.buf and api.nvim_buf_is_valid(M.buf) then api.nvim_buf_delete(M.buf, { force = true }) end
  M.buf = nil
  M.win = nil
  -- vim.cmd("redraw")
end

return M
