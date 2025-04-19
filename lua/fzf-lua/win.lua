local path = require "fzf-lua.path"
local utils = require "fzf-lua.utils"
local libuv = require "fzf-lua.libuv"
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

function TSInjector.clear_cache(buf)
  -- If called from fzf-tmux buf will be `nil` (#1556)
  if not buf then return end
  TSInjector.cache[buf] = nil
  -- If called from `FzfWin.hide` cache will not be empty
  assert(utils.tbl_isempty(TSInjector.cache))
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
      vim.keymap.set("t", key, funcref_str(keymap), { nowait = true, buffer = self.fzf_bufnr })
    end
  end

  -- If the user did not override the Esc action ensure it's
  -- not bound to anything else such as `<C-\><C-n>` (#663)
  if self.actions["esc"] == actions.dummy_abort and not self.keymap.builtin["<esc>"] then
    vim.keymap.set("t", "<Esc>", "<Esc>", { buffer = self.fzf_bufnr, nowait = true })
  end
end

function FzfWin:generate_layout(winopts)
  winopts = winopts or self.winopts
  -- If previewer is hidden we use full fzf layout, when previewer toggle behavior
  -- is "extend" we still reduce fzf main layout as if the previewer is displayed
  if not self.previewer_is_builtin
      or (self.preview_hidden
        and (self._previewer.toggle_behavior ~= "extend" or self.fullscreen))
  then
    self.layout = {
      fzf = self:normalize_border({
        row = self.winopts.row,
        col = self.winopts.col,
        width = self.winopts.width,
        height = self.winopts.height,
        border = self._o.winopts.border,
        style = "minimal",
        relative = self.winopts.relative or "editor",
        zindex = self.winopts.zindex,
        hide = self.winopts.hide,
      }, { type = "nvim", name = "fzf", nwin = 1 })
    }
    return
  end

  if self.previewer_is_builtin and self.winopts.split then
    local wininfo = utils.getwininfo(self.fzf_winid)
    -- unlike floating win popups, split windows inherit the global
    -- 'signcolumn' setting which affects the available width for fzf
    -- 'generate_layout' will then use the sign column available width
    -- to assure a perfect alignment of the builtin previewer window
    -- and the dummy native fzf previewer window border underneath it
    local signcol_width = vim.wo[self.fzf_winid].signcolumn == "yes" and 1 or 0
    winopts = {
      row = wininfo.winrow,
      col = wininfo.wincol + signcol_width,
      height = wininfo.height,
      width = api.nvim_win_get_width(self.fzf_winid) - signcol_width,
      signcol_width = signcol_width,
      split = self.winopts.split,
      hide = self.winopts.hide,
    }
  end

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
    pwopts = { relative = "win", anchor = "NW", row = 0, col = 0 }
    if preview_pos == "down" or preview_pos == "up" then
      pwopts.width = width - 2
      pwopts.height = utils.round((height) * preview_size / 100, math.huge) - 2
      if preview_pos == "down" then
        pwopts.row = height - pwopts.height - 2
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
      pwopts.col = col
      pwopts.width = width
      pwopts.height = utils.round((height) * preview_size / 100, 0.5)
      height = height - pwopts.height
      if preview_pos == "down" then
        -- next row
        pwopts.row = row + 2 + height
      else -- up
        pwopts.row = row
        row = pwopts.row + 2 + pwopts.height
      end
    else -- left|right
      width = width - 2
      pwopts.row = row
      pwopts.height = height
      pwopts.width = utils.round(width * preview_size / 100, 0.5)
      width = width - pwopts.width
      if preview_pos == "right" then
        -- next col
        pwopts.col = col + 2 + width
      else -- left
        pwopts.col = col
        col = pwopts.col + 2 + pwopts.width
      end
    end
  end
  local nwin = self.preview_hidden and self._previewer.toggle_behavior == "extend" and 1 or 2
  self.layout = {
    fzf = self:normalize_border(
      vim.tbl_extend("force", { row = row, col = col, height = height, width = width }, {
        style = "minimal",
        border = self._o.winopts.border,
        relative = self.winopts.relative or "editor",
        zindex = self.winopts.zindex,
        hide = self.winopts.hide,
      }), { type = "nvim", name = "fzf", nwin = nwin, layout = preview_pos }),
    preview = self:normalize_border(vim.tbl_extend("force", pwopts, {
      style = "minimal",
      zindex = self.winopts.zindex,
      border = self._o.winopts.preview.border,
      focusable = true,
      hide = self.winopts.hide,
    }), { type = "nvim", name = "prev", nwin = nwin, layout = preview_pos })
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
    cols = math.floor(cols * percent / 100)
  end
  return cols
end

function FzfWin:columns(no_fullscreen)
  assert(self.winopts)
  -- When called from `core.preview_window` we need to get the no-fullscreen columns
  -- in order to get an accurate alternate layout trigger that will also be consistent
  -- when starting with `winopts.fullscreen == true`
  local winopts = no_fullscreen and self:normalize_winopts(false) or self.winopts
  return self._o._is_fzf_tmux and self:tmux_columns()
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

--- @param winopts table
--- @return table winopts, number? scrolloff
function FzfWin:normalize_border(winopts, metadata)
  local border = winopts.border
  if type(border) == "function" then
    border = border(winopts, metadata)
  end
  -- Convert boolean types
  if not border then border = "none" end
  if border == true then border = "rounded" end
  -- nvim_open_win valid border
  local valid_borders = {
    none                  = "none",
    single                = "single",
    double                = "double",
    rounded               = "rounded",
    solid                 = "solid",
    empty                 = "solid",
    shadow                = "shadow",
    bold                  = { "┏", "━", "┓", "┃", "┛", "━", "┗", "┃" },
    block                 = { "▛", "▀", "▜", "▐", "▟", "▄", "▙", "▌" },
    solidblock            = { "█", "█", "█", "█", "█", "█", "█", "█" },
    thicc                 = { "┏", "━", "┓", "┃", "┛", "━", "┗", "┃" }, -- bold
    thiccc                = { "▛", "▀", "▜", "▐", "▟", "▄", "▙", "▌" }, -- block
    thicccc               = { "█", "█", "█", "█", "█", "█", "█", "█" }, -- solidblock
    -- empty              = { " ", " ", " ", " ", " ", " ", " ", " " },
    -- fzf preview border styles conversion of  `winopts.preview.border`
    ["border"]            = "rounded",
    ["noborder"]          = "none",
    ["border-none"]       = "none",
    ["border-rounded"]    = "rounded",
    ["border-sharp"]      = "single",
    ["border-bold"]       = { "┏", "━", "┓", "┃", "┛", "━", "┗", "┃" },
    ["border-double"]     = "double",
    ["border-block"]      = { "▛", "▀", "▜", "▐", "▟", "▄", "▙", "▌" },
    ["border-thinblock"]  = { "🭽", "▔", "🭾", "▕", "🭿", "▁", "🭼", "▏" },
    ["border-horizontal"] = { "─", "─", "─", "", "─", "─", "─", "" },
    ["border-top"]        = { "─", "─", "─", "", "", "", "", "" },
    ["border-bottom"]     = { "", "", "", "", "─", "─", "─", "" },
  }
  if type(border) == "string" then
    if not valid_borders[border] then
      if not self._o.silent then
        utils.warn(string.format("Invalid border style '%s', will use 'rounded'.", border))
      end
      border = "rounded"
    else
      border = valid_borders[border]
    end
  elseif type(border) ~= "table" then
    if not self._o.silent then
      utils.warn(string.format("Invalid border type '%s', will use 'rounded'.", type(border)))
    end
    border = "rounded"
  end
  if vim.o.ambiwidth == "double" and type(border) ~= "string" then
    -- when ambiwdith="double" `nvim_open_win` with border chars fails:
    -- with "border chars must be one cell", force string border (#874)
    if not self._o.silent then
      utils.warn(string.format(
        "Invalid border type for 'ambiwidth=double', will use 'rounded'.", border))
    end
    border = "rounded"
  end
  local w, h, scrolloff = 0, 0, nil
  if border == "none" then
    w, h, scrolloff = 2, 2, -1
  elseif type(border) == "table" then
    if not border[2] or #border[2] == 0 then
      h = h + 1
    end
    if not border[4] or #border[4] == 0 then
      w, scrolloff = w + 1, -1
    end
    if not border[6] or #border[6] == 0 then
      h = h + 1
    end
    if not border[8] or #border[8] == 0 then
      w, scrolloff = w + 1, -1
    end
  end
  winopts.border = border
  winopts.width = tonumber(winopts.width) and (winopts.width + w)
  winopts.height = tonumber(winopts.height) and (winopts.height + h)
  return winopts, scrolloff
end

function FzfWin:normalize_winopts(fullscreen)
  -- make a local copy of winopts so we don't pollute the user's options
  local winopts = utils.tbl_deep_clone(self._o.winopts)

  if fullscreen then
    -- NOTE: we set `winopts.relative=editor` so fullscreen
    -- works even when the user set `winopts.relative=cursor`
    winopts.relative = "editor"
    winopts.row = 1
    winopts.col = 1
    winopts.width = 1
    winopts.height = 1
  end

  winopts.__winhls = {
    main = {
      { "Normal",       self.hls.normal },
      { "NormalFloat",  self.hls.normal },
      { "FloatBorder",  self.hls.border },
      { "CursorLine",   self.hls.cursorline },
      { "CursorLineNr", self.hls.cursorlinenr },
    },
    prev = {
      { "Normal",       self.hls.preview_normal },
      { "NormalFloat",  self.hls.preview_normal },
      { "FloatBorder",  self.hls.preview_border },
      { "CursorLine",   self.hls.cursorline },
      { "CursorLineNr", self.hls.cursorlinenr },
    },
  }

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
    -- use the calling window context for correct pos
    local winid = utils.CTX().winid
    local pos = vim.api.nvim_win_get_cursor(winid)
    local screenpos = vim.fn.screenpos(winid, pos[1], pos[2])
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

  return winopts
end

function FzfWin:reset_win_highlights(win)
  -- derive the highlights from the window type
  local key = "main"
  if win == self.preview_winid then
    key = "prev"
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
  self.backdrop_win = utils.nvim_open_win0(self.backdrop_buf, false, {
    relative = "editor",
    width = vim.o.columns,
    height = vim.o.lines,
    row = 0,
    col = 0,
    style = "minimal",
    focusable = false,
    -- -2 as preview border is -1
    zindex = self.winopts.zindex - 2,
    border = "none",
    -- NOTE: backdrop shoulnd't be hidden with winopts.hide
    -- hide = self.winopts.hide,
  })
  vim.wo[self.backdrop_win].winhighlight = "Normal:" .. self.hls.backdrop
  vim.wo[self.backdrop_win].winblend = self.winopts.backdrop
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

---@alias FzfWin table
---@param o table
---@return FzfWin
function FzfWin:new(o)
  if not _self then
  elseif _self:was_hidden() then
    TSInjector.clear_cache(_self._hidden_fzf_bufnr)
    _self = nil
  elseif not _self:hidden() then
    -- utils.warn("Please close fzf-lua before starting a new instance")
    _self._reuse = true
    -- switch to fzf-lua's main window in case the user switched out
    -- NOTE: `self.fzf_winid == nil` when using fzf-tmux
    if _self.fzf_winid and _self.fzf_winid ~= vim.api.nvim_get_current_win() then
      vim.api.nvim_set_current_win(_self.fzf_winid)
    end
    -- Update main win title, required for toggle action flags
    _self:update_main_title(o.winopts.title)
    -- refersh treesitter settings as new picker might have it disabled
    _self._o.winopts.treesitter = o.winopts.treesitter
    return _self
  elseif _self:hidden() then
    -- Clear the hidden buffers
    vim.api.nvim_buf_delete(_self._hidden_fzf_bufnr, { force = true })
    TSInjector.clear_cache(_self._hidden_fzf_bufnr)
    _self = nil
  end
  o = o or {}
  self._o = o
  self = utils.setmetatable__gc({}, {
    __index = self,
    __gc = function(s)
      vim.schedule(function()
        if s._previewer and s._previewer.clear_cached_buffers then
          s._previewer:clear_cached_buffers()
        end
      end)
    end
  })
  self.hls = o.hls
  self.actions = o.actions
  self.fullscreen = o.winopts.fullscreen
  self.winopts = self:normalize_winopts(self.fullscreen)
  self.preview_wrap = not not o.winopts.preview.wrap     -- force boolean
  self.preview_hidden = not not o.winopts.preview.hidden -- force boolean
  self.keymap = o.keymap
  self.previewer = o.previewer
  self:_set_autoclose(o.autoclose)
  -- Backward compat since removal of "border" scrollbar
  if self.winopts.preview.scrollbar == "border" then
    self.hls.scrollfloat_f = false
    -- Reverse "FzfLuaScrollBorderFull" color
    if type(self.hls.scrollborder_f) == "string" then
      local fg = utils.hexcol_from_hl(self.hls.scrollborder_f, "fg")
      local bg = utils.hexcol_from_hl(self.hls.scrollborder_f, "bg")
      if fg and #fg > 0 then
        local hlgroup = "FzfLuaScrollBorderBackCompat"
        self.hls.scrollfloat_f = hlgroup
        vim.api.nvim_set_hl(0, hlgroup,
          vim.o.termguicolors and { default = false, fg = bg, bg = fg }
          or { default = false, ctermfg = tonumber(bg), ctermbg = tonumber(fg) })
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

function FzfWin:set_winopts(win, opts, ignore_events)
  if not win or not api.nvim_win_is_valid(win) then return end
  -- NOTE: Do not trigger "OptionSet" as this will trigger treesitter-context's
  -- `update_single_context` which will in turn close our treesitter-context
  local save_ei
  if ignore_events then
    save_ei = vim.o.eventignore
    vim.o.eventignore = "all"
  end
  for opt, value in pairs(opts) do
    if utils.nvim_has_option(opt) then
      vim.wo[win][opt] = value
    end
  end
  if save_ei then
    vim.o.eventignore = save_ei
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

function FzfWin:validate_preview()
  return not self.closing
      and tonumber(self.preview_winid)
      and self.preview_winid > 0
      and api.nvim_win_is_valid(self.preview_winid)
end

function FzfWin:redraw_preview()
  if not self.previewer_is_builtin or self.preview_hidden then
    return
  end

  -- Close the exisiting scrollbar
  self:close_preview_scrollbar()

  -- Generate the preview layout
  self:generate_layout()
  assert(type(self.layout.preview) == "table")

  if self:validate_preview() then
    -- since `nvim_win_set_config` removes all styling, save backup
    -- of the current options and restore after the call (#813)
    local style = self:get_winopts(self.preview_winid, self._previewer:gen_winopts())
    api.nvim_win_set_config(self.preview_winid, self.layout.preview)
    self:set_winopts(self.preview_winid, style)
  else
    local tmp_buf = self._previewer:get_tmp_buffer()
    -- No autocmds, can only be sent with 'nvim_open_win'
    self.preview_winid = api.nvim_open_win(tmp_buf, false,
      vim.tbl_extend("force", self.layout.preview, { noautocmd = true }))
    -- Add win local var for the preview|border windows
    api.nvim_win_set_var(self.preview_winid, "fzf_lua_preview", true)
  end
  self:reset_win_highlights(self.preview_winid)
  self._previewer:display_last_entry()
end

function FzfWin:validate()
  return self.fzf_winid and self.fzf_winid > 0
      and api.nvim_win_is_valid(self.fzf_winid)
end

function FzfWin:redraw()
  self.winopts = self:normalize_winopts(self.fullscreen)
  self:set_backdrop()
  if self:validate() then
    self:redraw_main()
  end
  if self:validate_preview() then
    self:redraw_preview()
  end
end

function FzfWin:redraw_main()
  if self.winopts.split then return end

  self:generate_layout()

  local winopts = vim.tbl_extend("keep", (function()
    if type(self.winopts.title) ~= "string" and type(self.winopts.title) ~= "table" then
      return {}
    end
    return {
      title = type(self.winopts.title) == "string" and type(self.hls.title) == "string"
          and { { self.winopts.title, self.hls.title } }
          or self.winopts.title,
      title_pos = self.winopts.title_pos,
    }
  end)(), self.layout.fzf)

  if self:validate() then
    if self._previewer
        and self._previewer.clear_on_redraw
        and self._previewer.clear_preview_buf then
      self._previewer:clear_preview_buf(true)
      self._previewer:clear_cached_buffers()
    end
    api.nvim_win_set_config(self.fzf_winid, winopts)
  else
    -- save 'cursorline' setting prior to opening the popup
    local cursorline = vim.o.cursorline
    self.fzf_bufnr = self.fzf_bufnr or vim.api.nvim_create_buf(false, true)
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
    if vim.o.cursorline ~= cursorline then
      vim.o.cursorline = cursorline
    end
  end
end

function FzfWin:_nvim_create_autocmd(e, callback)
  vim.api.nvim_create_autocmd(e, {
    group = vim.api.nvim_create_augroup("FzfLua" .. e, { clear = true }),
    buffer = self.fzf_bufnr,
    callback = callback,
  })
end

function FzfWin:set_redraw_autocmd()
  self:_nvim_create_autocmd("VimResized", function() self:redraw() end)
end

function FzfWin:set_winleave_autocmd()
  self:_nvim_create_autocmd("WinClosed", self.win_leave)
end

function FzfWin:treesitter_detach(buf)
  TSInjector.clear_cache(buf)
  TSInjector.deregister()
end

function FzfWin:treesitter_attach()
  if not self._o.winopts.treesitter then return end
  -- local utf8 = require("fzf-lua.lib.utf8")
  local function trim(s) return (string.gsub(s, "^%s*(.-)%s*$", "%1")) end
  ---@type fun(filepath: string, _lnum: string, text: string)
  local line_parser = vim.is_callable(self._o._treesitter) and self._o._treesitter or function(line)
    return line:match("(.-):?(%d+)[: ](.+)$")
  end
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
            and vim.api.nvim_win_is_valid(self.fzf_winid)
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
          local filepath, _lnum, text = line_parser(line:sub(min_col))
          if not text or text == 0 then return end

          text = text:gsub("^%d+:", "") -- remove col nr if exists
          filepath = trim(filepath)     -- trim spaces

          local ft_bufnr = (function()
            -- blines|lines: U+00A0 (decimal: 160) follows the lnum
            -- grep_curbuf: formats as line:col:text` thus `#filepath == 0`
            if #filepath == 0 or string.byte(text, 1) == 160 then
              if string.byte(text, 1) == 160 then text = text:sub(2) end -- remove A0+SPACE
              if string.byte(text, 1) == 32 then text = text:sub(2) end  -- remove leading SPACE
              -- IMPORTANT: use the `__CTX` version that doesn't trigger a new context
              local b = filepath:match("^%d+") or utils.__CTX().bufnr
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
  -- `hidden` must be set to true or the detached buffer will be deleted (#1850)
  local old_hidden = vim.o.hidden
  vim.o.hidden = true
  utils.win_set_buf_noautocmd(self.fzf_winid, self.fzf_bufnr)
  vim.o.hidden = old_hidden
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

  -- save sending bufnr/winid
  self.src_bufnr = vim.api.nvim_get_current_buf()
  self.src_winid = vim.api.nvim_get_current_win()
  -- save current window layout cmd
  self.winrestcmd = vim.fn.winrestcmd()
  self.cmdheight = vim.o.cmdheight

  if self.winopts.split then
    if type(self.winopts.split) == "function" then
      local curwin = vim.api.nvim_get_current_win()
      self.winopts.split()
      assert(curwin ~= vim.api.nvim_get_current_win(), "split function should return a new win")
    else
      vim.cmd(tostring(self.winopts.split))
    end
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
  -- when running async LSP with 'jump1'
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
  self:close_preview_scrollbar()
  if self._previewer and self._previewer.close then
    self._previewer:close(do_not_clear_cache)
  end
  if self.preview_winid and vim.api.nvim_win_is_valid(self.preview_winid) then
    utils.nvim_win_close(self.preview_winid, true)
  end
  self.preview_winid = nil
end

function FzfWin:close(fzf_bufnr, do_not_clear_cache)
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
  self:close_preview(do_not_clear_cache)
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
  self:treesitter_detach(self._hidden_fzf_bufnr or self.fzf_bufnr)
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
  if not self or self:hidden() then return end
  -- Note: we should never get here with a tmux profile as neovim binds (default: <A-Esc>)
  -- do not apply to tmux, validate anyways in case called directly using the API
  if not self or self._o._is_fzf_tmux then return end
  self:detach_fzf_buf()
  self:close(nil, true)
  -- save the current window size (VimResized won't emit when buffer hidden)
  self._hidden_save_size = { vim.o.lines, vim.o.columns }
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
  self._o.__CTX = utils.CTX({ includeBuflist = true })
  self._o._unhide_called = true
  -- Send SIGWINCH to to trigger resize in the fzf process
  -- We will use the trigger to reload necessary buffer lists
  local pid = fn.jobpid(vim.bo[self._hidden_fzf_bufnr].channel)
  vim.tbl_map(function(_pid) libuv.process_kill(_pid, 28) end, api.nvim_get_proc_children(pid))
  vim.bo[self._hidden_fzf_bufnr].bufhidden = "wipe"
  self.fzf_bufnr = self._hidden_fzf_bufnr
  self._hidden_fzf_bufnr = nil
  self:create()
  if not vim.deep_equal(self._hidden_save_size, { vim.o.lines, vim.o.columns }) then
    self:redraw()
  end
  self._hidden_save_size = nil
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

function FzfWin:close_preview_scrollbar()
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
  self._sbuf1 = nil
  self._sbuf2 = nil
  self._swin1 = nil
  self._swin2 = nil
end

function FzfWin:update_preview_scrollbar()
  if not self.winopts.preview.scrollbar
      or self.winopts.preview.scrollbar == "none"
      or not self:validate_preview() then
    return
  end

  local o = {}
  local buf = api.nvim_win_get_buf(self.preview_winid)
  o.wininfo = utils.getwininfo(self.preview_winid)
  o.line_count = utils.line_count(self.preview_winid, buf)

  local topline, height = o.wininfo.topline, o.wininfo.height
  if api.nvim_win_text_height then
    topline = topline == 1 and topline or
        api.nvim_win_text_height(self.preview_winid, { end_row = topline - 1 }).all + 1
  end
  o.bar_height = math.min(height, math.ceil(height * height / o.line_count))
  o.bar_offset = math.min(height - o.bar_height, math.floor(height * topline / o.line_count))

  -- do not display on files that are fully contained
  if o.bar_height >= o.line_count then
    self:close_preview_scrollbar()
    return
  end

  local scrolloff = self.winopts.preview.scrollbar == "border"
      and self.layout.preview.border ~= "none" and 0
      or tonumber(self.winopts.preview.scrolloff) or -1

  local empty = {
    style = "minimal",
    focusable = false,
    relative = "win",
    anchor = "NW",
    win = self.preview_winid,
    width = 1,
    height = o.wininfo.height,
    zindex = self.winopts.zindex + 1,
    row = 0,
    col = o.wininfo.width + scrolloff,
    border = "none",
    hide = self.winopts.hide,
  }
  local full = vim.tbl_extend("keep", {
    zindex = empty.zindex + 1,
    height = o.bar_height,
    row = empty.row + o.bar_offset,
  }, empty)
  -- We hide the "empty" win in `scrollbar="border"` back compat
  if self.winopts.preview.scrollbar ~= "border" then
    if self._swin1 and vim.api.nvim_win_is_valid(self._swin1) then
      vim.api.nvim_win_set_config(self._swin1, empty)
    else
      empty.noautocmd = true
      self._sbuf1 = ensure_tmp_buf(self._sbuf1)
      self._swin1 = utils.nvim_open_win0(self._sbuf1, false, empty)
      local hl = self.hls.scrollfloat_e or "PmenuSbar"
      vim.wo[self._swin1].winhighlight =
          ("Normal:%s,NormalNC:%s,NormalFloat:%s,EndOfBuffer:%s"):format(hl, hl, hl, hl)
    end
  end
  if self._swin2 and vim.api.nvim_win_is_valid(self._swin2) then
    vim.api.nvim_win_set_config(self._swin2, full)
  else
    full.noautocmd = true
    self._sbuf2 = ensure_tmp_buf(self._sbuf2)
    self._swin2 = utils.nvim_open_win0(self._sbuf2, false, full)
    local hl = self.hls.scrollfloat_f or "PmenuThumb"
    vim.wo[self._swin2].winhighlight =
        ("Normal:%s,NormalNC:%s,NormalFloat:%s,EndOfBuffer:%s"):format(hl, hl, hl, hl)
  end
end

function FzfWin.update_win_title(winid, winopts, o)
  if type(o.title) ~= "string" and type(o.title) ~= "table" then
    return
  end
  vim.api.nvim_win_set_config(winid,
    -- NOTE: although we can set the title without winopts we add these
    -- so we don't fail with "title requires border to be set" on wins
    -- without top border
    vim.tbl_extend("force", winopts, {
      title = type(o.hl) == "string" and type(o.title) == "string"
          and { { o.title, o.hl } } or o.title,
      title_pos = o.title_pos,
    }))
end

function FzfWin:update_main_title(title)
  -- Can be called from fzf-tmux on ctrl-g
  if not self.layout or self.winopts.split then return end
  self.winopts.title = title
  self._o.winopts.title = title
  self.update_win_title(self.fzf_winid, self.layout.fzf, {
    title = title,
    title_pos = self.winopts.title_pos,
    hl = self.hls.title,
  })
end

function FzfWin:update_preview_title(title)
  if type(title) ~= "string" and type(title) ~= "table" then
    return
  end
  -- since `nvim_win_set_config` removes all styling, save backup
  -- of the current options and restore after the call (#813)
  local style = self:get_winopts(self.preview_winid, self._previewer:gen_winopts())
  self.update_win_title(self.preview_winid, self.layout.preview, {
    title = title,
    title_pos = self.winopts.preview.title_pos,
    hl = self.hls.preview_title,
  })
  -- NOTE: `true` to ignore events for TSContext.update after selection change
  self:set_winopts(self.preview_winid, style, true)
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
    -- Do not trigger "ModeChanged"
    local save_ei = vim.o.eventignore
    vim.o.eventignore = "all"
    self._previewer:scroll(direction)
    vim.o.eventignore = save_ei
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

  local nvim_open_win = type(self._o.help_open_win) == "function"
      and self._o.help_open_win or vim.api.nvim_open_win

  self.km_bufnr = vim.api.nvim_create_buf(false, true)
  vim.bo[self.km_bufnr].modifiable = true
  vim.bo[self.km_bufnr].bufhidden = "wipe"
  self.km_winid = nvim_open_win(self.km_bufnr, false, winopts)
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
