local api, fn = vim.api, vim.fn
local utils = require("fzf-lua.utils")

---@alias fzf-lua.scrollbar.kind "border"|"float"|"none"

---@class fzf-lua.ScrollBar
---@field _track_buf? integer
---@field _track_win? integer
---@field _thumb_buf? integer
---@field _thumb_win? integer
local M = {}

---@param bufnr? integer
---@return integer
local function ensure_tmp_buf(bufnr)
  if bufnr and api.nvim_buf_is_valid(bufnr) then
    return bufnr
  end
  bufnr = api.nvim_create_buf(false, true)
  vim.bo[bufnr].modifiable = true
  vim.bo[bufnr].bufhidden = "wipe"
  return bufnr
end

---@param win integer
---@param buf integer
---@return integer
local function get_line_count(win, buf)
  if api.nvim_win_text_height then
    return api.nvim_win_text_height(win, {}).all
  else
    return api.nvim_buf_line_count(buf)
  end
end

---@param win integer
---@return integer
local function get_top_line(win)
  local topline = fn.line("w0", win)
  if api.nvim_win_text_height and topline > 1 then
    return api.nvim_win_text_height(win, { end_row = topline - 1 }).all + 1
  end
  return topline
end

---@param win integer
---@return { height: integer, offset: integer, total: integer, line_count: integer }?
local function calculate_dimensions(win)
  if not api.nvim_win_is_valid(win) then
    return nil
  end

  local buf = api.nvim_win_get_buf(win)
  local line_count = get_line_count(win, buf)
  local height = api.nvim_win_get_height(win)
  local topline = get_top_line(win)

  local bar_height = math.min(height, math.ceil(height * height / line_count))
  local bar_offset = math.min(height - bar_height, math.floor(height * topline / line_count))

  return {
    height = bar_height,
    offset = bar_offset,
    total = height,
    line_count = line_count,
  }
end

---@param buf_field "_track_buf"|"_thumb_buf"
---@param win_field "_track_win"|"_thumb_win"
---@param opts vim.api.keyset.win_config
---@param hl string
function M.ensure_window(buf_field, win_field, opts, hl)
  if M[win_field] and api.nvim_win_is_valid(M[win_field]) then
    api.nvim_win_set_config(M[win_field], opts)
  else
    opts.noautocmd = true
    M[buf_field] = ensure_tmp_buf(M[buf_field])
    M[win_field] = utils.nvim_open_win0(M[buf_field], false, opts)
    utils.wo[M[win_field]].eventignorewin = "WinResized"
    utils.wo[M[win_field]].winhl = ("Normal:%s,NormalNC:%s,NormalFloat:%s,EndOfBuffer:%s"):format(
      hl, hl, hl, hl)
  end
end

---@param hls fzf-lua.config.HLS
local function border_compat(hls)
  if hls.scrollfloat_f == false then return end -- already inited
  -- Reverse "FzfLuaScrollBorderFull" color
  local scrollborder_f = hls.scrollborder_f
  local fg = utils.hexcol_from_hl(scrollborder_f, "fg")
  local bg = utils.hexcol_from_hl(scrollborder_f, "bg")
  if fg and #fg > 0 then
    local hlgroup = "FzfLuaScrollBorderBackCompat"
    hls.scrollfloat_f = hlgroup
    api.nvim_set_hl(0, hlgroup,
      vim.o.termguicolors and { default = false, fg = bg, bg = fg }
      or { default = false, ctermfg = utils.tointeger(bg), ctermbg = utils.tointeger(fg) })
  end
end

---@param target_win integer
---@param hls fzf-lua.config.HLS
---@param winopts fzf-lua.config.WinoptsResolved
---@return nil
function M.update(target_win, hls, winopts)
  local preview = winopts.preview
  local kind = preview.scrollbar or "float"

  if kind == "none" then
    return M.close()
  elseif kind == "border" then -- Backward compat since removal of "border" scrollbar
    border_compat(hls)
  end

  local dims = calculate_dimensions(target_win)
  if not dims or dims.height >= dims.line_count then return M.close() end

  local win_width = api.nvim_win_get_width(target_win)
  local scrolloff = kind == "border" and preview.border ~= "none" and 0 or preview.scrolloff or -1

  local base_opts = {
    style = "minimal",
    focusable = false,
    relative = "win",
    anchor = "NW",
    win = target_win,
    width = 1,
    zindex = winopts.zindex + 1,
    row = 0,
    col = win_width + scrolloff,
    border = "none",
    hide = winopts.hide,
  }

  local track_opts = vim.tbl_extend("force", base_opts, {
    height = dims.total,
  })

  local thumb_opts = vim.tbl_extend("force", base_opts, {
    height = dims.height,
    row = dims.offset,
    zindex = winopts.zindex + 2,
  })

  if kind ~= "border" then
    local track_hl = hls.scrollfloat_e or "PmenuSbar"
    M.ensure_window("_track_buf", "_track_win", track_opts, track_hl)
  end

  local thumb_hl = hls.scrollfloat_f or "PmenuThumb"
  M.ensure_window("_thumb_buf", "_thumb_win", thumb_opts, thumb_hl)
end

function M.close()
  if M._track_buf and api.nvim_buf_is_valid(M._track_buf) then
    api.nvim_buf_delete(M._track_buf, { force = true })
  end
  if M._track_win and api.nvim_win_is_valid(M._track_win) then
    utils.nvim_win_close(M._track_win, true)
  end
  if M._thumb_buf and api.nvim_buf_is_valid(M._thumb_buf) then
    api.nvim_buf_delete(M._thumb_buf, { force = true })
  end
  if M._thumb_win and api.nvim_win_is_valid(M._thumb_win) then
    utils.nvim_win_close(M._thumb_win, true)
  end

  M._track_buf = nil
  M._track_win = nil
  M._thumb_buf = nil
  M._thumb_win = nil
end

return M
