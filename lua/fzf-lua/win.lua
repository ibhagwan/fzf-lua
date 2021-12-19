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

function FzfWin:setup_keybinds()
  if not self:validate() then return end
  if not self.keymap or not self.keymap.builtin then return end
  -- find the toggle_preview
  if self.keymap.fzf then
    for k, v in pairs(self.keymap.fzf) do
      if v == 'toggle-preview' then
        self._fzf_toggle_prev_bind = utils.fzf_bind_to_neovim(k)
      end
    end
  end
  local keymap_tbl = {
    ['toggle-fullscreen']   = { module = 'win', fnc = 'toggle_fullscreen()' },
  }
  if self.previewer_is_builtin then
    -- These maps are only valid for the builtin previewer
    keymap_tbl = vim.tbl_deep_extend("keep", keymap_tbl, {
      ['toggle-preview']      = { module = 'win', fnc = 'toggle_preview()' },
      ['toggle-preview-wrap'] = { module = 'win', fnc = 'toggle_preview_wrap()' },
      ['toggle-preview-cw']   = { module = 'win', fnc = 'toggle_preview_cw(1)' },
      ['toggle-preview-ccw']  = { module = 'win', fnc = 'toggle_preview_cw(-1)' },
      ['preview-page-up']     = { module = 'win', fnc = 'preview_scroll(-1)' },
      ['preview-page-down']   = { module = 'win', fnc = 'preview_scroll(1)' },
      ['preview-page-reset']  = { module = 'win', fnc = 'preview_scroll(0)' },
    })
  end
  local function funcref_str(keymap)
    return ([[<Cmd>lua require('fzf-lua.%s').%s<CR>]]):format(keymap.module, keymap.fnc)
  end
  for key, action in pairs(self.keymap.builtin) do
    local keymap = keymap_tbl[action]
    if keymap and not vim.tbl_isempty(keymap) and action ~= false then
      api.nvim_buf_set_keymap(self.fzf_bufnr, 't', key,
        funcref_str(keymap), {nowait = true, noremap = true})
    end
  end
end

local generate_layout = function(winopts)
  local row, col = winopts.row, winopts.col
  local height, width = winopts.height, winopts.width
  local preview_pos = winopts.preview_pos
  local preview_size = winopts.preview_size
  local prev_row, prev_col = row+1, col+1
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
        prev_width = prev_width - 2
        prev_height = prev_height - 1
        if vert_split then
          prev_col = 1
        else
          prev_col = prev_col - 1
        end
      else
        anchor = 'SW'
        prev_row = row - 1
      end
    else
      anchor = 'NW'
      if winopts.split then
        prev_col = 1
        prev_row = height + padding
        prev_height = prev_height - 1
        prev_width = prev_width - 2
      else
        prev_row = row + height + 3
      end
    end
  elseif preview_pos == 'left' or preview_pos == 'right' then
    prev_height = height
    prev_width = utils.round(width * preview_size/100)
    width = width - prev_width - 2
    if preview_pos == 'left' then
      anchor = 'NE'
      col = col + prev_width + 2
      prev_col = col - 1
      if winopts.split then
        prev_row = 1
        prev_width = prev_width - 1
        prev_height = prev_height - padding
        if vert_split then
          anchor = 'NW'
          prev_col = 1
        else
          prev_col = col - 3
        end
      end
    else
      anchor = 'NW'
      if winopts.split then
        prev_row = 1
        prev_col = width + 4
        prev_width = prev_width - 3
        prev_height = prev_height - padding
      else
        prev_col = col + width + 3
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

local strip_borderchars_hl = function(border)
  local default = nil
  if type(border) == 'string' then
    default = config.globals.winopts._borderchars[border]
  end
  if not default then
    default = config.globals.winopts._borderchars['rounded']
  end
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

local normalize_winopts = function(o)
  -- make a local copy of opts so we
  -- don't pollute the user's options
  local opts = o or {}
  opts.winopts = vim.tbl_deep_extend("keep", opts.winopts or {}, config.globals.winopts)
  opts.winopts_fn = opts.winopts_fn or config.globals.winopts_fn
  opts.winopts_raw = opts.winopts_raw or config.globals.winopts_raw

  local winopts = utils.tbl_deep_clone(opts.winopts)

  if type(opts.winopts_fn) == "function" then
    winopts = vim.tbl_deep_extend("force", winopts, opts.winopts_fn())
  end
  if type(opts.winopts_raw) == "function" then
    winopts = vim.tbl_deep_extend("force", winopts, opts.winopts_raw())
  end

  local max_width = vim.o.columns-2
  local max_height = vim.o.lines-vim.o.cmdheight-2
  winopts.width = math.min(max_width, winopts.width)
  winopts.height = math.min(max_height, winopts.height)
  if not winopts.height or winopts.height <= 1 then
    winopts.height = math.floor(max_height * winopts.height)
  end
  if not winopts.width or winopts.width <= 1 then
    winopts.width = math.floor(max_width * winopts.width)
  end
  if not winopts.row or winopts.row < 1 then
    winopts.row = math.floor((vim.o.lines - winopts.height) * winopts.row)
  end
  if not winopts.col or winopts.col < 1 then
    winopts.col = math.floor((vim.o.columns - winopts.width) * winopts.col)
  end
  winopts.col = math.min(winopts.col, max_width-winopts.width)
  winopts.row = math.min(winopts.row, max_height-winopts.height)

  -- normalize border option for nvim_open_win()
  if not winopts.border or winopts.border == true then
    winopts.border = 'rounded'
  elseif winopts.border == false then
    winopts.border = 'none'
  end

  -- We only allow 'none|single|double|rounded'
  if type(winopts.border) == 'string' then
    winopts.border = config.globals.winopts._borderchars[winopts.border] or
      config.globals.winopts._borderchars['rounded']
  end

  -- Store a version of borderchars with no highlights
  -- to be used in the border drawing functions
  winopts.nohl_borderchars = strip_borderchars_hl(winopts.border)

  -- parse preview options
  local preview
  if winopts.preview.layout == "horizontal" or
     winopts.preview.layout == "flex" and
       vim.o.columns > winopts.preview.flip_columns then
    preview = winopts.preview.horizontal
  else
    preview = winopts.preview.vertical
  end

  -- builtin previewer params
  winopts.preview_pos = preview:match("[^:]+") or 'right'
  winopts.preview_size = tonumber(preview:match(":(%d+)%%")) or 50

  return winopts
end

function FzfWin:reset_win_highlights(win, is_border)
  local hl = ("Normal:%s,FloatBorder:%s"):format(
    self.winopts.hl.normal, self.winopts.hl.border)
  if self._previewer and self.winopts.hl.cursorline then
    hl = hl .. (",CursorLine:%s"):format(self.winopts.hl.cursorline)
  end
  if is_border then
    -- our border is manuually drawn so we need
    -- to replace Normal with the border color
    hl = ("Normal:%s"):format(self.winopts.hl.border)
  end
  vim.api.nvim_win_set_option(win, 'winhighlight', hl)
end

function FzfWin:check_exit_status(exit_code)
  if not self:validate() then return end
  if not exit_code or (exit_code ~=0 and exit_code ~= 130) then
    local lines = vim.api.nvim_buf_get_lines(self.fzf_bufnr, 0, 1, false)
    -- this can happen before nvim-fzf returned exit code (PR #36)
    if not exit_code and (not lines or #lines[1]==0) then return end
    utils.warn(("fzf error %s: %s")
      :format(exit_code or "<null>",
        lines and #lines[1]>0 and lines[1] or "<null>"))
  end
end

function FzfWin:_set_autoclose(autoclose)
  if autoclose ~= nil then
    self._autoclose = autoclose
  else
    self._autoclose = true
  end
  return self._autoclose
end

function FzfWin.set_autoclose(autoclose)
  if not _self then return nil end
  return _self:_set_autoclose(autoclose)
end

function FzfWin.autoclose()
  if not _self then return nil end
  return _self._autoclose
end

local function opt_matches(opts, key, str)
  local opt = opts.winopts.preview[key] or config.globals.winopts.preview[key]
  return opt and opt:match(str)
end

function FzfWin:new(o)
  if _self then
    -- utils.warn("Please close fzf-lua before starting a new instance")
    _self._reuse = true
    return _self
  end
  o = o or {}
  self = setmetatable({}, { __index = self })
  self.winopts = normalize_winopts(o)
  self.fullscreen = self.winopts.fullscreen
  self.preview_wrap = not opt_matches(o, 'wrap', 'nowrap')
  self.preview_hidden = not opt_matches(o, 'hidden', 'nohidden')
  self.preview_border = not opt_matches(o, 'border', 'noborder')
  self.keymap = o.keymap
  self.previewer = o.previewer
  self.previewer_type = o.previewer_type
  self._orphaned_bufs = {}
  self:_set_autoclose(o.autoclose)
  _self = self
  return self
end

function FzfWin:attach_previewer(previewer)
  -- clear the previous previewer if existed
  if self._previewer and self._previewer.close then
    self._previewer:close()
  end
  if self._previewer and self._previewer.win_leave then
    self._previewer:win_leave()
  end
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
  if preview_pos == 'down' or preview_pos == 'up' then
    width_diff = vim.o.columns - border_winopts.width
    if preview_pos == 'down' then
      height_diff = vim.o.lines - border_winopts.row - border_winopts.height - vim.o.cmdheight
    elseif preview_pos == 'up' then
      height_diff = border_winopts.row - border_winopts.height
    end
    border_winopts.col = 0
    prev_winopts.col = border_winopts.col + 1
  elseif preview_pos == 'left' or preview_pos == 'right' then
    height_diff = vim.o.lines - border_winopts.height - vim.o.cmdheight
    if preview_pos == 'left' then
      border_winopts.col = border_winopts.col - 1
      prev_winopts.col = prev_winopts.col - 1
      width_diff = border_winopts.col - border_winopts.width
    elseif preview_pos == 'right' then
      width_diff = vim.o.columns - border_winopts.col - border_winopts.width
    end
    border_winopts.row = 0
    prev_winopts.row = border_winopts.row + 1
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

    -- we cannot use relative with floating windows due to:
    -- https://github.com/neovim/neovim/pull/14770
    -- only use relative when using splits
    local winopts = {relative = 'editor', focusable = false, style = 'minimal'}
    if self.winopts.split then
      winopts.relative = 'win'
    end
    local preview_opts = vim.tbl_extend('force', winopts, {
        focusable = true,
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
  return not self.closing
    and self.preview_winid and self.preview_winid > 0
    and api.nvim_win_is_valid(self.preview_winid)
    and self.border_winid and self.border_winid > 0
    and api.nvim_win_is_valid(self.border_winid)
end

function FzfWin:preview_winids()
    return self.preview_winid, self.border_winid
end

function FzfWin:update_border_buf()
  local border_buf = self.border_buf
  local border_winopts = self.border_winopts
  local borderchars = self.winopts.nohl_borderchars
  local width, height = border_winopts.width, border_winopts.height
  local top = borderchars[1] .. borderchars[2]:rep(width - 2) .. borderchars[3]
  local mid = borderchars[8] .. (' '):rep(width - 2) .. borderchars[4]
  local bot = borderchars[7] .. borderchars[6]:rep(width - 2) .. borderchars[5]
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
  if not self.previewer_is_builtin or self.preview_hidden then return end

  self.prev_winopts, self.border_winopts = self:preview_layout()
  if vim.tbl_isempty(self.prev_winopts) or vim.tbl_isempty(self.border_winopts) then
      return -1, -1
  end

  if self.fullscreen then
    self.prev_winopts, self.border_winopts =
      self:fs_preview_layout(self.fullscreen)
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

function FzfWin:fs_fzf_layout(fs, winopts)
  if not fs or self.winopts.split then
    return winopts
  end

  if not self.previewer_is_builtin or self.preview_hidden then
    -- fzf previewer, expand to fullscreen
    winopts.col = 0
    winopts.row = 0
    winopts.width = vim.o.columns
    winopts.height = vim.o.lines - vim.o.cmdheight - 2
  else
    local preview_pos = self.winopts.preview_pos
    if preview_pos == 'down' or preview_pos == 'up' then
      winopts.col = 0
      winopts.width = vim.o.columns
      if preview_pos == 'down' then
        winopts.height = winopts.height + winopts.row
        winopts.row = 0
      elseif preview_pos == 'up' then
        winopts.height = winopts.height +
          (vim.o.lines-winopts.row-winopts.height-vim.o.cmdheight-2)
      end
    elseif preview_pos == 'left' or preview_pos == 'right'then
      winopts.row = 0
      winopts.height = vim.o.lines - vim.o.cmdheight - 2
      if preview_pos == 'right' then
        winopts.width = winopts.width + winopts.col
        winopts.col = 0
      elseif preview_pos == 'left' then
        winopts.width = winopts.width + (vim.o.columns-winopts.col-winopts.width-1)
      end
    end
  end

  return winopts
end

function FzfWin:redraw()
    if self.winopts.split then return end
    local hidden = self._previewer and self.preview_hidden
    local relative = self.winopts.relative or 'editor'
    local columns, lines = vim.o.columns, vim.o.lines
    if relative == 'win' then
      columns, lines = vim.api.nvim_win_get_width(0), vim.api.nvim_win_get_height(0)
    end

    -- must use clone or fullscreen overrides our values
    local winopts = utils.tbl_deep_clone(self.winopts)
    if self.layout and not hidden then
      winopts = utils.tbl_deep_clone(self.layout.fzf)
    end
    if self.fullscreen then winopts = self:fs_fzf_layout(self.fullscreen, winopts) end

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
      -- save 'cursorline' setting prior to opening the popup
      local cursorline = vim.o.cursorline
      self.fzf_bufnr = vim.api.nvim_create_buf(false, true)
      self.fzf_winid = vim.api.nvim_open_win(self.fzf_bufnr, true, win_opts)
      -- `:help nvim_open_win`
      -- 'minimal' sets 'nocursorline', normally this shouldn't
      -- be an issue but for some reason this is affecting opening
      -- buffers in new splits and causes them to open with
      -- 'nocursorline', see discussion in #254
      if vim.o.cursorline ~= cursorline then
        vim.o.cursorline = cursorline
      end
    end
end

function FzfWin:set_winleave_autocmd()
  vim.cmd("augroup FzfLua")
  vim.cmd("au!")
  vim.cmd(('au WinLeave <buffer> %s'):format(
    [[lua require('fzf-lua.win').win_leave()]]))
  vim.cmd("augroup END")
end

function FzfWin:set_tmp_buffer()
  if not self:validate() then return end
  local tmp_buf = api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(self.fzf_winid, tmp_buf)
  self:set_winleave_autocmd()
  -- closing the buffer here causes the win to close
  -- shouldn't happen since the win is already associated
  -- with tmp_buf... use this table instead
  table.insert(self._orphaned_bufs, self.fzf_bufnr)
  self.fzf_bufnr = tmp_buf
  -- since we have the cusrorline workaround from
  -- issue #254 resume shows an ugly cursorline
  -- remove it, nvim_win API is better than vim.wo?
  -- vim.wo[self.fzf_winid].cursorline = false
  vim.api.nvim_win_set_option(self.fzf_winid, 'cursorline', false)
  return self.fzf_bufnr
end

function FzfWin:create()
  if self._reuse then
    -- we can't reuse the fzf term buffer
    -- create a new tmp buffer for the fzf win
    self:set_tmp_buffer()
    self:setup_keybinds()
    return
  end

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
  self:set_winleave_autocmd()

  self:reset_win_highlights(self.fzf_winid)

  if self.winopts.on_create and
      type(self.winopts.on_create) == 'function' then
    self.winopts.on_create()
  end

  -- create or redraw the preview win
  self:redraw_preview()

  -- setup the keybinds
  self:setup_keybinds()

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
  if self.border_winid and vim.api.nvim_win_is_valid(self.border_winid) then
    api.nvim_win_close(self.border_winid, true)
  end
  if self.border_buf and vim.api.nvim_buf_is_valid(self.border_buf) then
    vim.api.nvim_buf_delete(self.border_buf, {force=true})
  end
  if self.preview_winid and vim.api.nvim_win_is_valid(self.preview_winid) then
    api.nvim_win_close(self.preview_winid, true)
  end
  if self._sbuf1 and vim.api.nvim_buf_is_valid(self._sbuf1) then
    vim.api.nvim_buf_delete(self._sbuf1, {force=true})
  end
  if self._swin1 and vim.api.nvim_win_is_valid(self._swin1) then
    api.nvim_win_close(self._swin1, true)
  end
  if self._sbuf2 and vim.api.nvim_buf_is_valid(self._sbuf2) then
    vim.api.nvim_buf_delete(self._sbuf2, {force=true})
  end
  if self._swin2 and vim.api.nvim_win_is_valid(self._swin2) then
    api.nvim_win_close(self._swin2, true)
  end
  self._sbuf1, self._sbuf2, self._swin1, self._swin2 = nil, nil, nil, nil
  self.border_buf = nil
  self.border_winid = nil
  self.preview_winid = nil
end

function FzfWin:close()
  -- prevents race condition with 'win_leave'
  self.closing = true
  self:close_preview()
  if self.fzf_winid and vim.api.nvim_win_is_valid(self.fzf_winid) then
    vim.api.nvim_win_close(self.fzf_winid, {force=true})
  end
  if self.fzf_bufnr and vim.api.nvim_buf_is_valid(self.fzf_bufnr) then
    vim.api.nvim_buf_delete(self.fzf_bufnr, {force=true})
  end
  if self._orphaned_bufs then
    for _, b in ipairs(self._orphaned_bufs) do
      if vim.api.nvim_buf_is_valid(b) then
        vim.api.nvim_buf_delete(b, {force=true})
      end
    end
  end
  self.closing = nil
  self._reuse = nil
  self._orphaned_bufs = nil
  _self = nil
end

function FzfWin.win_leave()
  local self = _self
  if not self then return end
  if self._previewer and self._previewer.win_leave then
    self._previewer:win_leave()
  end
  if not self or self.closing then return end
  _self:close()
end

function FzfWin:clear_border_highlights()
  if self.border_winid and vim.api.nvim_win_is_valid(self.border_winid) then
    vim.fn.clearmatches(self.border_winid)
  end
end

function FzfWin:set_title_hl()
  if self.winopts.hl.title and self._title_len and self._title_len>0 then
    vim.api.nvim_win_call(self.border_winid, function()
      fn.matchaddpos(self.winopts.hl.title, {{1, 9, self._title_len+1}}, 11)
    end)
  end
end

function FzfWin:update_scrollbar_border(o)

  -- do not display on files that are fully contained
  if o.bar_height >= o.line_count then return end

  local borderchars = self.winopts.nohl_borderchars
  local scrollchars = self.winopts.preview.scrollchars

  -- bar_offset starts at 0, first line is 1
  o.bar_offset = o.bar_offset+1

  -- backward compatibility before 'scrollchar' was a table
  if type(self.winopts.preview.scrollchar) == 'string' and
    #self.winopts.preview.scrollchar > 0 then
    scrollchars[1] = self.winopts.preview.scrollchar
  end
  for i=1,2 do
    if not scrollchars[i] or #scrollchars[i]==0 then
      scrollchars[i] = borderchars[4]
    end
  end

  -- matchaddpos() can't handle more than 8 items at once
  local add_to_tbl = function(tbl, item)
    local len = utils.tbl_length(tbl)
    if len==0 or utils.tbl_length(tbl[len])==8 then
      table.insert(tbl, {})
      len = len+1
    end
    table.insert(tbl[len], item)
  end

  local full, empty = {}, {}
  local lines = api.nvim_buf_get_lines(self.border_buf, 1, -2, true)
  for i = 1, #lines do
    local line, linew = lines[i], fn.strwidth(lines[i])
    local bar_char
    if i >= o.bar_offset and i < o.bar_offset + o.bar_height then
      bar_char = scrollchars[1]
      add_to_tbl(full, {i+1, linew+2, 1})
    else
      bar_char = scrollchars[2]
      add_to_tbl(empty, {i+1, linew+2, 1})
    end
    lines[i] = fn.strcharpart(line, 0, linew - 1) .. bar_char
  end
  api.nvim_buf_set_lines(self.border_buf, 1, -2, 0, lines)
  -- border highlights
  if self.winopts.hl.scrollbar_f or self.winopts.hl.scrollbar_e then
    vim.api.nvim_win_call(self.border_winid, function()
      if self.winopts.hl.scrollbar_f then
        for i=1,#full do
          fn.matchaddpos(self.winopts.hl.scrollbar_f, full[i], 11)
        end
      end
      if self.winopts.hl.scrollbar_e then
        for i=1,#empty do
          fn.matchaddpos(self.winopts.hl.scrollbar_e, empty[i], 11)
        end
      end
    end)
  end
end

local function ensure_tmp_buf(bufnr)
  if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
    return bufnr
  end
  bufnr = api.nvim_create_buf(false, true)
  -- running nvim with `-M` will reset modifiable's default value to false
  vim.bo[bufnr].modifiable = true
  vim.bo[bufnr].bufhidden = 'wipe'
  return bufnr
end

function FzfWin:hide_scrollbar()
  if self._swin1 and vim.api.nvim_win_is_valid(self._swin1) then
    vim.api.nvim_win_hide(self._swin1)
    self._swin1 = nil
  end
  if self._swin2 and vim.api.nvim_win_is_valid(self._swin2) then
    vim.api.nvim_win_hide(self._swin2)
    self._swin2 = nil
  end
end

function FzfWin:update_scrollbar_float(o)
  -- do not display on files that are fully contained
  if o.bar_height >= o.line_count then
    self:hide_scrollbar()
  else
    local info = o.wininfo
    local style1 = {}
    style1.relative = 'editor'
    style1.style = 'minimal'
    style1.width = 1
    style1.height = info.height
    style1.row = info.winrow - 1
    style1.col = info.wincol + info.width +
      (tonumber(self.winopts.preview.scrolloff) or -2)
    style1.zindex = info.zindex or 998
    if self._swin1 and vim.api.nvim_win_is_valid(self._swin1) then
      vim.api.nvim_win_set_config(self._swin1, style1)
    else
      style1.noautocmd = true
      self._sbuf1 = ensure_tmp_buf(self._sbuf1)
      self._swin1 = vim.api.nvim_open_win(self._sbuf1, false, style1)
      local hl = self.winopts.hl.scrollbar_e or 'PmenuSbar'
      vim.api.nvim_win_set_option(self._swin1, 'winhighlight',
        ('Normal:%s,NormalNC:%s,NormalFloat:%s'):format(hl, hl, hl))
    end
    local style2 = utils.tbl_deep_clone(style1)
    style2.height = o.bar_height
    style2.row = style1.row + o.bar_offset
    style2.zindex = style1.zindex + 1
    if self._swin2 and vim.api.nvim_win_is_valid(self._swin2) then
      vim.api.nvim_win_set_config(self._swin2, style2)
    else
      style2.noautocmd = true
      self._sbuf2 = ensure_tmp_buf(self._sbuf2)
      self._swin2 = vim.api.nvim_open_win(self._sbuf2, false, style2)
      local hl = self.winopts.hl.scrollbar_f or 'PmenuThumb'
      vim.api.nvim_win_set_option(self._swin2, 'winhighlight',
        ('Normal:%s,NormalNC:%s,NormalFloat:%s'):format(hl, hl, hl))
    end
  end
end

function FzfWin:update_scrollbar()
  if not self.winopts.preview.scrollbar
     or self.winopts.preview.scrollbar == 'none'
     or not self:validate_preview() then
    return
   end

  local buf = api.nvim_win_get_buf(self.preview_winid)

  local o = {}
  o.wininfo = fn.getwininfo(self.preview_winid)[1]
  o.line_count = api.nvim_buf_line_count(buf)

  local topline, height = o.wininfo.topline, o.wininfo.height
  o.bar_height = math.min(height, math.ceil(height * height / o.line_count))
  o.bar_offset = math.min(height - o.bar_height, math.floor(height * topline / o.line_count))

  -- reset highlights before we move the scrollbar
  self:clear_border_highlights()
  self:set_title_hl()

  if self.winopts.preview.scrollbar == 'float' then
    self:update_scrollbar_float(o)
  else
    self:update_scrollbar_border(o)
  end
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
  -- save for set_title_hl
  self._title_len = #title
  local prefix = fn.strcharpart(top, 0, 3)
  local suffix = fn.strcharpart(top, fn.strwidth(title) + 3, fn.strwidth(top))
  title = ('%s%s%s'):format(prefix, title, suffix)
  api.nvim_buf_set_lines(border_buf, 0, 1, 1, {title})
  self:set_title_hl()
end

-- keybind methods below
function FzfWin.toggle_fullscreen()
  if not _self or _self.winopts.split then return end
  local self = _self
  self.fullscreen = not self.fullscreen
  self:hide_scrollbar()
  if self and self:validate() then
    self:redraw()
  end
  if self and self:validate_preview() then
    self:redraw_preview()
  end
end

function FzfWin.toggle_preview()
  if not _self then return end
  local self = _self
  self.preview_hidden = not self.preview_hidden
  if self.winopts.split and self._fzf_toggle_prev_bind then
    utils.feed_keys_termcodes(self._fzf_toggle_prev_bind)
  end
  if self.preview_hidden and self:validate_preview() then
    self:close_preview()
    self:redraw()
  elseif not self.preview_hidden then
    self:redraw()
    self:redraw_preview()
    if self._previewer and self._previewer.display_last_entry then
      self._previewer:display_last_entry()
    end
  end
  -- close_preview() calls FzfWin:close()
  -- which will clear out our singleton so
  -- we must save it again to call redraw
  _self = self
end

function FzfWin.toggle_preview_wrap()
  if not _self then return end
  local self = _self
  self.preview_wrap = not self.preview_wrap
  if self and self:validate_preview() then
    api.nvim_win_set_option(self.preview_winid, 'wrap', self.preview_wrap)
  end
end

function FzfWin.toggle_preview_cw(direction)
  if not _self or _self.winopts.split then return end
  local self = _self
  local pos = { 'up', 'right', 'down', 'left' }
  local idx
  for i=1,#pos do
    if pos[i] == self.winopts.preview_pos then
      idx = i
      break
    end
  end
  if not idx then return end
  local newidx = direction>0 and idx+1 or idx-1
  if newidx<1 then newidx = #pos end
  if newidx>#pos then newidx = 1 end
  self.winopts.preview_pos = pos[newidx]
  self.layout = generate_layout(self.winopts)
  self:close_preview()
  self:redraw()
  self:redraw_preview()
  if self._previewer and self._previewer.display_last_entry then
    self._previewer:display_last_entry()
  end
end

function FzfWin.preview_scroll(direction)
  if not _self then return end
  local self = _self
  if self:validate_preview()
    and self._previewer
    and self._previewer.scroll then
    self._previewer:scroll(direction)
  end
end

return FzfWin
