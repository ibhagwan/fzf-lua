local path = require "fzf-lua.path"
local utils = require "fzf-lua.utils"
local config = require "fzf-lua.config"
local actions = require "fzf-lua.actions"

local api = vim.api
local fn = vim.fn

local TSInjector = {}

---@type table<number, table<string,{parser: vim.treesitter.LanguageTree, highlighter:vim.treesitter.highlighter, enabled:boolean}>>
TSInjector.cache = {}

function TSInjector.setup()
  if TSInjector._setup then return true end

  TSInjector._setup = true
  TSInjector._ns = TSInjector._ns or vim.api.nvim_create_namespace("fzf-lua.win.highlighter")

  local function wrap_ts_hl_callback(name)
    return function(_, win, buf, ...)
      -- print(name, buf, win, TSInjector.cache[buf])
      if not TSInjector.cache[buf] then
        return false
      end
      for _, hl in pairs(TSInjector.cache[buf] or {}) do
        if hl.enabled then
          vim.treesitter.highlighter.active[buf] = hl.highlighter
          vim.treesitter.highlighter[name](_, win, buf, ...)
        end
      end
      vim.treesitter.highlighter.active[buf] = nil
    end
  end

  vim.api.nvim_set_decoration_provider(TSInjector._ns, {
    on_win = wrap_ts_hl_callback("_on_win"),
    on_line = wrap_ts_hl_callback("_on_line"),
  })

  return true
end

function TSInjector.deregister()
  if not TSInjector._ns then return end
  vim.api.nvim_set_decoration_provider(TSInjector._ns, { on_win = nil, on_line = nil })
  TSInjector._setup = nil
end

function TSInjector.clear_cache(buf, noassert)
  -- If called from fzf-tmux buf will be `nil` (#1556)
  if not buf then return end
  TSInjector.cache[buf] = nil
  -- If called from `FzfWin.hide` cache will not be empty
  assert(noassert or utils.tbl_isempty(TSInjector.cache))
end

---@param buf number
function TSInjector.attach(buf, regions)
  if not TSInjector.setup() then return end

  TSInjector.cache[buf] = TSInjector.cache[buf] or {}
  for lang, _ in pairs(TSInjector.cache[buf]) do
    TSInjector.cache[buf][lang].enabled = regions[lang] ~= nil
  end

  for lang, _ in pairs(regions) do
    TSInjector._attach_lang(buf, lang, regions[lang])
  end
end

---@param buf number
---@param lang? string
function TSInjector._attach_lang(buf, lang, regions)
  if not TSInjector.cache[buf][lang] then
    local ok, parser = pcall(vim.treesitter.languagetree.new, buf, lang)
    if not ok then return end
    TSInjector.cache[buf][lang] = {
      parser = parser,
      highlighter = vim.treesitter.highlighter.new(parser),
    }
  end

  local parser = TSInjector.cache[buf][lang].parser
  if not parser then return end

  TSInjector.cache[buf][lang].enabled = true
  parser:set_included_regions(regions)
end

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
  ["toggle-preview"]         = { module = "win", fnc = "toggle_preview()" },
  ["toggle-preview-wrap"]    = { module = "win", fnc = "toggle_preview_wrap()" },
  ["toggle-preview-cw"]      = { module = "win", fnc = "toggle_preview_cw(1)" },
  ["toggle-preview-ccw"]     = { module = "win", fnc = "toggle_preview_cw(-1)" },
  ["toggle-preview-ts-ctx"]  = { module = "win", fnc = "toggle_preview_ts_ctx()" },
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
}

function FzfWin:setup_keybinds()
  if not self:validate() then return end
  self.keymap = type(self.keymap) == "table" and self.keymap or {}
  self.keymap.fzf = type(self.keymap.fzf) == "table" and self.keymap.fzf or {}
  self.keymap.builtin = type(self.keymap.builtin) == "table" and self.keymap.builtin or {}
  local keymap_tbl = {
    ["hide"]              = { module = "win", fnc = "hide()" },
    ["toggle-help"]       = { module = "win", fnc = "toggle_help()" },
    ["toggle-fullscreen"] = { module = "win", fnc = "toggle_fullscreen()" },
  }
  -- find the toggle_preview keybind, to be sent when using a split for the native
  -- pseudo fzf preview window or when using native and treesitter is enabled
  if self.winopts.split or not self.previewer_is_builtin and self.winopts.treesitter then
    for k, v in pairs(self.keymap.fzf) do
      if v == "toggle-preview" then
        self._fzf_toggle_prev_bind = utils.fzf_bind_to_neovim(k)
        keymap_tbl = vim.tbl_deep_extend("keep", keymap_tbl, {
          ["toggle-preview"] = { module = "win", fnc = "toggle_preview()" },
        })
      end
    end
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
      utils.keymap_set("t", key, funcref_str(keymap), { nowait = true, buffer = self.fzf_bufnr })
    end
  end

  -- If the user did not override the Esc action ensure it's
  -- not bound to anything else such as `<C-\><C-n>` (#663)
  if self.actions["esc"] == actions.dummy_abort and not self.keymap.builtin["<esc>"] then
    utils.keymap_set("t", "<Esc>", "<Esc>", { buffer = self.fzf_bufnr, nowait = true })
  end
end

function FzfWin:generate_layout(winopts)
  local pwopts
  local row, col = winopts.row, winopts.col
  local height, width = winopts.height, winopts.width
  local preview_pos, preview_size = (function()
    -- @return preview_pos:  preview position {left|right|up|down}
    -- @return preview_size: preview size in %
    local preview_str
    if self._preview_pos_force then
      -- Get the correct layout string and size when set from `:toggle_preview_cw`
      preview_str = (self._preview_pos_force == "up" or self._preview_pos_force == "down")
          and winopts.preview.vertical or winopts.preview.horizontal
      self._preview_pos = self._preview_pos_force
    else
      preview_str = self:fzf_preview_layout_str()
      self._preview_pos = preview_str:match("[^:]+") or "right"
    end
    self._preview_size = tonumber(preview_str:match(":(%d+)%%")) or 50
    return self._preview_pos, self._preview_size
  end)()
  if winopts.split then
    -- Custom "split"
    pwopts = { relative = "win", anchor = "NW", row = 1, col = 1 }
    if preview_pos == "down" or preview_pos == "up" then
      pwopts.width = width - 2
      pwopts.height = utils.round((height) * preview_size / 100, math.huge) - 2
      if preview_pos == "down" then
        pwopts.row = height - pwopts.height - 1
      end
    else -- left|right
      pwopts.height = height - 2
      pwopts.width = utils.round(width * preview_size / 100, math.huge) - 2
      if preview_pos == "right" then
        pwopts.col = width - pwopts.width - 1 + winopts.signcol_width
      end
    end
  else
    -- Float window
    pwopts = { relative = "editor" }
    if preview_pos == "down" or preview_pos == "up" then
      height = height - 2
      pwopts.col = col + 1 -- +border
      pwopts.width = width
      pwopts.height = utils.round((height) * preview_size / 100, 0.5)
      height = height - pwopts.height
      if preview_pos == "down" then
        -- next row +2xborder
        pwopts.row = row + 1 + height + 2
      else                   -- up
        pwopts.row = row + 1 -- +border
        row = pwopts.row + 1 + pwopts.height
      end
    else                   -- left|right
      width = width - 2
      pwopts.row = row + 1 -- +border
      pwopts.height = height
      pwopts.width = utils.round(width * preview_size / 100, 0.5)
      width = width - pwopts.width
      if preview_pos == "right" then
        -- next col +2xborder
        pwopts.col = col + 1 + width + 2
      else                   -- left
        pwopts.col = col + 1 -- +border
        col = pwopts.col + 1 + pwopts.width
      end
    end
  end
  return {
    fzf = { row = row, col = col, height = height, width = width },
    preview = pwopts,
  }
end

local strip_borderchars_hl = function(border)
  local default = nil
  if type(border) == "string" then
    default = config.globals.__WINOPTS.borderchars[border]
  end
  if not default then
    default = config.globals.__WINOPTS.borderchars["rounded"]
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

function FzfWin:columns(no_fullscreen)
  assert(self.winopts)
  -- When called from `core.preview_window` we need to get the no-fullscreen columns
  -- in order to get an accurate alternate layout trigger that will also be consistent
  -- when starting with `winopts.fullscreen == true`
  local winopts = no_fullscreen and self:normalize_winopts(false) or self.winopts
  return self._o._is_fzf_tmux and self._o._is_fzf_tmux_popup and self._o._tmux_columns
      or winopts.split and vim.api.nvim_win_get_width(self.fzf_winid or 0)
      or winopts.width
end

function FzfWin:fzf_preview_layout_str()
  assert(self.winopts)
  local columns = self:columns()
  local is_hsplit = self.winopts.preview.layout == "horizontal"
      or self.winopts.preview.layout == "flex" and columns > self.winopts.preview.flip_columns
  return is_hsplit and self._o.winopts.preview.horizontal or self._o.winopts.preview.vertical
end

function FzfWin:normalize_winopts(fullscreen)
  -- make a local copy of winopts so we don't pollute the user's options
  local o, winopts = self._o, utils.tbl_deep_clone(self._o.winopts)

  if fullscreen then
    winopts.row = 1
    winopts.col = 1
    winopts.width = 1
    winopts.height = 1
  end

  winopts.__winhls = {
    main = {
      { "Normal",       o.hls.normal },
      { "NormalFloat",  o.hls.normal },
      { "FloatBorder",  o.hls.border },
      { "CursorLine",   o.hls.cursorline },
      { "CursorLineNr", o.hls.cursorlinenr },
    },
    prev = {
      { "Normal",       o.hls.preview_normal },
      { "NormalFloat",  o.hls.preview_normal },
      { "FloatBorder",  o.hls.preview_border },
      { "CursorLine",   o.hls.cursorline },
      { "CursorLineNr", o.hls.cursorlinenr },
    },
    -- our border is manually drawn so we need
    -- to replace Normal with the border color
    prev_border = {
      { "Normal",      o.hls.preview_border },
      { "NormalFloat", o.hls.preview_border }
    },
  }

  -- add title hl if wasn't provided by the user
  if type(winopts.title) == "string" and type(o.hls.title) == "string" then
    winopts.title = { { winopts.title, o.hls.title } }
  end

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
      winopts.row = math.floor((vim.o.lines - winopts.height - 2) * winopts.row)
    end
    if not winopts.col or winopts.col <= 1 then
      winopts.col = math.floor((vim.o.columns - winopts.width - 2) * winopts.col)
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

  -- when ambiwdith="double" `nvim_open_win` with border chars fails:
  -- with "border chars must be one cell", force string border (#874)
  if vim.o.ambiwidth == "double" then
    if type(winopts.border) == "table" then
      local topleft = winopts.border[1]
      winopts.border = topleft and config.globals.__WINOPTS.border2string[topleft] or "rounded"
    end
    winopts._border = winopts.border
  elseif type(winopts.border) == "string" then
    -- We only allow 'none|empty|single|double|rounded|thicc|thiccc|thiccc'
    winopts.border = config.globals.__WINOPTS.borderchars[winopts.border] or
        config.globals.__WINOPTS.borderchars["rounded"]
  end

  -- Store a version of borderchars with no highlights
  -- to be used in the border drawing functions
  winopts.nohl_borderchars = strip_borderchars_hl(winopts.border)

  return winopts
end

function FzfWin:reset_win_highlights(win)
  -- derive the highlights from the window type
  local key = "main"
  if win == self.preview_winid then
    key = "prev"
  elseif win == self.border_winid then
    key = "prev_border"
  end
  local hl
  for _, h in ipairs(self.winopts.__winhls[key]) do
    if h[2] then
      hl = string.format("%s%s:%s", hl and hl .. "," or "", h[1], h[2])
    end
  end
  vim.wo[win].winhighlight = hl
end

---@param exit_code integer
---@param fzf_bufnr integer
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
    local lines = vim.api.nvim_buf_get_lines(self.fzf_bufnr, 0, 1, false)
    utils.warn(string.format("fzf error %d: %s", exit_code,
      lines and #lines[1] > 0 and lines[1] or "<null>"))
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

function FzfWin:set_backdrop()
  -- No backdrop for split, only floats / tmux
  if self.winopts.split then return end
  -- Called from redraw?
  if self.backdrop_win then
    if vim.api.nvim_win_is_valid(self.backdrop_win) then
      vim.api.nvim_win_set_config(self.backdrop_win, {
        width = vim.o.columns,
        height = vim.o.lines,
      })
    end
    return
  end

  -- Validate backdrop hlgroup and opacity
  self.hls.backdrop = type(self.hls.backdrop) == "string"
      and self.hls.backdrop or "FzfLuaBackdrop"
  self.winopts.backdrop = tonumber(self.winopts.backdrop)
      or self.winopts.backdrop == true and 60
      or 100
  if self.winopts.backdrop < 0 or self.winopts.backdrop > 99 then return end

  -- Neovim bg has no color, will look weird
  if #utils.hexcol_from_hl("Normal", "bg") == 0 then return end

  -- Code from lazy.nvim (#1344)
  self.backdrop_buf = vim.api.nvim_create_buf(false, true)
  self.backdrop_win = vim.api.nvim_open_win(self.backdrop_buf, false, {
    relative = "editor",
    width = vim.o.columns,
    height = vim.o.lines,
    row = 0,
    col = 0,
    style = "minimal",
    focusable = false,
    -- -2 as preview border is -1
    zindex = self.winopts.zindex - 2,
  })
  utils.wo(self.backdrop_win, "winhighlight", "Normal:" .. self.hls.backdrop)
  utils.wo(self.backdrop_win, "winblend", self.winopts.backdrop)
  vim.bo[self.backdrop_buf].buftype = "nofile"
  vim.bo[self.backdrop_buf].filetype = "fzflua_backdrop"
end

function FzfWin:close_backdrop()
  if not self.backdrop_win or not self.backdrop_buf then return end
  if self.backdrop_win and vim.api.nvim_win_is_valid(self.backdrop_win) then
    vim.api.nvim_win_close(self.backdrop_win, true)
  end
  if self.backdrop_buf and vim.api.nvim_buf_is_valid(self.backdrop_buf) then
    vim.api.nvim_buf_delete(self.backdrop_buf, { force = true })
  end
  self.backdrop_buf = nil
  self.backdrop_win = nil
  -- vim.cmd("redraw")
end

local function opt_matches(opts, key, str)
  local opt = opts.winopts.preview[key] or config.globals.winopts.preview[key]
  return opt and opt:match(str)
end

---@alias FzfWin table
---@param o table
---@return FzfWin
function FzfWin:new(o)
  if _self and not _self:hidden() then
    -- utils.warn("Please close fzf-lua before starting a new instance")
    _self._reuse = true
    -- refersh treesitter settings as new picker might have it disabled
    _self._o.winopts.treesitter = o.winopts.treesitter
    return _self
  elseif _self and _self:hidden() then
    -- Clear the hidden buffers
    vim.api.nvim_buf_delete(_self._hidden_fzf_bufnr, { force = true })
    TSInjector.clear_cache(_self._hidden_fzf_bufnr)
    _self = nil
  end
  o = o or {}
  self._o = o
  self = setmetatable({}, { __index = self })
  self.hls = o.hls
  self.actions = o.actions
  self.fullscreen = o.winopts.fullscreen
  self.winopts = self:normalize_winopts(self.fullscreen)
  self.preview_wrap = not opt_matches(o, "wrap", "nowrap")
  self.preview_hidden = not opt_matches(o, "hidden", "nohidden")
  self.preview_border = not opt_matches(o, "border", "noborder")
  self.keymap = o.keymap
  self.previewer = o.previewer
  self.prompt = o.prompt or o.fzf_opts["--prompt"]
  self:_set_autoclose(o.autoclose)
  -- Backward compat since removal of "border" scrollbar
  if self.winopts.preview.scrollbar == "border" then
    self.winopts.preview.scrollbar = "float"
    self.winopts.preview.scrolloff = -1
    self.winopts.preview._scroll_hide_empty = true
    self.hls.scrollfloat_f = false
    -- Reverse "FzfLuaScrollBorderFull" color
    if type(self.hls.scrollborder_f) == "string" then
      local fg = utils.hexcol_from_hl(self.hls.scrollborder_f, "fg")
      local bg = utils.hexcol_from_hl(self.hls.scrollborder_f, "bg")
      if fg and #fg > 0 then
        local hlgroup = "FzfLuaScrollBorderBackCompat"
        self.hls.scrollfloat_f = hlgroup
        if utils.__HAS_NVIM_07 then
          vim.api.nvim_set_hl(0, hlgroup,
            vim.o.termguicolors and { default = false, fg = bg, bg = fg }
            or { default = false, ctermfg = tonumber(bg), ctermbg = tonumber(fg) })
        else
          if vim.o.termguicolors then
            vim.cmd(string.format("hi! %s guifg=%s guibg=%s", hlgroup, bg, fg))
          else
            vim.cmd(string.format("hi! %s %s %s", hlgroup,
              tonumber(bg) and "ctermfg=" .. tostring(bg),
              tonumber(fg) and "ctermbg=" .. tostring(fg)))
          end
        end
      end
    end
  end
  _self = self
  return self
end

function FzfWin:get_winopts(win, opts)
  if not win or not api.nvim_win_is_valid(win) then return end
  local ret = {}
  for opt, _ in pairs(opts) do
    if utils.nvim_has_option(opt) then
      ret[opt] = vim.wo[win][opt]
    end
  end
  return ret
end

function FzfWin:set_winopts(win, opts)
  if not win or not api.nvim_win_is_valid(win) then return end
  for opt, value in pairs(opts) do
    if utils.nvim_has_option(opt) then
      -- PROBABLY DOESN'T MATTER (WHO USES 0.5?) BUT WHY NOT LOL
      -- minor backward compatibility fix, with neovim version < 0.7
      -- nvim_win_get_option("scroloff") which should return -1
      -- returns an invalid (really big number instead which panics
      -- when called with nvim_win_set_option, wrapping in a pcall
      -- ensures this plugin still works for neovim version as low as 0.5!
      pcall(function() vim.wo[win][opt] = value end)
    end
  end
end

function FzfWin:attach_previewer(previewer)
  -- clear the previous previewer if existed
  if self._previewer and self._previewer.close then
    -- if we press ctrl-g too quickly 'previewer.preview_bufnr' will be nil
    -- and even though the temp buffer is set to 'bufhidden:wipe' the buffer
    -- won't be closed properly and remain lingering (visible in `:ls!`)
    -- make sure the previewer is aware of this buffer
    if not self._previewer.preview_bufnr and self:validate_preview() then
      self._previewer.preview_bufnr = vim.api.nvim_win_get_buf(self.preview_winid)
    end
    self._previewer:close()
  end
  if self._previewer and self._previewer.win_leave then
    self._previewer:win_leave()
  end
  self._previewer = previewer
  self.previewer_is_builtin = previewer and type(previewer.display_entry) == "function"
end

function FzfWin:preview_layout()
  if self.winopts.split and self.previewer_is_builtin then
    local wininfo = utils.getwininfo(self.fzf_winid)
    -- unlike floating win popups, split windows inherit the global
    -- 'signcolumn' setting which affects the available width for fzf
    -- 'generate_layout' will then use the sign column available width
    -- to assure a perfect alignment of the builtin previewer window
    -- and the dummy native fzf previewer window border underneath it
    local signcol_width = vim.wo[self.fzf_winid].signcolumn == "yes" and 1 or 0
    self.layout = self:generate_layout({
      row = wininfo.winrow,
      col = wininfo.wincol + signcol_width,
      height = wininfo.height,
      width = api.nvim_win_get_width(self.fzf_winid) - signcol_width,
      signcol_width = signcol_width,
      split = self.winopts.split,
    })
  end
  if not self.layout then return {}, {} end

  local preview_opts = vim.tbl_extend("force", self.layout.preview, {
    zindex = self.winopts.zindex,
    style = "minimal",
    focusable = true,
  })
  local border_winopts = {
    zindex = self.winopts.zindex - 1,
    style = "minimal",
    focusable = false,
    relative = self.layout.preview.relative,
    anchor = self.layout.preview.anchor,
    width = self.layout.preview.width + 2,
    height = self.layout.preview.height + 2,
    col = self.layout.preview.col - 1,
    row = self.layout.preview.row - 1,
  }
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

function FzfWin:redraw_preview_border()
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
  api.nvim_buf_set_lines(border_buf, 0, -1, true, lines)
  -- reset botder window highlights
  if self.border_winid and vim.api.nvim_win_is_valid(self.border_winid) then
    vim.fn.clearmatches(self.border_winid)
  end
  return border_buf
end

function FzfWin:redraw_preview()
  if not self.previewer_is_builtin or self.preview_hidden then return end

  self.prev_winopts, self.border_winopts = self:preview_layout()
  if utils.tbl_isempty(self.prev_winopts) or utils.tbl_isempty(self.border_winopts) then
    return -1, -1
  end

  -- manual border chars looks horrible with ambiwdith="double", override border
  -- window with preview window dimensions and use builtin `nvim_open_win` border
  -- NOTES:
  --    (1) there will be no border scroll
  --    (2) preview title only when nvim >= 0.9
  if vim.o.ambiwidth == "double" then
    assert(type(self.winopts._border) == "string")
    self.prev_winopts = vim.tbl_extend("force", self.prev_winopts, {
      col = self.border_winopts.col,
      row = self.border_winopts.row,
      border = self.winopts._border,
    })
    self.prev_single_win = true
  end

  if self:validate_preview() then
    self.border_buf = api.nvim_win_get_buf(self.border_winid)
    self:redraw_preview_border()
    api.nvim_win_set_config(self.border_winid, self.border_winopts)
    -- since `nvim_win_set_config` removes all styling, save backup
    -- of the current options and restore after the call (#813)
    local style = self:get_winopts(self.preview_winid, self._previewer:gen_winopts())
    api.nvim_win_set_config(self.preview_winid, self.prev_winopts)
    self:set_winopts(self.preview_winid, style)
  else
    local tmp_buf = api.nvim_create_buf(false, true)
    -- No autocmds, can only be sent with 'nvim_open_win'
    self.prev_winopts.noautocmd = true
    self.border_winopts.noautocmd = true
    vim.bo[tmp_buf].bufhidden = "wipe"
    self.border_buf = self:redraw_preview_border()
    self.preview_winid = api.nvim_open_win(tmp_buf, false, self.prev_winopts)
    self.border_winid = api.nvim_open_win(self.border_buf, false, self.border_winopts)
    -- Add win local var for the preview|border windows
    api.nvim_win_set_var(self.preview_winid, "fzf_lua_preview", true)
    api.nvim_win_set_var(self.border_winid, "fzf_lua_preview", true)
  end
  self:reset_win_highlights(self.border_winid)
  self:reset_win_highlights(self.preview_winid)
  self._previewer:display_last_entry()
  return self.preview_winid, self.border_winid
end

function FzfWin:validate()
  return self.fzf_winid and self.fzf_winid > 0
      and api.nvim_win_is_valid(self.fzf_winid)
end

function FzfWin:redraw()
  self.winopts = self:normalize_winopts(self.fullscreen)
  if not self.winopts.split and self.previewer_is_builtin then
    self.layout = self:generate_layout(self.winopts)
  end
  self:set_backdrop()
  self:hide_scrollbar()
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

  local win_opts = {
    width = winopts.width or math.min(columns - 4, math.max(80, columns - 20)),
    height = winopts.height or math.min(lines - 4, math.max(20, lines - 10)),
    style = "minimal",
    relative = relative,
    border = self.winopts.border,
    zindex = self.winopts.zindex,
    title = utils.__HAS_NVIM_09 and self.winopts.title or nil,
    title_pos = utils.__HAS_NVIM_09 and self.winopts.title_pos or nil,
  }
  win_opts.row = winopts.row or math.floor(((lines - win_opts.height) / 2) - 1)
  win_opts.col = winopts.col or math.floor((columns - win_opts.width) / 2)

  -- When border chars are empty strings 'nvim_open_win' adjusts
  -- the layout to take all available space, we use these to adjust
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
    self.fzf_bufnr = self.fzf_bufnr or vim.api.nvim_create_buf(false, true)
    self.fzf_winid = utils.nvim_open_win(self.fzf_bufnr, true, win_opts)
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
    if vim.o.cursorline ~= cursorline then
      vim.o.cursorline = cursorline
    end
  end
end

function FzfWin:_nvim_create_autocmd(e, callback, vimL)
  local augroup = "FzfLua" .. e
  if utils.__HAS_NVIM_07 then
    vim.api.nvim_create_autocmd(e, {
      group = vim.api.nvim_create_augroup(augroup, { clear = true }),
      buffer = self.fzf_bufnr,
      callback = callback,
    })
  else
    vim.cmd("augroup " .. augroup)
    vim.cmd("au!")
    vim.cmd(string.format([[au %s <buffer=%d> lua %s]], e, self.fzf_bufnr, vimL))
    vim.cmd("augroup END")
  end
end

function FzfWin:set_redraw_autocmd()
  self:_nvim_create_autocmd("VimResized",
    function() self:redraw() end,
    [[require("fzf-lua").redraw()]])
end

function FzfWin:set_winleave_autocmd()
  self:_nvim_create_autocmd("WinLeave", self.win_leave, [[require('fzf-lua.win').win_leave()]])
end

function FzfWin:treesitter_detach(buf, noassert)
  TSInjector.clear_cache(buf, noassert)
  TSInjector.deregister()
end

function FzfWin:treesitter_attach()
  if not utils.__HAS_NVIM_09 then return end
  if not self._o.winopts.treesitter then return end
  -- local utf8 = require("fzf-lua.lib.utf8")
  local function trim(s) return (string.gsub(s, "^%s*(.-)%s*$", "%1")) end
  local _format = type(self._o._treesitter) == "string" and self._o._treesitter or nil
  vim.api.nvim_buf_attach(self.fzf_bufnr, false, {
    on_lines = function(_, bufnr)
      local lines = api.nvim_buf_get_lines(bufnr, 0, -1, false)
      local regions = {}
      local empty_regions = {}
      -- Adjust treesitter region based on the available main window width
      -- otherwise the highlights may interfere with the fzf scrollbar or
      -- the native fzf preview window
      local min_col, max_col, trim_right = (function()
        local min, max, tr = 0, nil, 4
        if not self.preview_hidden
            and (not self.previewer_is_builtin or self.winopts.split)
        then
          local win_width = vim.api.nvim_win_get_width(self.fzf_winid)
          local layout = self:fzf_preview_layout_str()
          local percent = layout:match("(%d+)%%") or 50
          local prev_width = math.floor(win_width * percent / 100)
          if layout:match("left") then
            min = prev_width
          elseif layout:match("right") then
            max = win_width - prev_width
          end
        end
        return min, max, tr
      end)()
      for i, line in ipairs(lines) do
        (function()
          -- Lines with code can be of the following formats:
          -- file:line:col:text   (grep_xxx)
          -- file:line:text       (grep_project or missing "--column" flag)
          -- line:col:text        (grep_curbuf)
          -- line<U+00A0>text     (lines|blines)
          local filepath, _lnum, text = line:sub(min_col):match(_format or "(.-):?(%d+)[: ](.+)$")
          if not text or text == 0 then return end

          text = text:gsub("^%d+:", "") -- remove col nr if exists
          filepath = trim(filepath)     -- trim spaces

          local ft_bufnr = (function()
            -- blines|lines: U+00A0 (decimal: 160) follows the lnum
            -- grep_curbuf: formats as line:col:text` thus `#filepath == 0`
            if #filepath == 0 or string.byte(text, 1) == 160 then
              if string.byte(text, 1) == 160 then text = text:sub(2) end -- remove A0+SPACE
              if string.byte(text, 1) == 32 then text = text:sub(2) end  -- remove leading SPACE
              local b = filepath:match("^%d+") or utils.CTX().bufnr
              return vim.api.nvim_buf_is_valid(tonumber(b)) and b or nil
            end
          end)()

          local ft = ft_bufnr and vim.bo[tonumber(ft_bufnr)].ft
              or vim.filetype.match({ filename = path.tail(filepath) })
          if not ft then return end

          local lang = vim.treesitter.language.get_lang(ft)
          local loaded = lang and utils.has_ts_parser(lang)
          if not loaded then return end

          -- NOTE: if the line contains unicode characters `#line > win_width`
          -- as both `#str` and `string.len` count bytes and not characters
          -- hence we trim 4 bytes from the right (for the scrollbar) except
          -- when using native fzf previewer / split with left preview where
          -- we use `max_col` instead (assuming our code isn't unicode)
          local line_idx = i - 1
          local line_len = #line
          local start_col = math.max(min_col, line_len - #text)
          local end_col = max_col and math.min(max_col, line_len) or (line_len - trim_right)
          regions[lang] = regions[lang] or {}
          empty_regions[lang] = empty_regions[lang] or {}
          table.insert(regions[lang], { { line_idx, start_col, line_idx, end_col } })
          -- print(lang, string.format("%d:%d  [%d] %d:%s",
          --   start_col, end_col, line_idx, _lnum, line:sub(start_col + 1, end_col)))
        end)()
      end
      TSInjector.attach(bufnr, empty_regions)
      TSInjector.attach(bufnr, regions)
    end
  })
end

function FzfWin:set_tmp_buffer(no_wipe)
  if not self:validate() then return end
  -- Store the [would be] detached buffer number
  local detached = self.fzf_bufnr
  -- replace the attached buffer with a new temp buffer, setting `self.fzf_bufnr`
  -- makes sure the call to `fzf_win:close` (which is triggered by the buf del)
  -- won't trigger a close due to mismatched buffers condition on `self:close`
  self.fzf_bufnr = api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(self.fzf_winid, self.fzf_bufnr)
  -- close the previous fzf term buffer without triggering autocmds
  -- this also kills the previous fzf process if its still running
  if not no_wipe then
    utils.nvim_buf_delete(detached, { force = true })
    TSInjector.clear_cache(detached)
  end
  -- in case buffer exists prematurely
  self:set_winleave_autocmd()
  -- automatically resize fzf window
  self:set_redraw_autocmd()
  -- Use treesitter to highlight results on the main fzf window
  self:treesitter_attach()
  -- since we have the cursorline workaround from
  -- issue #254, resume shows an ugly cursorline.
  -- remove it, nvim_win API is better than vim.wo?
  -- vim.wo[self.fzf_winid].cursorline = false
  vim.wo[self.fzf_winid].cursorline = false
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
    else
      self:treesitter_detach(self.fzf_bufnr)
    end
    -- also recall the user's 'on_create' (#394)
    if self.winopts.on_create and
        type(self.winopts.on_create) == "function" then
      self.winopts.on_create({ winid = self.fzf_winid, bufnr = self.fzf_bufnr })
    end
    -- not sure why but when using a split and reusing the window,
    -- fzf will not use all the available width until 'redraw' is
    -- called resulting in misaligned native and builtin previews
    vim.cmd("redraw")
    return self.fzf_bufnr
  end

  -- Set backdrop
  self:set_backdrop()

  if not self.winopts.split and self.previewer_is_builtin then
    self.layout = self:generate_layout(self.winopts)
  end
  -- save sending bufnr/winid
  self.src_bufnr = vim.api.nvim_get_current_buf()
  self.src_winid = vim.api.nvim_get_current_win()
  -- save current window layout cmd
  self.winrestcmd = vim.fn.winrestcmd()
  self.cmdheight = vim.o.cmdheight

  if self.winopts.split then
    vim.cmd(self.winopts.split)
    local split_bufnr = vim.api.nvim_get_current_buf()
    self.fzf_winid = vim.api.nvim_get_current_win()
    if tonumber(self.fzf_bufnr) and vim.api.nvim_buf_is_valid(self.fzf_bufnr) then
      -- Set to fzf bufnr set by `:unhide()`, wipe the new split buf
      utils.win_set_buf_noautocmd(self.fzf_winid, self.fzf_bufnr)
      utils.nvim_buf_delete(split_bufnr, { force = true })
    else
      self.fzf_bufnr = split_bufnr
    end
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
  -- Use treesitter to highlight results on the main fzf window
  self:treesitter_attach()

  self:reset_win_highlights(self.fzf_winid)

  -- potential workarond for `<C-c>` freezing neovim (#1091)
  -- https://github.com/neovim/neovim/issues/20726
  vim.wo[self.fzf_winid].foldmethod = "manual"

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
  if self._previewer and self._previewer.close then
    self._previewer:close(do_not_clear_cache)
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

function FzfWin:close(fzf_bufnr)
  -- When a window is reused, (e.g. open any fzf-lua interface, press <C-\-n> and run
  -- ":FzfLua") `FzfWin:set_tmp_buffer()` will call `nvim_buf_delete` on the original
  -- fzf terminal buffer which will terminate the fzf process and trigger the call to
  -- `fzf_win:close()` within `core.fzf()`. We need to avoid the close in this case.
  if fzf_bufnr and fzf_bufnr ~= self.fzf_bufnr then
    return
  end
  --
  -- prevents race condition with 'win_leave'
  self.closing = true
  self.close_help()
  self:close_backdrop()
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
  -- Clear treesitter buffer cache and deregister decoration callbacks
  self:treesitter_detach(self.fzf_bufnr, self._hidden_fzf_bufnr)
  -- when using `split = "belowright new"` closing the fzf
  -- window may not always return to the correct source win
  -- depending on the user's split configuration (#397)
  if self.winopts and self.winopts.split
      and self.src_winid and self.src_winid > 0
      and self.src_winid ~= vim.api.nvim_get_current_win()
      and vim.api.nvim_win_is_valid(self.src_winid) then
    vim.api.nvim_set_current_win(self.src_winid)
  end
  if self.winopts.split then
    -- remove all windows from the restore cmd that have been closed in the meantime
    -- if we're not doing this the result might be all over the place
    local winnrs = vim.tbl_map(function(win)
      return vim.api.nvim_win_get_number(win) .. ""
    end, vim.api.nvim_tabpage_list_wins(0))

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
  if self.winopts and type(self.winopts.on_close) == "function" then
    self.winopts.on_close()
  end
  self.closing = nil
  self._reuse = nil
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
  self:close()
end

function FzfWin:detach_fzf_buf()
  self._hidden_fzf_bufnr = self.fzf_bufnr
  vim.bo[self._hidden_fzf_bufnr].bufhidden = ""
  self:set_tmp_buffer(true)
end

function FzfWin.hide()
  local self = _self
  -- Note: we should never get here with a tmux profile as neovim binds (default: <A-Esc>)
  -- do not apply to tmux, validate anyways in case called directly using the API
  if not self or self._o._is_fzf_tmux then return end
  if self:validate_preview() and not self.preview_hidden then
    self:close_preview()
    self._hidden_had_preview = true
  end
  self:detach_fzf_buf()
  self:close()
  -- Save self as `:close()` nullifies it
  _self = self
end

function FzfWin:hidden()
  return tonumber(self._hidden_fzf_bufnr)
      and tonumber(self._hidden_fzf_bufnr) > 0
      and vim.api.nvim_buf_is_valid(self._hidden_fzf_bufnr)
end

-- True after a `:new()` call for a different picker, used in `core.fzf`
-- to avoid post processing an fzf process that was discarded
function FzfWin:was_hidden()
  return tonumber(self._hidden_fzf_bufnr)
      and tonumber(self._hidden_fzf_bufnr) > 0
      and not vim.api.nvim_buf_is_valid(self._hidden_fzf_bufnr)
end

function FzfWin.unhide()
  local self = _self
  if not self or not self:hidden() then return end
  vim.bo[self._hidden_fzf_bufnr].bufhidden = "wipe"
  self.fzf_bufnr = self._hidden_fzf_bufnr
  self._hidden_fzf_bufnr = nil
  self:create()
  if self._hidden_had_preview then
    self._hidden_had_preview = nil
    self:redraw_preview()
  end
  vim.cmd("startinsert")
  return true
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

function FzfWin:update_scrollbar(hide)
  if not self.winopts.preview.scrollbar
      or self.winopts.preview.scrollbar == "none"
      or not self:validate_preview() then
    return
  end

  if hide then
    self:hide_scrollbar()
    return
  end

  local buf = api.nvim_win_get_buf(self.preview_winid)

  local o = {}
  o.wininfo = utils.getwininfo(self.preview_winid)
  o.line_count = api.nvim_buf_line_count(buf)

  local topline, height = o.wininfo.topline, o.wininfo.height
  o.bar_height = math.min(height, math.ceil(height * height / o.line_count))
  o.bar_offset = math.min(height - o.bar_height, math.floor(height * topline / o.line_count))

  -- do not display on files that are fully contained
  if o.bar_height >= o.line_count then
    self:hide_scrollbar()
    return
  end

  local offset = self.prev_single_win and 1 or 0
  local info = o.wininfo
  local style1 = {}
  style1.relative = "editor"
  style1.style = "minimal"
  style1.width = 1
  style1.height = info.height
  style1.row = info.winrow - 1 + offset
  style1.col = info.wincol + info.width + offset +
      (tonumber(self.winopts.preview.scrolloff) or -2)
  style1.zindex = self.winopts.zindex + 1
  -- We hide the "empty" win in `scrollbar="botder"` back compat
  if not self.winopts.preview._scroll_hide_empty then
    if self._swin1 and vim.api.nvim_win_is_valid(self._swin1) then
      vim.api.nvim_win_set_config(self._swin1, style1)
    else
      style1.noautocmd = true
      self._sbuf1 = ensure_tmp_buf(self._sbuf1)
      self._swin1 = vim.api.nvim_open_win(self._sbuf1, false, style1)
      local hl = self.hls.scrollfloat_e or "PmenuSbar"
      vim.wo[self._swin1].winhighlight =
          ("Normal:%s,NormalNC:%s,NormalFloat:%s,EndOfBuffer:%s"):format(hl, hl, hl, hl)
    end
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
    local hl = self.hls.scrollfloat_f or "PmenuThumb"
    vim.wo[self._swin2].winhighlight =
        ("Normal:%s,NormalNC:%s,NormalFloat:%s,EndOfBuffer:%s"):format(hl, hl, hl, hl)
  end
end

function FzfWin:update_title(title)
  if self.prev_single_win then
    -- we are using a single window, the border window is hidden
    -- under the preview window and thus meaningless to update
    -- if neovim >= 0.9 we can use the builtin title params instead
    if utils.__HAS_NVIM_09 then
      -- since `nvim_win_set_config` removes all styling, save backup
      -- of the current options and restore after the call (#813)
      local style = self:get_winopts(self.preview_winid, self._previewer:gen_winopts())
      -- `nvim_win_set_config`: Invalid key: 'noautocmd'
      self.prev_winopts.noautocmd = nil
      api.nvim_win_set_config(self.preview_winid, vim.tbl_extend("keep", {
          title = type(self.hls.preview_title) == "string"
              and { { title, self.hls.preview_title } }
              or title,
          title_pos = self.winopts.preview.title_pos,
        },
        self.prev_winopts))
      self:set_winopts(self.preview_winid, style)
    end
    return
  end
  local right_pad = 7
  local border_buf = api.nvim_win_get_buf(self.border_winid)
  local top = api.nvim_buf_get_lines(border_buf, 0, 1, false)[1]
  local width = fn.strwidth(top)
  if #title > width - right_pad then
    title = title:sub(1, width - right_pad) .. " "
  end
  local width_title = fn.strwidth(title)
  local prefix = fn.strcharpart(top, 0, 3)
  if self.winopts.preview.title_pos == "center" then
    prefix = fn.strcharpart(top, 0, utils.round((width - width_title) / 2))
  elseif self.winopts.preview.title_pos == "right" then
    prefix = fn.strcharpart(top, 0, width - (width_title + 3))
  end

  local suffix = fn.strcharpart(top, width_title + fn.strwidth(prefix), width)
  local line = ("%s%s%s"):format(prefix, title, suffix)
  pcall(api.nvim_buf_set_lines, border_buf, 0, 1, true, { line })

  if self.hls.preview_title and #title > 0 then
    pcall(vim.api.nvim_win_call, self.border_winid, function()
      fn.matchaddpos(self.hls.preview_title, { { 1, #prefix + 1, #title } }, 11)
    end)
  end
end

-- keybind methods below
function FzfWin.toggle_fullscreen()
  if not _self or _self.winopts.split then return end
  local self = _self
  self.fullscreen = not self.fullscreen
  self:redraw()
end

function FzfWin.toggle_preview()
  if not _self then return end
  local self = _self
  self.preview_hidden = not self.preview_hidden
  if self._fzf_toggle_prev_bind then
    -- Toggle the empty preview window (under the neovim preview buffer)
    utils.feed_keys_termcodes(self._fzf_toggle_prev_bind)
    -- This is just a proxy to toggle the native fzf preview when treesitter
    -- is enabled, no need to redraw, stop here
    if not self.previewer_is_builtin then
      return
    end
  end
  if self.preview_hidden and self:validate_preview() then
    self:close_preview(true)
    self:redraw_main()
  elseif not self.preview_hidden then
    self:redraw_main()
    self:redraw_preview()
  end
  -- close_preview() calls FzfWin:close()
  -- which will clear out our singleton so
  -- we must save it again to call redraw
  _self = self
end

function FzfWin.toggle_preview_wrap()
  if not _self or not _self:validate_preview() then return end
  local self = _self
  self.preview_wrap = not vim.wo[self.preview_winid].wrap
  if self and self:validate_preview() then
    vim.wo[self.preview_winid].wrap = self.preview_wrap
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
    if pos[i] == self._preview_pos then
      idx = i
      break
    end
  end
  if not idx then return end
  local newidx = direction > 0 and idx + 1 or idx - 1
  if newidx < 1 then newidx = #pos end
  if newidx > #pos then newidx = 1 end
  self._preview_pos_force = pos[newidx]
  self:redraw()
end

function FzfWin.toggle_preview_ts_ctx()
  if not _self then return end
  local self = _self
  if self:validate_preview()
      and self._previewer
      and self._previewer.ts_ctx_toggle then
    self._previewer:ts_ctx_toggle()
  end
end

function FzfWin.preview_ts_ctx_inc_dec(num)
  if not _self then return end
  local self = _self
  if self:validate_preview()
      and self._previewer
      and self._previewer.ts_ctx_inc_dec_maxlines then
    self._previewer:ts_ctx_inc_dec_maxlines(num)
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
  opts.normal_hl = opts.normal_hl or self.hls.help_normal
  opts.border_hl = opts.border_hl or self.hls.help_border
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

  -- ignore fzf event bind as they aren't valid keymaps
  local keymap_ignore = { ["load"] = true, ["zero"] = true }

  -- fzf and neovim (builtin) keymaps
  for _, m in ipairs({ "builtin", "fzf" }) do
    for k, v in pairs(self.keymap[m]) do
      if not keymap_ignore[k] then
        -- value can be defined as a table with addl properties (help string)
        if type(v) == "table" then
          v = v.desc or v[1]
        end
        -- only add preview keybinds respective of
        -- the current preview mode
        if v and (not _preview_keymaps[v] or m == preview_mode) then
          if m == "builtin" then
            k = utils.neovim_bind_to_fzf(k)
          end
          table.insert(keymaps,
            format_bind(m, k, v, opts.mode_width, opts.keybind_width, opts.name_width))
        end
      end
    end
  end

  -- action keymaps
  if self.actions then
    for k, v in pairs(self.actions) do
      if k == "default" then k = "enter" end
      if type(v) == "table" then
        v = v.desc or config.get_action_helpstr(v[1]) or config.get_action_helpstr(v.fn) or v
      elseif v then
        v = config.get_action_helpstr(v) or v
      end
      if v then
        -- skips 'v == false'
        table.insert(keymaps,
          format_bind("action", k,
            ("%s"):format(tostring(v)):gsub(" ", ""),
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
    -- topmost popup (+2 for float border empty/full)
    zindex = self.winopts.zindex + 2,
  }

  -- "border chars mustbe one cell" (#874)
  if vim.o.ambiwidth == "double" then
    -- "single" looks better
    -- winopts.border[2] = "-"
    winopts.border = "single"
  end

  self.km_bufnr = vim.api.nvim_create_buf(false, true)
  vim.bo[self.km_bufnr].bufhidden = "wipe"
  self.km_winid = vim.api.nvim_open_win(self.km_bufnr, false, winopts)
  vim.api.nvim_buf_set_name(self.km_bufnr, "_FzfLuaHelp")
  vim.wo[self.km_winid].winhl =
      string.format("Normal:%s,FloatBorder:%s", opts.normal_hl, opts.border_hl)
  vim.wo[self.km_winid].winblend = opts.winblend
  vim.wo[self.km_winid].foldenable = false
  vim.wo[self.km_winid].wrap = false
  vim.wo[self.km_winid].spell = false
  vim.bo[self.km_bufnr].filetype = "help"

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
