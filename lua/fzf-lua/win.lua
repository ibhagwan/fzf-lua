local utils = require "fzf-lua.utils"
local libuv = require "fzf-lua.libuv"
local actions = require "fzf-lua.actions"

local api = vim.api
local fn = vim.fn

---@alias fzf-lua.win.previewPos "up"|"down"|"left"|"right"
---@alias fzf-lua.win.previewLayout { pos: fzf-lua.win.previewPos, size: number, str: string }

---@class fzf-lua.config.WinoptsResolved: fzf-lua.config.Winopts
---@field height integer
---@field width integer
---@field row integer
---@field col integer
---@field zindex integer
---@field preview fzf-lua.config.PreviewOpts

---@class fzf-lua.Win
---@field winopts fzf-lua.config.WinoptsResolved
---@field actions fzf-lua.config.Actions|{}
---@field layout fzf-lua.WinLayout
---@field fzf_bufnr integer
---@field fzf_winid integer
---@field preview_hidden? boolean
---@field preview_wrap? boolean
---@field fullscreen? boolean
---@field hls fzf-lua.config.HLS
---@field tsinjector? fzf-lua.TSInjector
---@field previewer? fun(...)|table|string
---@field _hidden_fzf_bufnr? integer
---@field toggle_behavior? "extend"|"default"
---@field _previewer? fzf-lua.previewer.Builtin|fzf-lua.previewer.Fzf
---@field _preview_pos_force? fzf-lua.win.previewPos
---@field _last_view? [integer, integer, integer]?
---@field _o fzf-lua.config.Resolved
local FzfWin = {}

-- singleton instance used by "_exported_wapi"
---@type fzf-lua.Win?
local _self = nil

function FzfWin.__SELF()
  return _self
end

local _preview_keymaps = {
  ["toggle-preview-wrap"]    = { module = "win", fnc = "toggle_preview_wrap()" },
  ["toggle-preview-ts-ctx"]  = { module = "win", fnc = "toggle_preview_ts_ctx()" },
  ["toggle-preview-undo"]    = { module = "win", fnc = "toggle_preview_undo_diff()" },
  ["preview-ts-ctx-inc"]     = { module = "win", fnc = "preview_ts_ctx_inc_dec(1)" },
  ["preview-ts-ctx-dec"]     = { module = "win", fnc = "preview_ts_ctx_inc_dec(-1)" },
  ["preview-up"]             = { module = "win", fnc = "preview_scroll('line-up')" },
  ["preview-down"]           = { module = "win", fnc = "preview_scroll('line-down')" },
  ["preview-page-up"]        = { module = "win", fnc = "preview_scroll('page-up')" },
  ["preview-page-down"]      = { module = "win", fnc = "preview_scroll('page-down')" },
  ["preview-half-page-up"]   = { module = "win", fnc = "preview_scroll('half-page-up')" },
  ["preview-half-page-down"] = { module = "win", fnc = "preview_scroll('half-page-down')" },
  ["preview-reset"]          = { module = "win", fnc = "preview_scroll('reset')" },
  ["preview-top"]            = { module = "win", fnc = "preview_scroll('top')" },
  ["preview-bottom"]         = { module = "win", fnc = "preview_scroll('bottom')" },
  ["focus-preview"]          = { module = "win", fnc = "focus_preview()" },
}

function FzfWin:setup_keybinds()
  self.keymap = type(self.keymap) == "table" and self.keymap or {}
  self.keymap.fzf = type(self.keymap.fzf) == "table" and self.keymap.fzf or {}
  self.keymap.builtin = type(self.keymap.builtin) == "table" and self.keymap.builtin or {}
  local keymap_tbl = {
    ["hide"]                    = { module = "win", fnc = "hide()" },
    ["toggle-help"]             = { module = "win", fnc = "toggle_help()" },
    ["toggle-fullscreen"]       = { module = "win", fnc = "toggle_fullscreen()" },
    ["toggle-preview"]          = { module = "win", fnc = "toggle_preview()" },
    ["toggle-preview-cw"]       = { module = "win", fnc = "toggle_preview_cw(1)" },
    ["toggle-preview-ccw"]      = { module = "win", fnc = "toggle_preview_cw(-1)" },
    ["toggle-preview-behavior"] = { module = "win", fnc = "toggle_preview_behavior()" },
  }
  -- use signal when user bind toggle-preview in FZF_DEFAULT_OPTS/FZF_DEFAULT_FILE_OPTS
  local function on_SIGWINCH_toggle_preview()
    if utils.__IS_WINDOWS then return end -- not sure why ci fail on windows
    self.on_SIGWINCH(self._o, "toggle-preview", function(args)
      -- hide if visible but do not toggle if hidden as we want to
      -- make sure the right layout is set if user rotated the preview
      if tonumber(args[1]) then
        return "toggle-preview"
      else
        -- NOTE: always equals?
        -- self = _self or self -- may differ with `... resume previewer=...`
        return string.format("change-preview-window(%s)", self:normalize_preview_layout().str)
      end
    end)
  end
  local function on_SIGWINCH_toggle_preview_cw()
    if utils.__IS_WINDOWS then return end -- not sure why ci fail on windows
    self.on_SIGWINCH(self._o, "toggle-preview-cw", function(args)
      -- only set the layout if preview isn't hidden
      if not tonumber(args[1]) then return end
      -- NOTE: always equals?
      -- self = _self or self -- may differ with `... resume previewer=...`
      return string.format("change-preview-window(%s)", self:normalize_preview_layout().str)
    end)
  end
  -- find the toggle_preview keybind, to be sent when using a split for the native
  -- pseudo fzf preview window or when using native and treesitter is enabled
  self._fzf_toggle_prev_bind = nil
  -- use fzf-native binds in fzf-tmux or cli (shell) profile
  if self._o._is_fzf_tmux or _G.fzf_jobstart then
    for k, v in pairs(self.keymap.builtin) do
      if type(v) == "string" and v:match("toggle%-preview%-c?cw") then
        k = utils.neovim_bind_to_fzf(k)
        self.keymap.fzf[k] = "transform:" .. FzfLua.shell.stringify_data(function(args, _, _)
          -- only set the layout if preview isn't hidden
          if not tonumber(args[1]) then return end
          assert(keymap_tbl[v])
          assert(loadstring(string.format([[require("fzf-lua.%s").%s]],
            keymap_tbl[v].module, keymap_tbl[v].fnc)))()
          return string.format("change-preview-window(%s)", self:normalize_preview_layout().str)
        end, {}, utils.__IS_WINDOWS and "%FZF_PREVIEW_LINES%" or "$FZF_PREVIEW_LINES")
      end
    end
  elseif self.winopts.split or not self.previewer_is_builtin then
    -- sync toggle-preview
    -- 1. always run the toggle-preview(), and self._fzf_toggle_prev_bind
    for k, v in pairs(self.keymap.builtin) do
      if v == "toggle-preview" then
        on_SIGWINCH_toggle_preview()
        self.keymap.fzf[utils.neovim_bind_to_fzf(k)] = v
      end
      if type(v) == "string" and v:match("toggle%-preview%-c?cw") then
        on_SIGWINCH_toggle_preview_cw()
      end
    end
    for k, v in pairs(self.keymap.fzf) do
      if v == "toggle-preview" then
        on_SIGWINCH_toggle_preview()
        self._fzf_toggle_prev_bind = utils.fzf_bind_to_neovim(k)
        self.keymap.builtin[self._fzf_toggle_prev_bind] = v
      end
      if type(v) == "string" and v:match("toggle%-preview%-c?cw") then
        on_SIGWINCH_toggle_preview_cw()
        self.keymap.fzf[k] = nil -- invalid fzf bind, user set bind by mistake
      end
    end
    self._fzf_toggle_prev_bind = self._fzf_toggle_prev_bind or true
  end
  if self.previewer_is_builtin then
    -- These maps are only valid for the builtin previewer
    keymap_tbl = vim.tbl_deep_extend("keep", keymap_tbl, _preview_keymaps)
  end
  local function funcref_str(keymap)
    return ([[<Cmd>lua require('fzf-lua.%s').%s<CR>]]):format(keymap.module, keymap.fnc)
  end

  for key, action in pairs(self.keymap.builtin) do
    local keymap = keymap_tbl[action]
    if keymap and not utils.tbl_isempty(keymap) and action ~= false then
      vim.keymap.set("t", key, funcref_str(keymap), { nowait = true, buffer = self.fzf_bufnr })
    end
  end

  -- If the user did not override the Esc action ensure it's
  -- not bound to anything else such as `<C-\><C-n>` (#663)
  if self.actions["esc"] == actions.dummy_abort and not self.keymap.builtin["<esc>"] then
    vim.keymap.set("t", "<Esc>", "<Esc>", { buffer = self.fzf_bufnr, nowait = true })
  end
end

-- check if previewer useable (not matter if it's hidden)
function FzfWin:has_previewer()
  return self._o.preview or self._previewer and true or false
end

---@return fzf-lua.win.previewLayout
function FzfWin:normalize_preview_layout()
  local preview_str, pos ---@type string, fzf-lua.win.previewPos
  if self._preview_pos_force then
    -- Get the correct layout string and size when set from `:toggle_preview_cw`
    preview_str = assert((self._preview_pos_force == "up" or self._preview_pos_force == "down")
      and self.winopts.preview.vertical or self.winopts.preview.horizontal)
    pos = self._preview_pos_force
  else
    preview_str = self:fzf_preview_layout_str()
    pos = preview_str:match("[^:]+") or "right"
  end
  local percent = tonumber(preview_str:match(":(%d+)%%"))
  local abs = not percent and tonumber(preview_str:match(":(%d+)")) or nil
  percent = percent or 50
  return {
    pos = pos,
    size = abs or (percent / 100),
    str = string.format("%s:%s", pos, tostring(abs or percent) .. ((not abs) and "%" or ""))
  }
end

---@return integer nwin, boolean preview
function FzfWin:normalize_layout()
  -- when to use full fzf layout
  -- 1. no previewer (always)
  -- 2. builtin previewer (hidden and not "extend")
  -- 3. fzf previewer (not "extend" or not hidden)
  if not self:has_previewer()
      or (self.previewer_is_builtin and (self.preview_hidden and self.toggle_behavior ~= "extend"))
      or (not self.previewer_is_builtin and (self.toggle_behavior ~= "extend" or not self.preview_hidden)) then
    return 1, false
  end
  -- has previewer, but when nwin=1, reduce fzf main layout as if the previewer is displayed
  local nwin = self.preview_hidden and self.toggle_behavior == "extend" and 1 or 2
  return nwin, true
end

---@class fzf-lua.WinLayout
---@field fzf vim.api.keyset.win_config
---@field preview? vim.api.keyset.win_config

function FzfWin:generate_layout()
  local winopts = self:normalize_winopts()
  local nwin, preview = self:normalize_layout()
  local layout = self:normalize_preview_layout()
  local border, h, w = self:normalize_border(self._o.winopts.border, {
    type = "nvim",
    name = "fzf",
    layout = preview and layout.pos or nil,
    nwin = nwin,
    opts = self._o
  })
  if not preview then
    self.layout = {
      fzf = {
        row = winopts.row,
        col = winopts.col,
        width = winopts.width,
        height = winopts.height,
        border = border,
        style = "minimal",
        relative = winopts.relative or "editor",
        zindex = winopts.zindex,
        hide = winopts.hide,
      }
    }
    return
  end

  if self.previewer_is_builtin and winopts.split then
    local wininfo = utils.__HAS_NVIM_010 and api.nvim_win_get_config(self.fzf_winid) or
        assert(fn.getwininfo(self.fzf_winid)[1])
    -- no signcolumn/number/relativenumber (in set_style_minimal)
    ---@diagnostic disable-next-line: missing-fields
    winopts = {
      height = wininfo.height,
      width = wininfo.width,
      split = winopts.split,
      row = 0,
      col = 0,
    }
  end

  local pwopts
  local row, col = winopts.row, winopts.col
  local height, width = winopts.height, winopts.width
  local preview_pos, preview_size = layout.pos, layout.size
  local pborder, ph, pw = self:normalize_border(self._o.winopts.preview.border,
    { type = "nvim", name = "prev", layout = preview and layout.pos, nwin = nwin, opts = self._o })
  if winopts.split then
    -- Custom "split"
    pwopts = { relative = "win", anchor = "NW", row = 0, col = 0 }
    if preview_pos == "down" or preview_pos == "up" then
      pwopts.width = width - pw
      pwopts.height = self:normalize_size(preview_size, height) - ph
      if preview_pos == "down" then
        pwopts.row = height - pwopts.height - ph
      end
    else -- left|right
      pwopts.height = height - ph
      pwopts.width = self:normalize_size(preview_size, width) - pw
      if preview_pos == "right" then
        pwopts.col = width - pwopts.width + pw
      end
    end
  else
    -- Float window
    pwopts = { relative = "editor" }
    if preview_pos == "down" or preview_pos == "up" then
      pwopts.col = col
      pwopts.width = width
      -- https://github.com/junegunn/fzf/blob/1afd14381079a35eac0a4c2a5cacb86e2a3f476b/src/terminal.go#L1820
      -- fzf's previewer border is draw inside preview window, so shrink builtin previewer if it have "top border"
      -- to ensure the fzf list height is the same between fzf/builtin
      local off = (preview_size < 1 and self.previewer_is_builtin and ph > 0) and 1
          or (preview_size >= 1 and not self.previewer_is_builtin and ph > 0) and -ph
          or 0
      pwopts.height = self:normalize_size(preview_size, (height + off)) - off
      height = height - pwopts.height
      if preview_pos == "down" then
        -- next row
        pwopts.row = row + h + height
      else -- up
        pwopts.row = row
        row = pwopts.row + ph + pwopts.height
      end
      -- enlarge the height to align fzf with preview win
      if self.previewer_is_builtin then
        width = width + math.max(pw - w, 0)
        pwopts.width = pwopts.width + math.max(w - pw, 0)
      end
    else -- left|right
      pwopts.row = row
      pwopts.height = height
      local off = (preview_size < 1 and self.previewer_is_builtin and pw > 0) and 1
          or (preview_size >= 1 and not self.previewer_is_builtin and pw > 0) and -pw
          or 0
      pwopts.width = self:normalize_size(preview_size, (width + off)) - off
      width = width - pwopts.width
      if preview_pos == "right" then
        -- next col
        pwopts.col = col + w + width
      else -- left
        pwopts.col = col
        col = pwopts.col + pw + pwopts.width
      end
      -- enlarge the height to align fzf with preview win
      if self.previewer_is_builtin then
        height = height + math.max(ph - h, 0)
        pwopts.height = pwopts.height + math.max(h - ph, 0)
      end
    end
  end
  self.layout = {
    fzf = vim.tbl_extend("force", { row = row, col = col, height = height, width = width }, {
      style = "minimal",
      border = border,
      relative = winopts.relative or "editor",
      zindex = winopts.zindex,
      hide = winopts.hide,
    }),
    preview = vim.tbl_extend("force", pwopts, {
      style = "minimal",
      zindex = winopts.zindex,
      border = pborder,
      focusable = true,
      hide = winopts.hide,
    }),
  }
end

function FzfWin:tmux_columns()
  local is_popup, is_hsplit, opt_val = (function()
    -- Backward compat using "fzf-tmux" script
    if self._o._is_fzf_tmux == 1 then
      for _, flag in ipairs({ "-l", "-r" }) do
        if self._o.fzf_tmux_opts[flag] then
          -- left/right split, not a popup, is an hsplit
          return false, true, self._o.fzf_tmux_opts[flag]
        end
      end
      for _, flag in ipairs({ "-u", "-d" }) do
        if self._o.fzf_tmux_opts[flag] then
          -- up/down split, not a popup, not an hsplit
          return false, false, self._o.fzf_tmux_opts[flag]
        end
      end
      -- Default is a popup with "-p" or without
      return true, false, self._o.fzf_tmux_opts["-p"]
    else
      return true, false, self._o.fzf_opts["--tmux"]
    end
  end)()
  local out = utils.io_system({
    "tmux", "display-message", "-p",
    is_popup and "#{window_width}" or "#{pane_width}"
  })
  local cols = tonumber(out:match("%d+"))
  -- Calc the correct width when using tmux popup or left|right splits
  -- fzf's defaults to "--tmux" is "center,50%" or "50%" for splits
  if is_popup or is_hsplit then
    local percent = type(opt_val) == "string" and tonumber(opt_val:match("(%d+)%%")) or 50
    cols = math.floor(assert(cols) * percent / 100)
  end
  return cols
end

function FzfWin:columns(no_fullscreen)
  -- When called from `core.preview_window` we need to get the no-fullscreen columns
  -- in order to get an accurate alternate layout trigger that will also be consistent
  -- when starting with `winopts.fullscreen == true`
  local winopts = no_fullscreen and self._o.winopts or self.winopts
  return self._o._is_fzf_tmux and self:tmux_columns()
      or vim.is_callable(_G.fzf_tty_get_width) and _G.fzf_tty_get_width()
      or winopts.split and api.nvim_win_get_width(self.fzf_winid or 0)
      or self:normalize_size(winopts.width, vim.o.columns)
end

function FzfWin:fzf_preview_layout_str()
  local columns = self:columns()
  local is_hsplit = self.winopts.preview.layout == "horizontal"
      or self.winopts.preview.layout == "flex" and columns > self.winopts.preview.flip_columns
  return is_hsplit and self._o.winopts.preview.horizontal or self._o.winopts.preview.vertical
end

---@param border any
---@param metadata fzf-lua.win.borderMetadata
---@return fzf-lua.winborder, integer, integer
function FzfWin:normalize_border(border, metadata)
  return require("fzf-lua.win.border").nvim(border, metadata, self._o.silent)
end

---@param size number|integer
---@param max integer
---@return integer
function FzfWin:normalize_size(size, max)
  local _ = self
  if size <= 1 then return math.floor(max * size) end
  ---@cast size integer
  return math.min(size, max)
end

---@return fzf-lua.config.WinoptsResolved
function FzfWin:normalize_winopts()
  -- make a local copy of winopts so we don't pollute the user's options
  self.winopts = utils.tbl_deep_clone(self._o.winopts or {}) or {}
  local winopts = self.winopts

  if self.fullscreen then
    -- NOTE: we set `winopts.relative=editor` so fullscreen
    -- works even when the user set `winopts.relative=cursor`
    winopts.relative = "editor"
    winopts.row = 1
    winopts.col = 1
    winopts.width = 1
    winopts.height = 1
  end

  local nwin, preview = self:normalize_layout()
  local preview_pos = preview and self:normalize_preview_layout().pos or nil
  if preview and self.previewer_is_builtin then nwin = 2 end
  local _, h, w = self:normalize_border(self._o.winopts.border,
    { type = "nvim", name = "fzf", layout = preview_pos, nwin = nwin, opts = self._o })
  if preview and self.previewer_is_builtin then
    local _, ph, pw = self:normalize_border(self._o.winopts.preview.border,
      { type = "nvim", name = "prev", layout = preview_pos, nwin = nwin, opts = self._o })
    if preview_pos == "up" or preview_pos == "down" then
      h, w = h + ph, math.max(w, pw)
    else -- left|right
      h, w = math.max(h, ph), w + pw
    end
  end

  -- #2121 we can suppress cmdline area when zindex >= 200
  local ch = winopts.zindex >= 200 and 0 or vim.o.cmdheight
  local max_width = vim.o.columns
  local max_height = vim.o.lines - ch
  winopts.width = self:normalize_size(assert(tonumber(winopts.width)), max_width)
  winopts.height = self:normalize_size(assert(tonumber(winopts.height)), max_height)
  if winopts.relative == "cursor" then
    -- convert cursor relative to absolute ('editor'),
    -- this solves the preview positioning seamlessly
    -- use the calling window context for correct pos
    local winid = utils.CTX().winid
    local pos = api.nvim_win_get_cursor(winid)
    local screenpos = fn.screenpos(winid, pos[1], pos[2])
    winopts.row = math.floor((winopts.row or 0) + screenpos.row - 1)
    winopts.col = math.floor((winopts.col or 0) + screenpos.col - 1)
    winopts.relative = nil
  else
    -- make row close to the center of screen (include cmdheight)
    -- avoid breaking existing test
    winopts.row = self:normalize_size(assert(tonumber(winopts.row)), vim.o.lines - winopts.height)
    winopts.col = self:normalize_size(assert(tonumber(winopts.col)), max_width - winopts.width)
    winopts.row = math.min(winopts.row, max_height - winopts.height)
  end
  -- width/height can be used for text area
  winopts.width = math.max(1, winopts.width - w)
  winopts.height = math.max(1, winopts.height - h)
  ---@type fzf-lua.config.WinoptsResolved
  return winopts
end

---@param winhls table<string, string|false>|string
---@return string
local function make_winhl(winhls)
  if type(winhls) == "string" then return winhls end
  local winhl = {}
  for k, h in pairs(winhls) do
    if h then winhl[#winhl + 1] = ("%s:%s"):format(k, h) end
  end
  return table.concat(winhl, ",")
end

---@param win integer
---@param pwinhl? table<string, string|false>|string preview winhl
function FzfWin:reset_winhl(win, pwinhl)
  -- derive the highlights from the window type
  local hls = self.hls
  local winhls = pwinhl or {
    Normal = hls.normal,
    NormalFloat = hls.normal,
    FloatBorder = hls.border,
    CursorLine = hls.cursorline,
    CursorLineNr = hls.cursorlinenr,
  }
  (pwinhl and utils.wo[win] or utils.wo[win][0]).winhl = make_winhl(winhls)
end

---@param exit_code integer
---@param fzf_bufnr integer?
function FzfWin:check_exit_status(exit_code, fzf_bufnr)
  -- see the comment in `FzfWin:close` for more info
  if fzf_bufnr and fzf_bufnr ~= self.fzf_bufnr then
    return
  end
  if not self:validate() then return end
  -- from 'man fzf':
  --    0      Normal exit
  --    1      No match
  --    2      Error
  --    130    Interrupted with CTRL-C or ESC
  if exit_code == 2 then
    local lines = api.nvim_buf_get_lines(self.fzf_bufnr, 0, 1, false)
    utils.error("fzf error %d: %s", exit_code, lines and #lines[1] > 0 and lines[1] or "<null>")
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

function FzfWin:set_autoclose(autoclose)
  return self:_set_autoclose(autoclose)
end

function FzfWin:autoclose()
  return self._autoclose
end

function FzfWin:set_backdrop()
  -- No backdrop for split, only floats / tmux
  if self.winopts.split then return end
  require("fzf-lua.win.backdrop").open(
    self.winopts.backdrop, self.winopts.zindex - 2, self.hls)
end

---@diagnostic disable-next-line: unused
function FzfWin:close_backdrop()
  require("fzf-lua.win.backdrop").close()
end

---@param o fzf-lua.config.Resolved
---@return fzf-lua.Win
function FzfWin.new(o)
  if not _self then
  elseif _self:was_hidden() or _self:hidden() then
    _self:close(nil, nil, true) -- do not clear info
    _self = nil
  elseif not _self:hidden() then
    -- utils.warn("Please close fzf-lua before starting a new instance")
    _self._reuse = true
    -- switch to fzf-lua's main window in case the user switched out
    -- NOTE: `self.fzf_winid == nil` when using fzf-tmux
    if _self.fzf_winid and _self.fzf_winid ~= api.nvim_get_current_win() then
      api.nvim_set_current_win(_self.fzf_winid)
    end
    -- Update main win title, required for toggle action flags
    _self:update_main_title(o.winopts.title)
    -- refersh treesitter settings as new picker might have it disabled
    -- detach previewer and refresh signal handler
    -- e.g. when switch from fzf previewer to builtin previewer
    _self._o = o
    o.winopts.preview.hidden = _self.preview_hidden
    _self:attach_previewer(nil)
    return _self
  end
  o = o or {} ---@type fzf-lua.config.Resolved
  ---@type fzf-lua.Win
  local self = utils.setmetatable({}, -- gc is unused now, only used to test _self is nullrified
    { __index = FzfWin, __gc = function() _G._fzf_lua_gc_called = true end })
  self._o = o
  self.hls = o.hls
  self.actions = o.actions
  self.fullscreen = o.winopts.fullscreen
  self.toggle_behavior = o.winopts.toggle_behavior
  self.preview_wrap = not not o.winopts.preview.wrap     -- force boolean
  self.preview_hidden = not not o.winopts.preview.hidden -- force boolean
  self.keymap = o.keymap
  self.previewer = o.previewer
  self:_set_autoclose(o.autoclose)
  self.winopts = self:normalize_winopts()
  _self = self
  return self
end

---@param win integer
---@param opts vim.wo|{}
---@return vim.wo|{}
function FzfWin:get_winopts(win, opts)
  local _ = self
  if not win or not api.nvim_win_is_valid(win) then return {} end
  local ret = {}
  for opt, _ in pairs(opts) do
    ret[opt] = utils.wo[win][opt]
  end
  return ret
end

---@param win integer
---@param opts vim.wo|{}
---@param ignore_events boolean?
---@param global boolean?
function FzfWin:set_winopts(win, opts, ignore_events, global)
  local _ = self
  if not win or not api.nvim_win_is_valid(win) then return end
  -- NOTE: Do not trigger "OptionSet" as this will trigger treesitter-context's
  -- `update_single_context` which will in turn close our treesitter-context
  local ei = ignore_events and "all" or vim.o.eventignore
  local wo = global ~= false and utils.wo[win] or utils.wo[win][0]
  utils.eventignore(function()
    for opt, value in pairs(opts) do
      wo[opt] = value
    end
  end, ei)
end

---@param previewer fzf-lua.previewer.Builtin|fzf-lua.previewer.Fzf? nil to "detach" previewer
function FzfWin:attach_previewer(previewer)
  if previewer then
    previewer.win = self
    previewer.delay = self.winopts.preview.delay or 100
    previewer.title = self.winopts.preview.title
    previewer.title_pos = self.winopts.preview.title_pos
    previewer.winopts = self.winopts.preview.winopts
  end
  -- clear the previous previewer if existed
  if self._previewer and self._previewer.close then
    -- if we press ctrl-g too quickly 'previewer.preview_bufnr' will be nil
    -- and even though the temp buffer is set to 'bufhidden:wipe' the buffer
    -- won't be closed properly and remain lingering (visible in `:ls!`)
    -- make sure the previewer is aware of this buffer
    if not self._previewer.preview_bufnr and self:validate_preview() then
      self._previewer.preview_bufnr = api.nvim_win_get_buf(self.preview_winid)
    end
    self:close_preview()
  end
  self._previewer = previewer
  self.previewer_is_builtin = previewer and previewer.type == "builtin"
  self.toggle_behavior = previewer and previewer.toggle_behavior or self.toggle_behavior
  self:normalize_winopts()
end

function FzfWin:validate_preview()
  return not self.closing
      and self.preview_winid
      and api.nvim_win_is_valid(self.preview_winid)
end

function FzfWin:redraw_preview()
  if not self.previewer_is_builtin or self.preview_hidden then
    return
  end
  local previewer = self._previewer ---@cast previewer fzf-lua.previewer.Builtin

  -- Close the exisiting scrollbar
  self:close_preview_scrollbar()

  -- Generate the preview layout
  self:generate_layout()
  assert(type(self.layout.preview) == "table")

  if self:validate_preview() then
    utils.win_set_config(self.preview_winid, self.layout.preview)
  else
    local tmp_buf = previewer:get_tmp_buffer()
    -- No autocmds, can only be sent with 'nvim_open_win'
    self.preview_winid = api.nvim_open_win(tmp_buf, false,
      vim.tbl_extend("force", self.layout.preview, { noautocmd = true }))
    -- Add win local var for the preview|border windows
    api.nvim_win_set_var(self.preview_winid, "fzf_lua_preview", true)
  end
  previewer:reset_winhl(self.preview_winid)
  previewer:display_last_entry()
  previewer:update_ts_context()
end

function FzfWin:validate()
  return self.fzf_winid and self.fzf_winid > 0
      and api.nvim_win_is_valid(self.fzf_winid)
end

function FzfWin:redraw()
  self:normalize_winopts()
  self:set_backdrop()
  if self:validate() then
    self:redraw_main()
  end
  if self:validate_preview() then
    self:redraw_preview()
  end
end

---@param title any
---@param hl? string|false hl will also be used as fallback, if title part don't have hl
---@return [string, string][]
local function make_title(title, hl)
  if type(title) == "string" then return { { title, type(hl) == "string" and hl or "FloatTitle" } } end
  return type(title) ~= "table" and { { "", hl or "FloatTitle" } }
      or vim.tbl_map(function(p) return { p[1], p[2] or hl or "FloatTitle" } end, title)
end

function FzfWin:redraw_main()
  if self.winopts.split then return end

  self:generate_layout()

  local winopts = vim.tbl_extend("keep", {
    title = make_title(self.winopts.title, self.hls.title),
    title_pos = self.winopts.title_pos,
  }, self.layout.fzf)

  if self:validate() then
    if self._previewer
        and self._previewer.clear_on_redraw
        and self._previewer.clear_preview_buf
        and self._previewer.clear_cached_buffers then
      self._previewer:clear_preview_buf(true)
      self._previewer:clear_cached_buffers()
    end
    utils.win_set_config(self.fzf_winid, winopts)
  else
    -- save 'cursorline' setting prior to opening the popup
    local cursorline = vim.o.cursorline
    self.fzf_bufnr = self.fzf_bufnr or api.nvim_create_buf(false, true)
    self.fzf_winid = utils.nvim_open_win(self.fzf_bufnr, true, winopts)
    -- disable search highlights as they interfere with fzf's highlights
    if vim.o.hlsearch and vim.v.hlsearch == 1 then
      self.hls_on_close = true
      vim.cmd("nohls")
    end
    -- `:help nvim_open_win`
    -- 'minimal' sets 'nocursorline', normally this shouldn't
    -- be an issue but for some reason this is affecting opening
    -- buffers in new splits and causes them to open with
    -- 'nocursorline', see discussion in #254
    vim.o.cursorline = cursorline
  end
end

function FzfWin:_on(e, callback, global)
  api.nvim_create_autocmd(e, {
    group = api.nvim_create_augroup("FzfLua" .. e, { clear = true }),
    buffer = global ~= true and self.fzf_bufnr or nil,
    callback = callback,
  })
end

function FzfWin:set_redraw_autocmd()
  self:_on("VimResized", function() self:redraw() end)
end

function FzfWin:set_winleave_autocmd()
  self:_on("WinClosed", function() self:close() end)
  -- Workaround for using `:wqa` with "hide"
  -- https://github.com/neovim/neovim/issues/14061
  self:_on("ExitPre", function() self:close() end, true)
end

function FzfWin:treesitter_attach()
  if not self._o.winopts.treesitter then return end
  self.tsinjector = require("fzf-lua.win.tsinjector")
  self.tsinjector.attach(self, self.fzf_bufnr, self._o._treesitter)
end

function FzfWin:set_tmp_buffer(no_wipe)
  if not self:validate() then return end
  -- Store the [would be] detached buffer number
  local detached = self.fzf_bufnr
  -- replace the attached buffer with a new temp buffer, setting `self.fzf_bufnr`
  -- makes sure the call to `fzf_win:close` (which is triggered by the buf del)
  -- won't trigger a close due to mismatched buffers condition on `self:close`
  self.fzf_bufnr = api.nvim_create_buf(false, true)
  -- `hidden` must be set to true or the detached buffer will be deleted (#1850)
  local old_hidden = vim.o.hidden
  vim.o.hidden = true
  utils.win_set_buf_noautocmd(self.fzf_winid, self.fzf_bufnr)
  vim.o.hidden = old_hidden
  -- close the previous fzf term buffer without triggering autocmds
  -- this also kills the previous fzf process if its still running
  if not no_wipe then
    utils.nvim_buf_delete(detached, { force = true })
    if self.tsinjector then self.tsinjector.clear_cache(detached) end
  end
  -- in case buffer exists prematurely
  self:set_winleave_autocmd()
  -- automatically resize fzf window
  self:set_redraw_autocmd()
  return self.fzf_bufnr
end

function FzfWin:save_style_minimal(winid)
  return self:get_winopts(winid, {
    number = true,
    relativenumber = true,
    cursorline = true,
    cursorcolumn = true,
    spell = true,
    list = true,
    signcolumn = true,
    foldcolumn = true,
    colorcolumn = true,
    winhl = true, -- for `winopts.split=enew`
  })
end

---@param winid integer
---@param global boolean If true, 'wo' can be inherited by other windows/buffers
function FzfWin:set_style_minimal(winid, global)
  local _ = self
  if not tonumber(winid) or not api.nvim_win_is_valid(winid) then return end
  self:set_winopts(winid, {
    number = false,
    relativenumber = false,
    -- BUG(upstream): causes issues with winopts.split=enew
    -- https://github.com/neovim/neovim/issues/37484
    -- cursorline = false,
    cursorcolumn = false,
    spell = false,
    list = false,
    signcolumn = "no",
    foldcolumn = "0",
    colorcolumn = "",
  }, false, global)
end

function FzfWin:create()
  -- Generate border-label from window title
  self:update_fzf_border_label()
  -- When using fzf-tmux we don't need to create windows
  -- as tmux popups will be used instead
  if self._o._is_fzf_tmux then
    self:setup_keybinds()
    self:set_backdrop()
    return
  end

  if self._reuse then
    -- we can't reuse the fzf term buffer
    -- create a new tmp buffer for the fzf win
    self:set_tmp_buffer()
    self:setup_keybinds()
    -- attach/detach treesitter (e.g. `grep_lgrep`)
    if self._o.winopts.treesitter then
      self:treesitter_attach()
    elseif self.tsinjector then
      self.tsinjector.detach(self.fzf_bufnr)
    end
    -- also recall the user's 'on_create' (#394)
    if self.winopts.on_create and
        type(self.winopts.on_create) == "function" then
      self.winopts.on_create({ winid = self.fzf_winid, bufnr = self.fzf_bufnr })
    end
    -- redraw all window (e.g. when switch from fzf previewer to builtin previewer)
    self:redraw_main()
    self:redraw_preview()
    -- not sure why but when using a split and reusing the window,
    -- fzf will not use all the available width until 'redraw' is
    -- called resulting in misaligned native and builtin previews
    vim.cmd("redraw")
    return self.fzf_bufnr
  end

  -- Set backdrop
  self:set_backdrop()

  -- save sending bufnr/winid
  self.src_bufnr = api.nvim_get_current_buf()
  self.src_winid = api.nvim_get_current_win()

  if self.winopts.split then
    -- save current window layout cmd
    self.winrestcmd = fn.winrestcmd()
    self.cmdheight = vim.o.cmdheight
    -- Store the current window styling options (number, cursor, etc)
    self.src_winid_style = self:save_style_minimal(self.src_winid)
    if type(self.winopts.split) == "function" then
      self.winopts.split()
    else
      vim.cmd(tostring(self.winopts.split))
    end

    local split_bufnr = api.nvim_get_current_buf()
    self.fzf_winid = api.nvim_get_current_win()

    if self.fzf_bufnr and api.nvim_buf_is_valid(self.fzf_bufnr) then
      -- set to fzf bufnr set by `:unhide()`
      utils.win_set_buf_noautocmd(self.fzf_winid, self.fzf_bufnr)
    else
      -- ensure split buffer is a scratch buffer
      self.fzf_bufnr = self:set_tmp_buffer(true)
    end

    -- since we're using our own scratch buf, if the
    -- split command created a new buffer, delete it
    if self.src_bufnr ~= split_bufnr then
      utils.nvim_buf_delete(split_bufnr, { force = true })
    end

    -- match window options with 'nvim_open_win' style:minimal
    self:set_style_minimal(self.fzf_winid, false)
  else
    -- draw the main window
    self:redraw_main()
  end

  -- verify the preview is closed, this can happen
  -- when running async LSP with 'jump1'
  self:set_winleave_autocmd()
  -- automatically resize fzf window
  self:set_redraw_autocmd()
  -- Use treesitter to highlight results on the main fzf window
  self:treesitter_attach()

  self:reset_winhl(self.fzf_winid)

  -- potential workarond for `<C-c>` freezing neovim (#1091)
  -- https://github.com/neovim/neovim/issues/20726
  utils.wo[self.fzf_winid][0].foldmethod = "manual"

  if type(self.winopts.on_create) == "function" then
    self.winopts.on_create({ winid = self.fzf_winid, bufnr = self.fzf_bufnr })
  end

  -- create or redraw the preview win
  self:redraw_preview()

  -- setup the keybinds
  self:setup_keybinds()

  return self.fzf_bufnr
end

function FzfWin:close_preview(do_not_clear_cache)
  self:close_preview_scrollbar()
  if self._previewer and self._previewer.close then
    self._previewer:close(do_not_clear_cache)
  end
  if self.preview_winid and api.nvim_win_is_valid(self.preview_winid) then
    utils.nvim_win_close(self.preview_winid, true)
  end
  self.preview_winid = nil
end

---@param fzf_bufnr? integer
---@param hide? boolean
---@param hidden? boolean
function FzfWin:close(fzf_bufnr, hide, hidden)
  -- When a window is reused, (e.g. open any fzf-lua interface, press <C-\-n> and run
  -- ":FzfLua") `FzfWin:set_tmp_buffer()` will call `nvim_buf_delete` on the original
  -- fzf terminal buffer which will terminate the fzf process and trigger the call to
  -- `fzf_win:close()` within `core.fzf()`. We need to avoid the close in this case.
  if self.closing or (fzf_bufnr and fzf_bufnr ~= self.fzf_bufnr) then return end
  self.closing = true -- prevents race condition
  -- we restore normal mode before exiting fzf due toma neovim bug? whereas
  -- switching from a term win to another term win preserves terminal mode
  -- even if the target window was in normal terminal mode (#2054 #2419)
  local ctx = utils.__CTX() or {}
  if ctx.mode == "nt" then vim.cmd "stopinsert" end
  self:close_help()
  self:close_backdrop()
  self:close_preview(hide)
  -- Abort hidden fzf job?
  if not hide and self._hidden_fzf_bufnr and self._hidden_fzf_bufnr ~= self.fzf_bufnr then
    pcall(api.nvim_buf_delete, self._hidden_fzf_bufnr, { force = true })
  end
  -- Clear treesitter buffer cache and deregister decoration callbacks
  if self.tsinjector then
    self.tsinjector.detach(self._hidden_fzf_bufnr or self.fzf_bufnr)
  end
  -- If this is a hidden buffer closure nothing else to do
  if hidden then return end
  if self.fzf_winid and api.nvim_win_is_valid(self.fzf_winid) then
    -- run in a pcall due to potential errors while closing the window
    -- Vim(lua):E5108: Error executing lua
    -- experienced while accessing 'vim.b[]' from my statusline code
    if self.src_winid == self.fzf_winid then
      -- "split" reused the current win (e.g. "enew")
      -- restore the original buffer and styling options
      self:set_winopts(self.fzf_winid, self.src_winid_style or {}, false)
      -- buf may be invalid if we switched away from a scratch buffer
      if api.nvim_buf_is_valid(self.src_bufnr) then
        -- TODO: why does ignoring events cause the cursor to move to the wrong position?
        -- repro steps: open diag + select and item, open code actions and abort
        -- utils.win_set_buf_noautocmd(self.fzf_winid, self.src_bufnr)
        api.nvim_win_set_buf(self.fzf_winid, self.src_bufnr)
      end
      -- also restore the original alternate buffer
      local alt_bname = (function()
        local alt_bufnr = (utils.__CTX() or {}).alt_bufnr
        if alt_bufnr and api.nvim_buf_is_valid(alt_bufnr) then
          return fn.bufname(alt_bufnr)
        end
      end)()
      if alt_bname and #alt_bname > 0 then
        vim.cmd("balt " .. fn.bufname(alt_bname))
      end
    else
      pcall(api.nvim_win_close, self.fzf_winid, true)
    end
  end
  if self.fzf_bufnr then
    pcall(api.nvim_buf_delete, self.fzf_bufnr, { force = true })
  end
  -- when using `split = "belowright new"` closing the fzf
  -- window may not always return to the correct source win
  -- depending on the user's split configuration (#397)
  if self.winopts.split
      and self.src_winid
      and api.nvim_win_is_valid(self.src_winid)
      and self.src_winid ~= api.nvim_get_current_win()
  then
    api.nvim_set_current_win(self.src_winid)
  end
  if self.winopts.split then
    -- remove all windows from the restore cmd that have been closed in the meantime
    -- if we're not doing this the result might be all over the place
    local winnrs = vim.tbl_map(function(win)
      return api.nvim_win_get_number(win) .. ""
    end, api.nvim_tabpage_list_wins(0))

    local cmd = {}
    for cmd_part in string.gmatch(self.winrestcmd, "[^|]+") do
      local winnr = cmd_part:match("(.)resize")
      if utils.tbl_contains(winnrs, winnr) then
        table.insert(cmd, cmd_part)
      end
    end

    vim.cmd(table.concat(cmd, "|"))

    -- Also restore cmdheight, will be wrong if vim resized (#1462)
    vim.o.cmdheight = self.cmdheight
  end
  if self.hls_on_close then
    -- restore search highlighting if we disabled it
    -- use `vim.o.hlsearch` as `vim.cmd("hls")` is invalid
    vim.o.hlsearch = true
    self.hls_on_close = nil
  end
  if type(self.winopts.on_close) == "function" then
    self.winopts.on_close()
  end
  self.closing = nil
  self._reuse = nil
  _self = nil
end

function FzfWin:detach_fzf_buf()
  self._hidden_fzf_bufnr = self.fzf_bufnr
  vim.bo[self._hidden_fzf_bufnr].bufhidden = ""
  self:set_tmp_buffer(true)
end

function FzfWin:hide()
  if self:hidden() then return end
  -- Note: we should never get here with a tmux profile as neovim binds (default: <A-Esc>)
  -- do not apply to tmux, validate anyways in case called directly using the API
  if not self or self._o._is_fzf_tmux then return end
  self:detach_fzf_buf()
  self:close(nil, true)
  self:save_size()
  -- Save self as `:close()` nullifies it
  _self = self
end

function FzfWin:save_size()
  -- save the current window size (VimResized won't emit when buffer hidden)
  self._last_view = { vim.o.lines, vim.o.columns, vim.o.cmdheight }
end

function FzfWin:resized()
  return not vim.deep_equal(self._last_view, { vim.o.lines, vim.o.columns, vim.o.cmdheight })
end

function FzfWin:hidden()
  return self._hidden_fzf_bufnr and api.nvim_buf_is_valid(self._hidden_fzf_bufnr)
end

-- True after a `:new()` call for a different picker, used in `core.fzf`
-- to avoid post processing an fzf process that was discarded (e.g. kill by :%bw!)
function FzfWin:was_hidden()
  return self._hidden_fzf_bufnr and not api.nvim_buf_is_valid(self._hidden_fzf_bufnr)
end

---SIGWINCH/on_SIGWINCH is nop if fzf < v0.46
---@param opts fzf-lua.config.Resolved|{}
---@param scope string? nil means on any sigwinch
---@param cb function
---@return boolean?
function FzfWin.on_SIGWINCH(opts, scope, cb)
  if not utils.has(opts, "fzf", { 0, 46 }) then return end
  local first = not opts.__sigwinch_on_scope
  opts.__sigwinch_on_scope = opts.__sigwinch_on_scope or {}
  opts.__sigwinch_on_any = opts.__sigwinch_on_any or {}
  if type(scope) == "string" then
    local s = opts.__sigwinch_on_scope
    if s[scope] then return end
    -- if s[scope] then error("duplicated handler: " .. scope) end
    s[scope] = cb
  else
    local s = opts.__sigwinch_on_any
    s[#s + 1] = cb
  end
  if not first then return true end
  opts._fzf_cli_args = opts._fzf_cli_args or {}
  table.insert(opts._fzf_cli_args, "--bind="
    .. libuv.shellescape("resize:+transform:" .. FzfLua.shell.stringify_data(function(args)
      local scopes = opts.__sigwinches or {}
      local acts = vim.tbl_map(function(k) return opts.__sigwinch_on_scope[k](args) end, scopes)
      opts.__sigwinches = nil
      acts = vim.tbl_filter(function(a) return a and #a > 0 end, acts)
      local anys = vim.tbl_map(function(h) return h(args) end, opts.__sigwinch_on_any)
      anys = vim.tbl_filter(function(a) return a and #a > 0 end, anys)
      vim.list_extend(anys, acts)
      return table.concat(anys, "+")
    end, opts, utils.__IS_WINDOWS and "%FZF_PREVIEW_LINES%" or "$FZF_PREVIEW_LINES")))
  return true
end

---@param scopes string[]?
---@return boolean?
function FzfWin:SIGWINCH(scopes)
  -- avoid racing when multiple SIGWINCH trigger at the same time
  if not utils.has(self._o, "fzf", { 0, 46 }) or self._o.__sigwinches then return end
  local bufnr = self._hidden_fzf_bufnr or self.fzf_bufnr
  if not bufnr or not api.nvim_buf_is_valid(bufnr) then return end
  local ok, pid = pcall(fn.jobpid, vim.bo[bufnr].channel)
  if ok and pid > 0 then ---@cast pid integer
    self._o.__sigwinches = scopes or {}
    vim.tbl_map(function(_pid) libuv.process_kill(_pid, 28) end, api.nvim_get_proc_children(pid))
  end
  return true
end

function FzfWin:unhide()
  if not self:hidden() then return end
  self._o.__CTX = utils.CTX({ includeBuflist = true })
  -- Send SIGWINCH to to trigger resize in the fzf process
  -- We will use the trigger to reload necessary buffer lists
  self:SIGWINCH({ "win.unhide" })
  vim.bo[self._hidden_fzf_bufnr].bufhidden = "wipe"
  self.fzf_bufnr = self._hidden_fzf_bufnr
  self._hidden_fzf_bufnr = nil
  self:create()
  if self:resized() then self:redraw() end
  vim.cmd("startinsert")
  return true
end

---@diagnostic disable-next-line: unused
function FzfWin:close_preview_scrollbar()
  require("fzf-lua.win.scrollbar").close()
end

function FzfWin:update_preview_scrollbar()
  if not self:validate_preview() then return end
  require("fzf-lua.win.scrollbar").update(self.preview_winid, self.hls, self.winopts)
end

function FzfWin:update_statusline()
  if not self.winopts.split then
    -- NOTE: 0.12 added float win local statusline, we nullify the statusline here and
    -- not after `nvim_open_win` in case the user also has fzf.vim installed which sets
    -- the statusline on WinEnter
    if utils.__HAS_NVIM_012 and #api.nvim_win_get_config(self.fzf_winid).relative > 0 then
      vim.wo[self.fzf_winid].statusline = ""
    end
    return
  end
  local titlestr = self.winopts.title or (" %s "):format(tostring(FzfLua.get_info().cmd))
  local title = make_title(titlestr, self.hls.title)
  local parts = vim.tbl_map(function(p) return ("%%#%s#%s%%#fzf3#"):format(p[2], p[1]) end, title)
  local picker = table.remove(parts, 1) or ""
  vim.wo[self.fzf_winid].statusline = "%#fzf1# > %#fzf2#fzf-lua%#fzf3#"
      .. string.format(" %s %s", picker, table.concat(parts, ""))
end

function FzfWin:update_fzf_border_label()
  if not utils.has(self._o, "fzf", { 0, 35 })
      or not self._o.fzf_opts["--border"]
      or self._o.fzf_opts["--border-label"] == false
  then
    return
  end
  local titlestr = self.winopts.title or (" %s "):format(tostring(FzfLua.get_info().cmd))
  local title = make_title(titlestr, self.hls.title)
  local parts = vim.tbl_map(function(p) return (utils.ansi_from_hl(p[2], p[1])) end, title)
  self._o.fzf_opts["--border-label"] = table.concat(parts, " ")
end

function FzfWin:update_main_title(title)
  -- Can be called from fzf-tmux on ctrl-g
  if not self:validate() or self.winopts.split then return end
  self.winopts.title = title
  self._o.winopts.title = title
  -- NOTE: <0.11 fail without top border: "title requires border to be set"
  utils.win_set_config(self.fzf_winid, {
    title = make_title(title, self.hls.title),
    title_pos = self.winopts.title_pos,
    border = not utils.__HAS_NVIM_011
        and (api.nvim_win_get_config(self.fzf_winid).border or "none") or nil,
  })
end

function FzfWin:update_preview_title(title)
  if not self:validate_preview() or not self._previewer then return end
  -- NOTE: <0.11 fail without top border: "title requires border to be set"
  utils.win_set_config(self.preview_winid, {
    title = make_title(title, self.hls.preview_title),
    title_pos = self.winopts.preview.title_pos,
    border = not utils.__HAS_NVIM_011
        and (api.nvim_win_get_config(self.preview_winid).border or "none") or nil,
  })
end

-- keybind methods below
function FzfWin:toggle_fullscreen()
  self.fullscreen = not self.fullscreen
  self:redraw()
end

function FzfWin:focus_preview()
  api.nvim_set_current_win(self.preview_winid)
end

function FzfWin:toggle_preview()
  self.preview_hidden = not self.preview_hidden
  if self._fzf_toggle_prev_bind then
    -- 1. Toggle the empty preview window (under the neovim preview buffer)
    -- 2. Trigger resize to cange the preview layout if needed (toggle -> resize -> toggle)
    local feedkey
    if utils.__IS_WINDOWS then
      self:SIGWINCH({})
      feedkey = true
    elseif not self:SIGWINCH({ "toggle-preview" }) then
      feedkey = true
    end
    if feedkey and type(self._fzf_toggle_prev_bind) == "string" then
      utils.feed_keys_termcodes(self._fzf_toggle_prev_bind)
    elseif feedkey and not self._o.silent then
      utils.warn("missing 'toggle-preview' in opts.keymap.fzf or opts.keymap.builtin")
    end
    -- TODO: this don't work with <a-x> or <fxx> (wrong keycode)
    -- api.nvim_chan_send(vim.bo.channel, vim.keycode(self._fzf_toggle_prev_bind))
  end
  if self.preview_hidden then
    if self:validate_preview() then self:close_preview(true) end
    self:redraw_main()
  elseif not self.preview_hidden then
    self:redraw_main()
    self:redraw_preview()
  end
end

function FzfWin:toggle_preview_wrap()
  if not self:validate_preview() then return end
  self.preview_wrap = not utils.wo[self.preview_winid].wrap
  utils.wo[self.preview_winid].wrap = self.preview_wrap
end

---@param direction integer
function FzfWin:toggle_preview_cw(direction)
  local curpos = self:normalize_preview_layout().pos
  local pos = { "up", "right", "down", "left" }
  local idx ---@type integer
  for i = 1, #pos do
    if pos[i] == curpos then
      idx = i
      break
    end
  end
  if not idx then return end
  local newidx = direction > 0 and idx + 1 or idx - 1
  if newidx < 1 then newidx = #pos end
  if newidx > #pos then newidx = 1 end
  self._preview_pos_force = pos[newidx]
  if self.winopts.split or not self.previewer_is_builtin then
    self:SIGWINCH({ "toggle-preview-cw" })
  end
  self:redraw()
end

function FzfWin:toggle_preview_behavior()
  self.toggle_behavior = not self.toggle_behavior and "extend" or nil
  utils.info("preview toggle behavior set to %s", self.toggle_behavior or "default")
  self:redraw()
end

function FzfWin:toggle_preview_ts_ctx()
  if self:validate_preview()
      and self._previewer
      and self._previewer.ts_ctx_toggle then
    self._previewer:ts_ctx_toggle()
  end
end

function FzfWin:toggle_preview_undo_diff()
  if self:validate_preview()
      and self._previewer
      ---@diagnostic disable-next-line: undefined-field
      and self._previewer.toggle_undo_diff then
    ---@diagnostic disable-next-line: undefined-field
    self._previewer:toggle_undo_diff()
  end
end

---@param num integer
function FzfWin:preview_ts_ctx_inc_dec(num)
  if self:validate_preview()
      and self._previewer
      and self._previewer.ts_ctx_inc_dec_maxlines then
    self._previewer:ts_ctx_inc_dec_maxlines(num)
  end
end

---@alias fzf-lua.win.direction "top"|"bottom"|"half-page-up"|"half-page-down"|"page-up"|"page-down"|"line-up"|"line-down"|"reset"
---@param direction fzf-lua.win.direction
function FzfWin:preview_scroll(direction)
  if self:validate_preview()
      and self._previewer
      and self._previewer.scroll then
    -- Do not trigger "ModeChanged"
    utils.eventignore(function() self._previewer:scroll(direction) end)
  end
end

---@diagnostic disable-next-line: unused
function FzfWin:close_help()
  require("fzf-lua.win.help").close()
end

function FzfWin:toggle_help()
  local zindex = self.winopts.zindex + 2
  local mode = self.previewer_is_builtin and "builtin" or "fzf"
  local help = require("fzf-lua.win.help")
  help.toggle(self.keymap, self.actions, self.hls, zindex, _preview_keymaps, mode,
    self._o.help_open_win)
end

---@type fzf-lua.win.api
local M = setmetatable({}, {
  __index = function(m, k)
    rawset(m, k, FzfLua._exported_wapi[k] and function(...)
      if not _self then return end
      return _self[k](_self, ...)
    end or FzfWin[k])
    return rawget(m, k)
  end,
})

return M
