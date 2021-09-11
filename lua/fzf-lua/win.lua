local utils = require "fzf-lua.utils"
local config = require "fzf-lua.config"

local api = vim.api
local fn = vim.fn

local FzfWin = {}

-- signgleton instance used in win_leave
local _self = nil

setmetatable(FzfWin, {
  __call = function (cls, ...)
    return cls:new(...)
  end,
})

local generate_layout = function(winopts)
  local row, col = winopts.row, winopts.col
  local height, width = winopts.height, winopts.width
  local preview_pos = winopts.preview_pos
  local preview_size = winopts.preview_size
  local prev_row, prev_col = row, col
  local prev_height, prev_width
  local padding = 2
  local anchor
  local vert_split = winopts.split and winopts.split:match("vnew") ~= nil
  if preview_pos == 'down' or preview_pos == 'up' then
    height = height - padding
    prev_width = width
    prev_height = utils.round(height * preview_size/100, 0.6)
    height = height - prev_height
    if preview_pos == 'up' then
      row = row + prev_height + padding
      if winopts.split then
        anchor = 'NW'
        prev_row = 1
        prev_height = prev_height - 1
        if vert_split then
          prev_col = 1
        end
      else
        anchor = 'SW'
        prev_row = row - padding
      end
    else
      anchor = 'NW'
      if winopts.split then
        prev_col = 1
        prev_row = height + padding
        prev_height = prev_height - 1
      else
        prev_row = row + height + padding
      end
    end
  elseif preview_pos == 'left' or preview_pos == 'right' then
    prev_height = height
    prev_width = utils.round(width * preview_size/100)
    width = width - prev_width
    if preview_pos == 'left' then
      anchor = 'NE'
      col = col + prev_width
      prev_col = col - padding
      if winopts.split then
        prev_row = 1
        prev_height = prev_height - padding
        if vert_split then
          anchor = 'NW'
          prev_col = 1
          prev_width = prev_width + 1
        else
          prev_width = prev_width - 1
        end
      end
    else
      anchor = 'NW'
      if winopts.split then
        prev_row = 1
        prev_height = prev_height - padding
        if vert_split then
          prev_col = width + 2
          prev_width = prev_width - 1
        else
          prev_col = width + 3
          prev_width = prev_width - padding
        end
      else
        prev_col = col + width + padding
      end
    end
  end
  return {
    fzf = {
      row = row, col = col,
      height = height, width = width,
    },
    preview = {
      anchor = anchor,
      row = prev_row, col = prev_col,
      height = prev_height, width = prev_width,
    }
  }
end

local normalize_winopts = function(opts)
  if not opts then opts = {} end
  if not opts.winopts then opts.winopts = {} end
  opts = vim.tbl_deep_extend("keep", opts, config.globals)
  opts.winopts = vim.tbl_deep_extend("keep", opts.winopts, config.globals.winopts)
  opts.winopts_raw = opts.winopts_raw or config.globals.winopts_raw

  local raw = {}
  if opts.winopts_raw and type(opts.winopts_raw) == "function" then
    raw = opts.winopts_raw()
  end

  local winopts = opts.winopts
  local height = raw.height or math.floor(vim.o.lines * winopts.win_height)
  local width = raw.width or math.floor(vim.o.columns * winopts.win_width)
  local row = raw.row or math.floor((vim.o.lines - height) * winopts.win_row)
  local col = raw.col or math.floor((vim.o.columns - width) * winopts.win_col)
  local border = raw.border or winopts.win_border
  local scrollchar = raw.scrollchar or winopts.scrollchar
  local hl_normal = raw.hl_normal or winopts.hl_normal
  local hl_border = raw.hl_border or winopts.hl_border

  -- normalize border option for nvim_open_win()
  if border == false then
    border = {}
    for i=1, 8 do border[i] = ' ' end
  elseif border == true or border == nil then
    border = config.globals.winopts.borderchars
  end


  -- parse preview options
  local preview = opts.preview_horizontal
  if opts.preview_layout == "vertical" then
    preview = opts.preview_vertical
  elseif opts.preview_layout == "flex" then
    preview = utils._if(vim.o.columns>opts.flip_columns, opts.preview_horizontal, opts.preview_vertical)
  end

  -- builtin previewer params
  local prev_pos = preview:match("[^:]+") or 'right'
  local prev_size = tonumber(preview:match(":(%d+)%%")) or 50

  return {
    height = height, width = width, row = row, col = col, border = border,
    window_on_create = raw.window_on_create or winopts.window_on_create,
    split = raw.split or winopts.split,
    hl_normal = hl_normal, hl_border = hl_border,
    -- builtin previewer params
    scrollchar = scrollchar,
    preview_pos = prev_pos, preview_size = prev_size,
  }
end

function FzfWin:reset_win_highlights(win, is_border)
  local hl = ("Normal:%s,FloatBorder:%s"):format(
    self.winopts.hl_normal, self.winopts.hl_border)
  if self._previewer and self._previewer.hl_cursorline then
    hl = hl .. (",CursorLine:%s"):format(self._previewer.hl_cursorline)
  end
  if is_border then
    -- our border is manuually drawn so we need
    -- to replace Normal with the border color
    hl = ("Normal:%s"):format(self.winopts.hl_border)
  end
  vim.api.nvim_win_set_option(win, 'winhighlight', hl)
end

function FzfWin:new(o)
  o = o or {}
  self = setmetatable({}, { __index = self })
  self.winopts = normalize_winopts(o)
  self.previewer = o.previewer
  self.previewer_type = o.previewer_type
  _self = self
  return self
end

function FzfWin:attach_previewer(previewer)
  self._previewer = previewer
  self.previewer_is_builtin = previewer and type(previewer.display_entry) == 'function'
end

function FzfWin:fs_preview_layout(fs)
  local prev_winopts = self.prev_winopts
  local border_winopts = self.border_winopts
  if not fs or self.winopts.split
    or not prev_winopts or not border_winopts
    or vim.tbl_isempty(prev_winopts)
    or vim.tbl_isempty(border_winopts) then
    return prev_winopts, border_winopts
  end

  local preview_pos = self.winopts.preview_pos
  local height_diff = 0
  local width_diff = 0
  if preview_pos == 'down' or preview_pos == 'up'then
    width_diff = vim.o.columns - border_winopts.width
    if preview_pos == 'down' then
      height_diff = vim.o.lines - border_winopts.row - border_winopts.height - 3
    elseif preview_pos == 'up' then
      height_diff = border_winopts.row - border_winopts.height + 1
    end
    prev_winopts.col = prev_winopts.col - width_diff/2
    border_winopts.col = border_winopts.col - width_diff/2
  elseif preview_pos == 'left' or preview_pos == 'right'then
    height_diff = vim.o.lines - border_winopts.height - 2
    if preview_pos == 'left' then
      width_diff = border_winopts.col - border_winopts.width + 1
    elseif preview_pos == 'right' then
      width_diff = vim.o.columns - border_winopts.col - border_winopts.width - 1
    end
    prev_winopts.row = prev_winopts.row - height_diff/2 - 1
    border_winopts.row = border_winopts.row - height_diff/2 - 1
  end

  prev_winopts.height = prev_winopts.height + height_diff
  border_winopts.height = border_winopts.height + height_diff
  prev_winopts.width = prev_winopts.width + width_diff
  border_winopts.width = border_winopts.width + width_diff

  return prev_winopts, border_winopts
end

function FzfWin:preview_layout()
    if self.winopts.split and self.previewer_is_builtin then
      local wininfo = fn.getwininfo(self.fzf_winid)[1]
      self.layout = generate_layout({
        row = wininfo.winrow,
        col = wininfo.wincol,
        height = wininfo.height,
        width = api.nvim_win_get_width(self.fzf_winid),
        preview_pos = self.winopts.preview_pos,
        preview_size = self.winopts.preview_size,
        split = self.winopts.split,
      })
    end
    if not self.layout then return {}, {} end

    local anchor = self.layout.preview.anchor
    local row, col = self.layout.preview.row, self.layout.preview.col
    local width, height = self.layout.preview.width, self.layout.preview.height
    if not anchor or not width or width < 1 or not height or height < 1 then
        return {}, {}
    end

    local winopts = {relative = 'win', win = self.fzf_winid, focusable = false, style = 'minimal'}
    if self.winopts.split then
      width = width - 2
    end
    local preview_opts = vim.tbl_extend('force', winopts, {
        anchor = anchor,
        width = width,
        height = height,
        col = col,
        row = row
    })
    local border_winopts = vim.tbl_extend('force', winopts, {
        anchor = anchor,
        width = width + 2,
        height = height + 2,
        col = anchor:match('W') and col - 1 or col + 1,
        row = anchor:match('N') and row - 1 or row + 1
    })
    return preview_opts, border_winopts
end

function FzfWin:validate_preview()
  return self.preview_winid and self.preview_winid > 0
    and api.nvim_win_is_valid(self.preview_winid)
    and self.border_winid and self.border_winid > 0
    and api.nvim_win_is_valid(self.border_winid)
end

function FzfWin:preview_winids()
    return self.preview_winid, self.border_winid
end

local strip_border_highlights = function(border)
  local default = config.globals.winopts.borderchars
  if not border or type(border) ~= 'table' or #border<8 then
    return default
  end
  local borderchars = {}
  for i=1, 8 do
    if type(border[i]) == 'string' then
      table.insert(borderchars, border[i])
    elseif type(border[i]) == 'table' and type(border[i][1]) == 'string' then
      -- can happen when border chars contains a highlight, i.e:
      -- border = { {'╭', 'NormalFloat'}, {'─', 'NormalFloat'}, ... }
      table.insert(borderchars, border[i][1])
    else
      table.insert(borderchars, default[i])
    end
  end
  -- assert(#borderchars == 8)
  return borderchars
end

function FzfWin:update_border_buf()
  local border_buf = self.border_buf
  local border_winopts = self.border_winopts
  local border_chars = strip_border_highlights(self.winopts.border)
  local width, height = border_winopts.width, border_winopts.height
  local top = border_chars[1] .. border_chars[2]:rep(width - 2) .. border_chars[3]
  local mid = border_chars[8] .. (' '):rep(width - 2) .. border_chars[4]
  local bot = border_chars[7] .. border_chars[6]:rep(width - 2) .. border_chars[5]
  local lines = {top}
  for _ = 1, height - 2 do
    table.insert(lines, mid)
  end
  table.insert(lines, bot)
  if not border_buf then
    border_buf = api.nvim_create_buf(false, true)
    -- run nvim with `-M` will reset modifiable's default value to false
    vim.bo[border_buf].modifiable = true
    vim.bo[border_buf].bufhidden = 'wipe'
  end
  api.nvim_buf_set_lines(border_buf, 0, -1, 1, lines)
  return border_buf
end

function FzfWin:redraw_preview()
  self.prev_winopts, self.border_winopts = self:preview_layout()
  if vim.tbl_isempty(self.prev_winopts) or vim.tbl_isempty(self.border_winopts) then
      return -1, -1
  end

  -- expand preview only if set by the previewer
  if self._previewer and self._previewer.expand then
    self.prev_winopts, self.border_winopts =
      self:fs_preview_layout(self._previewer.expand)
  end

  if self:validate_preview() then
    self.border_buf = api.nvim_win_get_buf(self.border_winid)
    self:update_border_buf()
    api.nvim_win_set_config(self.border_winid, self.border_winopts)
    api.nvim_win_set_config(self.preview_winid, self.prev_winopts)
    if self._previewer and self._previewer.set_winopts then
      self._previewer:set_winopts(self.preview_winid)
      self._previewer:display_last_entry()
    end
  else
    local tmp_buf = api.nvim_create_buf(false, true)
    api.nvim_buf_set_option(tmp_buf, 'bufhidden', 'wipe')
    self.border_buf = self:update_border_buf()
    self.preview_winid = api.nvim_open_win(tmp_buf, false, self.prev_winopts)
    self.border_winid = api.nvim_open_win(self.border_buf, false, self.border_winopts)
    -- nowrap border or long filenames will mess things up
    api.nvim_win_set_option(self.border_winid, 'wrap', false)
  end
  self:reset_win_highlights(self.border_winid, true)
  self:reset_win_highlights(self.preview_winid)
  return self.preview_winid, self.border_winid
end

function FzfWin:validate()
  return self.fzf_winid and self.fzf_winid > 0
    and api.nvim_win_is_valid(self.fzf_winid)
end

function FzfWin:redraw()
    if self.winopts.split then return end
    local hidden = self._previewer and self._previewer.hidden
    local relative = self.winopts.relative or 'editor'
    local columns, lines = vim.o.columns, vim.o.lines
    if relative == 'win' then
      columns, lines = vim.api.nvim_win_get_width(0), vim.api.nvim_win_get_height(0)
    end

    local winopts = self.winopts
    if self.layout and not hidden then winopts = self.layout.fzf end
    local win_opts = {
      width = winopts.width or math.min(columns - 4, math.max(80, columns - 20)),
      height = winopts.height or math.min(lines - 4, math.max(20, lines - 10)),
      style = 'minimal',
      relative = relative,
      border = self.winopts.border
    }
    win_opts.row = winopts.row or math.floor(((lines - win_opts.height) / 2) - 1)
    win_opts.col = winopts.col or math.floor((columns - win_opts.width) / 2)

    if self:validate() then
      api.nvim_win_set_config(self.fzf_winid, win_opts)
    else
      self.fzf_bufnr = vim.api.nvim_create_buf(false, true)
      self.fzf_winid = vim.api.nvim_open_win(self.fzf_bufnr, true, win_opts)
    end
end

function FzfWin:create()
  if not self.winopts.split and self.previewer_is_builtin then
    self.layout = generate_layout(self.winopts)
  end
  -- save sending bufnr/winid
  self.src_bufnr = vim.api.nvim_get_current_buf()
  self.src_winid = vim.api.nvim_get_current_win()

  if self.winopts.split then
    vim.cmd(self.winopts.split)
    self.fzf_bufnr = vim.api.nvim_get_current_buf()
    self.fzf_winid = vim.api.nvim_get_current_win()
  else
    -- draw the main window
    self:redraw()
  end

  -- verify the preview is closed, this can happen
  -- when running async LSP with 'jump_to_single_result'
  -- should also close issue #105
  -- https://github.com/ibhagwan/fzf-lua/issues/105
  vim.cmd(('au WinLeave <buffer> %s'):format(
    [[lua require('fzf-lua.win').win_leave()]]))

  self:reset_win_highlights(self.fzf_winid)

  if self.winopts.window_on_create and
      type(self.winopts.window_on_create) == 'function' then
    self.winopts.window_on_create()
  end

  -- create or redraw the preview win
  local hidden = self._previewer and self._previewer.hidden
  if not hidden then self:redraw_preview() end

  -- setup the keybinds for the builtin previewer
  if self._previewer and self._previewer.setup_keybinds then
    self._previewer:setup_keybinds()
  end

  return {
    src_bufnr = self.src_bufnr,
    src_winid = self.src_winid,
    fzf_bufnr = self.fzf_bufnr,
    fzf_winid = self.fzf_winid,
  }

end

function FzfWin:close_preview()
  if self._previewer and self._previewer.close then
    self._previewer:close()
  end
  if not self:validate_preview() then return end
  if vim.api.nvim_win_is_valid(self.border_winid) then
    api.nvim_win_close(self.border_winid, true)
  end
  if vim.api.nvim_buf_is_valid(self.border_buf) then
    vim.api.nvim_buf_delete(self.border_buf, {force=true})
  end
  if vim.api.nvim_win_is_valid(self.preview_winid) then
    api.nvim_win_close(self.preview_winid, true)
  end
  self.border_buf = nil
  self.border_winid = nil
  self.preview_winid = nil
end

function FzfWin:close()
  -- prevents race condition with 'win_leave'
  self.closing = true
  self:close_preview()
  if vim.api.nvim_win_is_valid(self.fzf_winid) then
    vim.api.nvim_win_close(self.fzf_winid, {force=true})
  end
  if vim.api.nvim_buf_is_valid(self.fzf_bufnr) then
    vim.api.nvim_buf_delete(self.fzf_bufnr, {force=true})
  end
  if vim.api.nvim_win_is_valid(self.src_winid) then
    vim.api.nvim_set_current_win(self.src_winid)
  end
  self.closing = nil
  _self = nil
end

function FzfWin.win_leave()
  local self = _self
  if self._previewer and self._previewer.win_leave then
    self._previewer:win_leave()
  end
  if not self or self.closing then return end
  _self:close()
end

function FzfWin:update_scrollbar()
  local border_winid = self.border_winid
  local preview_winid = self.preview_winid
  local border_chars = strip_border_highlights(self.winopts.border)
  local scrollchar = self.winopts.scrollchar
  local buf = api.nvim_win_get_buf(preview_winid)
  local border_buf = api.nvim_win_get_buf(border_winid)
  local line_count = api.nvim_buf_line_count(buf)

  local win_info = fn.getwininfo(preview_winid)[1]
  local topline, height = win_info.topline, win_info.height

  local bar_size = math.min(height, math.ceil(height * height / line_count))

  local bar_pos = math.ceil(height * topline / line_count)
  if bar_pos + bar_size > height then
      bar_pos = height - bar_size + 1
  end

  -- only accept a string
  if not scrollchar or type(scrollchar) ~= 'string' then
    scrollchar = '█'
  end

  local lines = api.nvim_buf_get_lines(border_buf, 1, -2, true)
  for i = 1, #lines do
    local bar_char
    if i >= bar_pos and i < bar_pos + bar_size then
      bar_char = scrollchar
    else
      bar_char = border_chars[4]
    end
    local line = lines[i]
    lines[i] = fn.strcharpart(line, 0, fn.strwidth(line) - 1) .. bar_char
  end
  api.nvim_buf_set_lines(border_buf, 1, -2, 0, lines)
end

function FzfWin:update_title(title)
  self:update_border_buf()
  local right_pad = 7
  local border_buf = api.nvim_win_get_buf(self.border_winid)
  local top = api.nvim_buf_get_lines(border_buf, 0, 1, 0)[1]
  local width = fn.strwidth(top)
  if #title > width-right_pad then
    title = title:sub(1, width-right_pad) .. " "
  end
  local prefix = fn.strcharpart(top, 0, 3)
  local suffix = fn.strcharpart(top, fn.strwidth(title) + 3, fn.strwidth(top))
  title = ('%s%s%s'):format(prefix, title, suffix)
  api.nvim_buf_set_lines(border_buf, 0, 1, 1, {title})
end

return FzfWin
