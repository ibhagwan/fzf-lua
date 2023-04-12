local utils = require "fzf-lua.utils"
local config = require "fzf-lua.config"
local actions = require "fzf-lua.actions"

local api = vim.api
local fn = vim.fn

local __HAS_NVIM_09 = vim.fn.has("nvim-0.9") == 1

local FzfWin = {}

-- singleton instance used in win_leave
local _self = nil

function FzfWin.__SELF()
  return _self
end

setmetatable(FzfWin, {
  __call = function(cls, ...)
    return cls:new(...)
  end,
})

local _preview_keymaps = {
  ["toggle-preview"]      = { module = "win", fnc = "toggle_preview()" },
  ["toggle-preview-wrap"] = { module = "win", fnc = "toggle_preview_wrap()" },
  ["toggle-preview-cw"]   = { module = "win", fnc = "toggle_preview_cw(1)" },
  ["toggle-preview-ccw"]  = { module = "win", fnc = "toggle_preview_cw(-1)" },
  ["preview-page-up"]     = { module = "win", fnc = "preview_scroll(-1)" },
  ["preview-page-down"]   = { module = "win", fnc = "preview_scroll(1)" },
  ["preview-page-reset"]  = { module = "win", fnc = "preview_scroll(0)" },
}

function FzfWin:setup_keybinds()
  if not self:validate() then return end
  if not self.keymap or not self.keymap.builtin then return end
  -- find the toggle_preview
  if self.keymap.fzf then
    for k, v in pairs(self.keymap.fzf) do
      if v == "toggle-preview" then
        self._fzf_toggle_prev_bind = utils.fzf_bind_to_neovim(k)
      end
    end
  end
  local keymap_tbl = {
    ["toggle-help"]       = { module = "win", fnc = "toggle_help()" },
    ["toggle-fullscreen"] = { module = "win", fnc = "toggle_fullscreen()" },
  }
  if self.previewer_is_builtin then
    -- These maps are only valid for the builtin previewer
    keymap_tbl = vim.tbl_deep_extend("keep", keymap_tbl, _preview_keymaps)
  end
  local function funcref_str(keymap)
    return ([[<Cmd>lua require('fzf-lua.%s').%s<CR>]]):format(keymap.module, keymap.fnc)
  end

  for key, action in pairs(self.keymap.builtin) do
    local keymap = keymap_tbl[action]
    if keymap and not vim.tbl_isempty(keymap) and action ~= false then
      utils.keymap_set("t", key, funcref_str(keymap),
        { nowait = true, buffer = self.fzf_bufnr })
    end
  end

  -- If the user did not override the Esc action ensure it's
  -- not bound to anything else such as `<C-\><C-n>` (#663)
  if self.actions["esc"] == actions.dummy_abort then
    utils.keymap_set("t", "<Esc>", "<Esc>", { buffer = 0 })
  end
end

function FzfWin:generate_layout(winopts)
  local row, col = winopts.row, winopts.col
  local height, width = winopts.height, winopts.width
  local signcol_width = winopts.signcol_width or 0
  local preview_pos = winopts.preview_pos
  local preview_size = winopts.preview_size
  local prev_row, prev_col = row + 1, col + 1
  local prev_height, prev_width
  local padding = 2
  local anchor
  local vert_split = winopts.split and winopts.split:match("vnew") ~= nil
  if preview_pos == "down" or preview_pos == "up" then
    height = height - padding
    prev_width = width
    prev_height = utils.round(height * preview_size / 100, 0.6)
    height = height - prev_height
    if preview_pos == "up" then
      row = row + prev_height + padding
      if winopts.split then
        anchor = "NW"
        prev_row = 1
        prev_col = 1
        prev_width = prev_width - 2
        prev_height = prev_height - 1
      else
        anchor = "SW"
        prev_row = row - 1
      end
    else
      anchor = "NW"
      if winopts.split then
        prev_col = 1
        prev_row = height + padding
        prev_height = prev_height - 1
        prev_width = prev_width - 2
      else
        prev_row = row + height + 3
      end
    end
  elseif preview_pos == "left" or preview_pos == "right" then
    prev_height = height
    prev_width = utils.round(width * preview_size / 100)
    width = width - prev_width - 2
    if preview_pos == "left" then
      anchor = "NE"
      col = col + prev_width + 2
      prev_col = col - 1
      if winopts.split then
        prev_row = 1
        prev_width = prev_width - 1 - signcol_width
        prev_height = prev_height - padding
        if vert_split then
          anchor = "NW"
          prev_col = 1
        else
          prev_col = col - 3 - signcol_width
        end
      end
    else
      anchor = "NW"
      if winopts.split then
        prev_row = 1
        prev_col = width + 4 - signcol_width
        prev_width = prev_width - 3 + signcol_width
        prev_height = prev_height - padding
      else
        prev_col = col + width + 3
      end
    end
  end
  return {
    fzf = {
      row = row,
      col = col,
      height = height,
      width = width,
    },
    preview = {
      anchor = anchor,
      row = prev_row,
      col = prev_col,
      height = prev_height,
      width = prev_width,
    }
  }
end

local strip_borderchars_hl = function(border)
  local default = nil
  if type(border) == "string" then
    default = config.globals.winopts._borderchars[border]
  end
  if not default then
    default = config.globals.winopts._borderchars["rounded"]
  end
  if not border or type(border) ~= "table" or #border < 8 then
    return default
  end
  local borderchars = {}
  for i = 1, 8 do
    if type(border[i]) == "string" then
      table.insert(borderchars, #border[i] > 0 and border[i] or " ")
    elseif type(border[i]) == "table" and type(border[i][1]) == "string" then
      -- can happen when border chars contains a highlight, i.e:
      -- border = { {'╭', 'NormalFloat'}, {'─', 'NormalFloat'}, ... }
      table.insert(borderchars, #border[i][1] > 0 and border[i][1] or " ")
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

  -- overwrite highlights if supplied by the caller/provider setup
  winopts.__hl = vim.tbl_deep_extend("force", winopts.__hl, winopts.hl or {})

  local max_width = vim.o.columns - 2
  local max_height = vim.o.lines - vim.o.cmdheight - 2
  winopts.width = math.min(max_width, winopts.width)
  winopts.height = math.min(max_height, winopts.height)
  if not winopts.height or winopts.height <= 1 then
    winopts.height = math.floor(max_height * winopts.height)
  end
  if not winopts.width or winopts.width <= 1 then
    winopts.width = math.floor(max_width * winopts.width)
  end
  if winopts.relative == "cursor" then
    -- convert cursor relative to absolute ('editor'),
    -- this solves the preview positioning seamlessly
    local pos = vim.api.nvim_win_get_cursor(0)
    local screenpos = vim.fn.screenpos(0, pos[1], pos[2])
    winopts.row = math.floor((winopts.row or 0) + screenpos.row - 1)
    winopts.col = math.floor((winopts.col or 0) + screenpos.col - 1)
    winopts.relative = nil
  else
    if not winopts.row or winopts.row <= 1 then
      winopts.row = math.floor((vim.o.lines - winopts.height) * winopts.row)
    end
    if not winopts.col or winopts.col <= 1 then
      winopts.col = math.floor((vim.o.columns - winopts.width) * winopts.col)
    end
    winopts.col = math.min(winopts.col, max_width - winopts.width)
    winopts.row = math.min(winopts.row, max_height - winopts.height)
  end

  -- normalize border option for nvim_open_win()
  if winopts.border == false then
    winopts.border = "none"
  elseif not winopts.border or winopts.border == true then
    winopts.border = "rounded"
  end

  -- We only allow 'none|single|double|rounded'
  if type(winopts.border) == "string" then
    -- save the original string so we can pass it
    -- to the main fzf window 'nvim_open_win' (#364)
    winopts._border = winopts.border
    winopts.border = config.globals.winopts._borderchars[winopts.border] or
        config.globals.winopts._borderchars["rounded"]
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
  winopts.preview_pos = preview:match("[^:]+") or "right"
  winopts.preview_size = tonumber(preview:match(":(%d+)%%")) or 50

  return winopts
end

function FzfWin:reset_win_highlights(win, is_border)
  local hl = ("Normal:%s,FloatBorder:%s"):format(
    self.winopts.__hl.normal, self.winopts.__hl.border)
  if self._previewer then
    for _, h in ipairs({ "CursorLine", "CursorLineNr" }) do
      if self.winopts.__hl[h:lower()] then
        hl = hl .. (",%s:%s"):format(h, self.winopts.__hl[h:lower()])
      end
    end
  end
  if is_border then
    -- our border is manually drawn so we need
    -- to replace Normal with the border color
    hl = ("Normal:%s"):format(self.winopts.__hl.border)
  end
  vim.api.nvim_win_set_option(win, "winhighlight", hl)
end

function FzfWin:check_exit_status(exit_code)
  if not self:validate() then return end
  -- from 'man fzf':
  --    0      Normal exit
  --    1      No match
  --    2      Error
  --    130    Interrupted with CTRL-C or ESC
  if exit_code ~= 0 and exit_code ~= 130 then
    local lines = vim.api.nvim_buf_get_lines(self.fzf_bufnr, 0, 1, false)
    -- the reason we're not ignoring error 1 is due
    -- to skim returning 1 for unexpected arguments
    -- only warn about there is an actual error msg
    if exit_code ~= 1 or (lines and #lines[1] > 0) then
      utils.warn(("fzf error %s: %s"):format(
        exit_code or "<null>",
        lines and #lines[1] > 0 and lines[1] or "<null>"))
    end
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
  self._o = o
  self = setmetatable({}, { __index = self })
  self.actions = o.actions
  self.winopts = normalize_winopts(o)
  self.fullscreen = self.winopts.fullscreen
  self.preview_wrap = not opt_matches(o, "wrap", "nowrap")
  self.preview_hidden = not opt_matches(o, "hidden", "nohidden")
  self.preview_border = not opt_matches(o, "border", "noborder")
  self.keymap = o.keymap
  self.previewer = o.previewer
  self.prompt = o.prompt or o.fzf_opts["--prompt"]
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
  self.previewer_is_builtin = previewer and type(previewer.display_entry) == "function"
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
  if preview_pos == "down" or preview_pos == "up" then
    width_diff = vim.o.columns - border_winopts.width
    if preview_pos == "down" then
      height_diff = vim.o.lines - border_winopts.row - border_winopts.height - vim.o.cmdheight
    elseif preview_pos == "up" then
      height_diff = border_winopts.row - border_winopts.height
    end
    border_winopts.col = 0
    prev_winopts.col = border_winopts.col + 1
  elseif preview_pos == "left" or preview_pos == "right" then
    height_diff = vim.o.lines - border_winopts.height - vim.o.cmdheight
    if preview_pos == "left" then
      border_winopts.col = border_winopts.col - 1
      prev_winopts.col = prev_winopts.col - 1
      width_diff = border_winopts.col - border_winopts.width
    elseif preview_pos == "right" then
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
    -- unlike floating win popups, split windows inherit the global
    -- 'signcolumn' setting which affects the available width for fzf
    -- 'generate_layout' will then use the sign column available width
    -- to assure a perfect alignment of the builtin previewer window
    -- and the dummy native fzf previewer window border underneath it
    local signcol_width = vim.wo[self.fzf_winid].signcolumn == "no" and 1 or 0
    self.layout = self:generate_layout({
      row = wininfo.winrow,
      col = wininfo.wincol,
      height = wininfo.height,
      width = api.nvim_win_get_width(self.fzf_winid),
      signcol_width = signcol_width,
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
  local winopts = { relative = "editor", focusable = false, style = "minimal" }
  if self.winopts.split then
    winopts.relative = "win"
  end
  local preview_opts = vim.tbl_extend("force", winopts, {
    focusable = true,
    anchor = anchor,
    width = width,
    height = height,
    col = col,
    row = row
  })
  local border_winopts = vim.tbl_extend("force", winopts, {
    anchor = anchor,
    width = width + 2,
    height = height + 2,
    col = anchor:match("W") and col - 1 or col + 1,
    row = anchor:match("N") and row - 1 or row + 1
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
  local mid = borderchars[8] .. (" "):rep(width - 2) .. borderchars[4]
  local bot = borderchars[7] .. borderchars[6]:rep(width - 2) .. borderchars[5]
  local lines = { top }
  for _ = 1, height - 2 do
    table.insert(lines, mid)
  end
  table.insert(lines, bot)
  if not border_buf then
    border_buf = api.nvim_create_buf(false, true)
    -- run nvim with `-M` will reset modifiable's default value to false
    vim.bo[border_buf].modifiable = true
    vim.bo[border_buf].bufhidden = "wipe"
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
    self.prev_winopts, self.border_winopts = self:fs_preview_layout(self.fullscreen)
  end

  if self:validate_preview() then
    self.border_buf = api.nvim_win_get_buf(self.border_winid)
    self:update_border_buf()
    api.nvim_win_set_config(self.border_winid, self.border_winopts)
    api.nvim_win_set_config(self.preview_winid, self.prev_winopts)
    if self._previewer and self._previewer.display_last_entry then
      self._previewer:set_winopts(self.preview_winid)
      self._previewer:display_last_entry()
    end
  else
    local tmp_buf = api.nvim_create_buf(false, true)
    -- No autocmds, can only be sent with 'nvim_open_win'
    self.prev_winopts.noautocmd = true
    self.border_winopts.noautocmd = true
    api.nvim_buf_set_option(tmp_buf, "bufhidden", "wipe")
    self.border_buf = self:update_border_buf()
    self.preview_winid = api.nvim_open_win(tmp_buf, false, self.prev_winopts)
    self.border_winid = api.nvim_open_win(self.border_buf, false, self.border_winopts)
    -- nowrap border or long filenames will mess things up
    api.nvim_win_set_option(self.border_winid, "wrap", false)
    -- Add win local var for the preview|border windows
    api.nvim_win_set_var(self.preview_winid, "fzf_lua_preview", true)
    api.nvim_win_set_var(self.border_winid, "fzf_lua_preview", true)
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
    if preview_pos == "down" or preview_pos == "up" then
      winopts.col = 0
      winopts.width = vim.o.columns
      if preview_pos == "down" then
        winopts.height = winopts.height + winopts.row
        winopts.row = 0
      elseif preview_pos == "up" then
        winopts.height = winopts.height +
            (vim.o.lines - winopts.row - winopts.height - vim.o.cmdheight - 2)
      end
    elseif preview_pos == "left" or preview_pos == "right" then
      winopts.row = 0
      winopts.height = vim.o.lines - vim.o.cmdheight - 2
      if preview_pos == "right" then
        winopts.width = winopts.width + winopts.col
        winopts.col = 0
      elseif preview_pos == "left" then
        winopts.width = winopts.width + (vim.o.columns - winopts.col - winopts.width - 1)
      end
    end
  end

  return winopts
end

function FzfWin:redraw()
  self.winopts = normalize_winopts(self._o)
  if not self.winopts.split and self.previewer_is_builtin then
    self.layout = self:generate_layout(self.winopts)
  end
  if self:validate() then
    self:redraw_main()
  end
  if self:validate_preview() then
    self:redraw_preview()
  end
end

function FzfWin:redraw_main()
  if self.winopts.split then return end
  local hidden = self._previewer
      and self.preview_hidden
      and self._previewer.toggle_behavior ~= "extend"
  local relative = self.winopts.relative or "editor"
  local columns, lines = vim.o.columns, vim.o.lines
  if relative == "win" then
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
    style = "minimal",
    relative = relative,
    border = self.winopts.border,
    title = __HAS_NVIM_09 and self.winopts.title or nil,
    title_pos = __HAS_NVIM_09 and self.winopts.title_pos or nil,
  }
  win_opts.row = winopts.row or math.floor(((lines - win_opts.height) / 2) - 1)
  win_opts.col = winopts.col or math.floor((columns - win_opts.width) / 2)

  -- adjust for borderless main window (#364)
  if self.winopts._border and self.winopts._border == "none" then
    win_opts.border = self.winopts._border
    win_opts.width = win_opts.width + 2
    win_opts.height = win_opts.height + 2
  end

  -- When border chars are empty strings 'nvim_open_win' adjusts
  -- the layout to take all avialable space, we use these to adjust
  -- our main window height to use all available lines (#364)
  if type(win_opts.border) == "table" then
    local function is_empty_str(tbl, arr)
      for _, i in ipairs(arr) do
        if tbl[i] and #tbl[i] > 0 then
          return false
        end
      end
      return true
    end

    win_opts.height = win_opts.height
        + (is_empty_str(win_opts.border, { 2 }) and 1 or 0) -- top border
        + (is_empty_str(win_opts.border, { 6 }) and 1 or 0) -- bottom border
    win_opts.width = win_opts.width
        + (is_empty_str(win_opts.border, { 4 }) and 1 or 0) -- right border
        + (is_empty_str(win_opts.border, { 8 }) and 1 or 0) -- left border
  end

  if self:validate() then
    if self._previewer
        and self._previewer.clear_on_redraw
        and self._previewer.clear_preview_buf then
      self._previewer:clear_preview_buf(true)
      self._previewer:clear_cached_buffers()
    end
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

function FzfWin:set_redraw_autocmd()
  vim.cmd("augroup FzfLua")
  vim.cmd([[au VimResized <buffer> lua require("fzf-lua").redraw()]])
  vim.cmd("augroup END")
end

function FzfWin:set_winleave_autocmd()
  vim.cmd("augroup FzfLua")
  vim.cmd("au!")
  vim.cmd(("au WinLeave <buffer> %s"):format(
    [[lua require('fzf-lua.win').win_leave()]]))
  vim.cmd("augroup END")
end

function FzfWin:set_tmp_buffer()
  if not self:validate() then return end
  local tmp_buf = api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(self.fzf_winid, tmp_buf)
  self:set_winleave_autocmd()
  -- automatically resize fzf window
  self:set_redraw_autocmd()
  -- closing the buffer here causes the win to close
  -- shouldn't happen since the win is already associated
  -- with tmp_buf... use this table instead
  table.insert(self._orphaned_bufs, self.fzf_bufnr)
  self.fzf_bufnr = tmp_buf
  -- since we have the cursorline workaround from
  -- issue #254, resume shows an ugly cursorline.
  -- remove it, nvim_win API is better than vim.wo?
  -- vim.wo[self.fzf_winid].cursorline = false
  vim.api.nvim_win_set_option(self.fzf_winid, "cursorline", false)
  return self.fzf_bufnr
end

function FzfWin:set_style_minimal(winid)
  if not tonumber(winid) or
      not api.nvim_win_is_valid(winid)
  then
    return
  end
  vim.wo[winid].number = false
  vim.wo[winid].relativenumber = false
  vim.wo[winid].cursorline = false
  vim.wo[winid].cursorcolumn = false
  vim.wo[winid].spell = false
  vim.wo[winid].list = false
  vim.wo[winid].signcolumn = "no"
  vim.wo[winid].foldcolumn = "0"
  vim.wo[winid].colorcolumn = ""
end

function FzfWin:create()
  -- When using fzf-tmux we don't need to create windows
  -- as tmux popups will be used instead
  if self._o._is_fzf_tmux then
    return
  end

  if self._reuse then
    -- we can't reuse the fzf term buffer
    -- create a new tmp buffer for the fzf win
    self:set_tmp_buffer()
    self:setup_keybinds()
    -- also recall the user's 'on_create' (#394)
    if self.winopts.on_create and
        type(self.winopts.on_create) == "function" then
      self.winopts.on_create()
    end
    -- not sure why but when using a split and reusing the window,
    -- fzf will not use all the avialable width until 'redraw' is
    -- called resulting in misaligned native and builtin previews
    vim.cmd("redraw")
    return
  end

  if not self.winopts.split and self.previewer_is_builtin then
    self.layout = self:generate_layout(self.winopts)
  end
  -- save sending bufnr/winid
  self.src_bufnr = vim.api.nvim_get_current_buf()
  self.src_winid = vim.api.nvim_get_current_win()

  if self.winopts.split then
    vim.cmd(self.winopts.split)
    self.fzf_bufnr = vim.api.nvim_get_current_buf()
    self.fzf_winid = vim.api.nvim_get_current_win()
    -- match window options with 'nvim_open_win' style:minimal
    self:set_style_minimal(self.fzf_winid)
  else
    -- draw the main window
    self:redraw_main()
  end

  -- verify the preview is closed, this can happen
  -- when running async LSP with 'jump_to_single_result'
  -- should also close issue #105
  -- https://github.com/ibhagwan/fzf-lua/issues/105
  self:set_winleave_autocmd()
  -- automatically resize fzf window
  self:set_redraw_autocmd()

  self:reset_win_highlights(self.fzf_winid)

  if self.winopts.on_create and
      type(self.winopts.on_create) == "function" then
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
    utils.nvim_win_close(self.border_winid, true)
  end
  if self.border_buf and vim.api.nvim_buf_is_valid(self.border_buf) then
    vim.api.nvim_buf_delete(self.border_buf, { force = true })
  end
  if self.preview_winid and vim.api.nvim_win_is_valid(self.preview_winid) then
    utils.nvim_win_close(self.preview_winid, true)
  end
  if self._sbuf1 and vim.api.nvim_buf_is_valid(self._sbuf1) then
    vim.api.nvim_buf_delete(self._sbuf1, { force = true })
  end
  if self._swin1 and vim.api.nvim_win_is_valid(self._swin1) then
    utils.nvim_win_close(self._swin1, true)
  end
  if self._sbuf2 and vim.api.nvim_buf_is_valid(self._sbuf2) then
    vim.api.nvim_buf_delete(self._sbuf2, { force = true })
  end
  if self._swin2 and vim.api.nvim_win_is_valid(self._swin2) then
    utils.nvim_win_close(self._swin2, true)
  end
  self._sbuf1, self._sbuf2, self._swin1, self._swin2 = nil, nil, nil, nil
  self.border_buf = nil
  self.border_winid = nil
  self.preview_winid = nil
end

function FzfWin:close()
  -- prevents race condition with 'win_leave'
  self.closing = true
  self.close_help()
  self:close_preview()
  if self.fzf_winid and vim.api.nvim_win_is_valid(self.fzf_winid) then
    -- run in a pcall due to potential errors while closing the window
    -- Vim(lua):E5108: Error executing lua
    -- experienced while accessing 'vim.b[]' from my statusline code
    pcall(vim.api.nvim_win_close, self.fzf_winid, true)
  end
  if self.fzf_bufnr and vim.api.nvim_buf_is_valid(self.fzf_bufnr) then
    vim.api.nvim_buf_delete(self.fzf_bufnr, { force = true })
  end
  if self._orphaned_bufs then
    for _, b in ipairs(self._orphaned_bufs) do
      if vim.api.nvim_buf_is_valid(b) then
        vim.api.nvim_buf_delete(b, { force = true })
      end
    end
  end
  -- when using `split = "belowright new"` closing the fzf
  -- window may not always return to the correct source win
  -- depending on the user's split configuration (#397)
  if self.winopts and self.winopts.split
      and self.src_winid and self.src_winid > 0
      and self.src_winid ~= vim.api.nvim_get_current_win()
      and vim.api.nvim_win_is_valid(self.src_winid) then
    vim.api.nvim_set_current_win(self.src_winid)
  end
  self.closing = nil
  self._reuse = nil
  self._orphaned_bufs = nil
  _self = nil
  -- clear the main module picker __INFO
  utils.reset_info()
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
  if self.winopts.__hl.title and self._title_len and self._title_len > 0 then
    pcall(vim.api.nvim_win_call, self.border_winid, function()
      fn.matchaddpos(self.winopts.__hl.title, { { 1, self._title_position, self._title_len + 1 } },
        11)
    end)
  end
end

function FzfWin:update_scrollbar_border(o)
  -- do not display on files that are fully contained
  if o.bar_height >= o.line_count then return end

  local borderchars = self.winopts.nohl_borderchars
  local scrollchars = self.winopts.preview.scrollchars

  -- bar_offset starts at 0, first line is 1
  o.bar_offset = o.bar_offset + 1

  -- backward compatibility before 'scrollchar' was a table
  if type(self.winopts.preview.scrollchar) == "string" and
      #self.winopts.preview.scrollchar > 0 then
    scrollchars[1] = self.winopts.preview.scrollchar
  end
  for i = 1, 2 do
    if not scrollchars[i] or #scrollchars[i] == 0 then
      scrollchars[i] = borderchars[4]
    end
  end

  -- matchaddpos() can't handle more than 8 items at once
  local add_to_tbl = function(tbl, item)
    local len = utils.tbl_length(tbl)
    if len == 0 or utils.tbl_length(tbl[len]) == 8 then
      table.insert(tbl, {})
      len = len + 1
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
      add_to_tbl(full, { i + 1, linew + 2, 1 })
    else
      bar_char = scrollchars[2]
      add_to_tbl(empty, { i + 1, linew + 2, 1 })
    end
    lines[i] = fn.strcharpart(line, 0, linew - 1) .. bar_char
  end
  api.nvim_buf_set_lines(self.border_buf, 1, -2, 0, lines)
  -- border highlights
  if self.winopts.__hl.scrollborder_f or self.winopts.__hl.scrollborder_e then
    pcall(vim.api.nvim_win_call, self.border_winid, function()
      if self.winopts.hl.scrollborder_f then
        for i = 1, #full do
          fn.matchaddpos(self.winopts.__hl.scrollborder_f, full[i], 11)
        end
      end
      if self.winopts.__hl.scrollborder_e then
        for i = 1, #empty do
          fn.matchaddpos(self.winopts.__hl.scrollborder_e, empty[i], 11)
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
  vim.bo[bufnr].bufhidden = "wipe"
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
    style1.relative = "editor"
    style1.style = "minimal"
    style1.width = 1
    style1.height = info.height
    style1.row = info.winrow - 1
    style1.col = info.wincol + info.width +
        (tonumber(self.winopts.preview.scrolloff) or -2)
    style1.zindex = info.zindex or 997
    if self._swin1 and vim.api.nvim_win_is_valid(self._swin1) then
      vim.api.nvim_win_set_config(self._swin1, style1)
    else
      style1.noautocmd = true
      self._sbuf1 = ensure_tmp_buf(self._sbuf1)
      self._swin1 = vim.api.nvim_open_win(self._sbuf1, false, style1)
      local hl = self.winopts.__hl.scrollfloat_e or "PmenuSbar"
      vim.api.nvim_win_set_option(self._swin1, "winhighlight",
        ("Normal:%s,NormalNC:%s,NormalFloat:%s"):format(hl, hl, hl))
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
      local hl = self.winopts.__hl.scrollfloat_f or "PmenuThumb"
      vim.api.nvim_win_set_option(self._swin2, "winhighlight",
        ("Normal:%s,NormalNC:%s,NormalFloat:%s"):format(hl, hl, hl))
    end
  end
end

function FzfWin:update_scrollbar()
  if not self.winopts.preview.scrollbar
      or self.winopts.preview.scrollbar == "none"
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

  if self.winopts.preview.scrollbar == "float" then
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
  if #title > width - right_pad then
    title = title:sub(1, width - right_pad) .. " "
  end
  -- save for set_title_hl
  self._title_len = #title
  local width_title = fn.strwidth(title)
  local prefix = fn.strcharpart(top, 0, 3)
  if self.winopts.preview.title_align == "center" then
    prefix = fn.strcharpart(top, 0, utils.round((width - width_title) / 2))
  elseif self.winopts.preview.title_align == "right" then
    prefix = fn.strcharpart(top, 0, width - (width_title + 3))
  end

  local suffix = fn.strcharpart(top, width_title + fn.strwidth(prefix), width)
  title = ("%s%s%s"):format(prefix, title, suffix)
  api.nvim_buf_set_lines(border_buf, 0, 1, 1, { title })
  -- will be used later in set_title_hl()
  self._title_position = #prefix
  self:set_title_hl()
end

-- keybind methods below
function FzfWin.toggle_fullscreen()
  if not _self or _self.winopts.split then return end
  local self = _self
  self.fullscreen = not self.fullscreen
  self:hide_scrollbar()
  if self and self:validate() then
    self:redraw_main()
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
    self:redraw_main()
  elseif not self.preview_hidden then
    self:redraw_main()
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
  self.preview_wrap = not api.nvim_win_get_option(self.preview_winid, "wrap")
  if self and self:validate_preview() then
    api.nvim_win_set_option(self.preview_winid, "wrap", self.preview_wrap)
  end
end

function FzfWin.toggle_preview_cw(direction)
  if not _self
      or _self.winopts.split
      or not _self:validate_preview() then
    return
  end
  local self = _self
  local pos = { "up", "right", "down", "left" }
  local idx
  for i = 1, #pos do
    if pos[i] == self.winopts.preview_pos then
      idx = i
      break
    end
  end
  if not idx then return end
  local newidx = direction > 0 and idx + 1 or idx - 1
  if newidx < 1 then newidx = #pos end
  if newidx > #pos then newidx = 1 end
  self.winopts.preview_pos = pos[newidx]
  self.layout = self:generate_layout(self.winopts)
  self:close_preview()
  self:redraw_main()
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

function FzfWin.close_help()
  if not _self or not _self.km_winid then
    return
  end

  local self = _self

  if vim.api.nvim_win_is_valid(self.km_winid) then
    utils.nvim_win_close(self.km_winid, true)
  end
  if vim.api.nvim_buf_is_valid(self.km_bufnr) then
    vim.api.nvim_buf_delete(self.km_bufnr, { force = true })
  end
  self.km_winid = nil
  self.km_bufnr = nil
end

function FzfWin.toggle_help()
  if not _self then return end
  local self = _self

  if self.km_winid then
    -- help window is already open
    -- close and dispose resources
    self.close_help()
    return
  end

  local opts = {}
  opts.max_height = opts.max_height or math.floor(0.4 * vim.o.lines)
  opts.mode_width = opts.mode_width or 10
  opts.name_width = opts.name_width or 28
  opts.keybind_width = opts.keybind_width or 14
  opts.normal_hl = opts.normal_hl or self.winopts.__hl.help_normal
  opts.border_hl = opts.border_hl or self.winopts.__hl.help_border
  opts.winblend = opts.winblend or 0
  opts.column_padding = opts.column_padding or "  "
  opts.column_width = opts.keybind_width + opts.name_width + #opts.column_padding + 2
  opts.close_with_action = opts.close_with_action or true

  local function format_bind(m, k, v, ml, kl, vl)
    return ("%s%%-%ds %%-%ds %%-%ds")
        :format(opts.column_padding, ml, kl, vl)
        :format("`" .. m .. "`", "|" .. k .. "|", "*" .. v .. "*")
  end

  local keymaps = {}
  local preview_mode = self.previewer_is_builtin and "builtin" or "fzf"

  -- fzf and neovim (builtin) keymaps
  for _, m in ipairs({ "builtin", "fzf" }) do
    for k, v in pairs(self.keymap[m]) do
      -- only add preview keybinds respective of
      -- the current preview mode
      if v and (not _preview_keymaps[v] or m == preview_mode) then
        if m == "builtin" then
          k = utils.neovim_bind_to_fzf(k)
        end
        table.insert(keymaps,
          format_bind(m, k, v,
            opts.mode_width, opts.keybind_width, opts.name_width))
      end
    end
  end

  -- action keymaps
  if self.actions then
    for k, v in pairs(self.actions) do
      if k == "default" then k = "enter" end
      if type(v) == "table" then
        v = config.get_action_helpstr(v[1]) or v
      elseif v then
        v = config.get_action_helpstr(v) or v
      end
      if v then
        -- skips 'v == false'
        table.insert(keymaps,
          format_bind("action", k,
            ("%s"):format(v):gsub(" ", ""),
            opts.mode_width, opts.keybind_width, opts.name_width))
      end
    end
  end

  -- sort alphabetically
  table.sort(keymaps, function(x, y)
    if x < y then
      return true
    else
      return false
    end
  end)

  -- append to existing line based on
  -- available columns
  local function table_append(tbl, s)
    local last = #tbl > 0 and tbl[#tbl]
    if not last or #last + #s > vim.o.columns then
      table.insert(tbl, s)
    else
      tbl[#tbl] = last .. s
    end
  end

  local lines = {}
  for _, km in ipairs(keymaps) do
    table_append(lines, km)
  end

  -- calc popup height based on no. of lines
  local height = #lines < opts.max_height and #lines or opts.max_height

  -- rearrange lines so keymaps appear
  -- sequential within the same column
  lines = {}
  for c = 0, math.floor(vim.o.columns / (opts.column_width + #opts.column_padding)) do
    for i = 1, height do
      local idx = height * c + i
      lines[i] = c == 0 and keymaps[idx] or
          lines[i] .. (keymaps[idx] or "")
    end
  end

  local winopts = {
    relative = "editor",
    style = "minimal",
    width = vim.o.columns,
    height = height,
    row = vim.o.lines - height - vim.o.cmdheight - 2,
    col = 1,
    -- top border only
    border = { " ", "─", " ", " ", " ", " ", " ", " " },
    -- topmost popup
    zindex = 999,
  }

  self.km_bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(self.km_bufnr, "bufhidden", "wipe")
  self.km_winid = vim.api.nvim_open_win(self.km_bufnr, false, winopts)
  vim.api.nvim_buf_set_name(self.km_bufnr, "_FzfLuaHelp")
  vim.api.nvim_win_set_option(self.km_winid, "winhl",
    string.format("Normal:%s,FloatBorder:%s", opts.normal_hl, opts.border_hl))
  vim.api.nvim_win_set_option(self.km_winid, "winblend", opts.winblend)
  vim.api.nvim_win_set_option(self.km_winid, "foldenable", false)
  vim.api.nvim_win_set_option(self.km_winid, "wrap", false)
  vim.api.nvim_buf_set_option(self.km_bufnr, "filetype", "help")

  vim.cmd(string.format(
    "autocmd BufLeave <buffer> ++once lua %s",
    table.concat({
      string.format("pcall(vim.api.nvim_win_close, %s, true)", self.km_winid),
      string.format("pcall(vim.api.nvim_buf_delete, %s, {force=true})", self.km_bufnr),
    }, ";")
  ))

  vim.api.nvim_buf_set_lines(self.km_bufnr, 0, -1, false, lines)
end

return FzfWin
