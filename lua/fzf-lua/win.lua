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
  TSInjector._has_on_range = TSInjector._has_on_range == nil
      and pcall(vim.api.nvim_set_decoration_provider, TSInjector._ns, { on_range = function() end })
      or TSInjector._has_on_range

  local function wrap_ts_hl_callback(name)
    return function(_, win, buf, ...)
      -- print(name, buf, win, TSInjector.cache[buf])
      if not TSInjector.cache[buf] then
        return false
      end
      for _, hl in pairs(TSInjector.cache[buf] or {}) do
        if hl.enabled then
          vim.treesitter.highlighter.active[buf] = hl.highlighter
          if vim.treesitter.highlighter[name] then
            vim.treesitter.highlighter[name](_, win, buf, ...)
          end
        end
      end
      vim.treesitter.highlighter.active[buf] = nil
    end
  end

  vim.api.nvim_set_decoration_provider(TSInjector._ns, {
    on_win = wrap_ts_hl_callback("_on_win"),
    on_line = wrap_ts_hl_callback("_on_line"),
    on_range = TSInjector._has_on_range and wrap_ts_hl_callback("_on_range") or nil,
  })

  return true
end

function TSInjector.deregister()
  if not TSInjector._ns then return end
  vim.api.nvim_set_decoration_provider(TSInjector._ns,
    { on_win = nil, on_line = nil, on_range = nil })
  TSInjector._setup = nil
end

function TSInjector.clear_cache(buf)
  -- If called from fzf-tmux buf will be `nil` (#1556)
  if not buf then return end
  TSInjector.cache[buf] = nil
  -- If called from `FzfWin.hide` cache will not be empty
  assert(utils.tbl_isempty(TSInjector.cache))
end

---@alias TSRegion (Range4|Range6|TSNode)[][]

---@param buf integer
---@param regions table<string, TSRegion>
function TSInjector.attach(buf, regions)
  if not TSInjector.setup() then return end

  TSInjector.cache[buf] = TSInjector.cache[buf] or {}
  for lang, _ in pairs(TSInjector.cache[buf]) do
    TSInjector.cache[buf][lang].enabled = regions[lang] ~= nil
  end

  for lang, region in pairs(regions) do
    TSInjector._attach_lang(buf, lang, region)
  end
end

---@param buf integer
---@param lang? string
---@param regions table<string, TSRegion>
function TSInjector._attach_lang(buf, lang, regions)
  if not lang then return end
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
  ---@diagnostic disable-next-line: invisible
  parser:set_included_regions(regions)
end

---@alias fzf-lua.win.previewPos "up"|"down"|"left"|"right"
---@alias fzf-lua.win.previewLayout { pos: fzf-lua.win.previewPos, size: number, str: string }

---@class fzf-lua.Win
---@field winopts fzf-lua.config.Winopts|{}
---@field km_winid integer?
---@field km_bufnr integer?
---@field _previewer fzf-lua.previewer.Builtin|fzf-lua.previewer.Fzf?
---@field _preview_pos_force fzf-lua.win.previewPos
---@field _last_view [integer, integer, integer]?
local FzfWin = {}

-- singleton instance used in win_leave
---@type fzf-lua.Win?
local _self = nil

function FzfWin.__SELF()
  return _self
end

local _preview_keymaps = {
  ["toggle-preview-wrap"]    = { module = "win", fnc = "toggle_preview_wrap()" },
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
  ["focus-preview"]          = { module = "win", fnc = "focus_preview()" },
}

function FzfWin:setup_keybinds()
  if not self:validate() then return end
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
  self._fzf_toggle_prev_bind = nil
  -- find the toggle_preview keybind, to be sent when using a split for the native
  -- pseudo fzf preview window or when using native and treesitter is enabled
  if self.winopts.split or not self.previewer_is_builtin then
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
    preview_str = (self._preview_pos_force == "up" or self._preview_pos_force == "down")
        and self.winopts.preview.vertical or self.winopts.preview.horizontal
    assert(preview_str)
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

function FzfWin:generate_layout()
  self:normalize_winopts()
  local winopts = self.winopts

  local nwin, preview = self:normalize_layout()
  local layout = self:normalize_preview_layout()
  local border, h, w = self:normalize_border(self._o.winopts.border,
    { type = "nvim", name = "fzf", layout = preview and layout.pos, nwin = nwin, opts = self._o })
  if not preview then
    self.layout = {
      fzf = {
        row = self.winopts.row,
        col = self.winopts.col,
        width = self.winopts.width,
        height = self.winopts.height,
        border = border,
        style = "minimal",
        relative = self.winopts.relative or "editor",
        zindex = self.winopts.zindex,
        hide = self.winopts.hide,
      }
    }
    return
  end

  if self.previewer_is_builtin and self.winopts.split then
    local wininfo = utils.getwininfo(self.fzf_winid)
    -- no signcolumn/number/relativenumber (in set_style_minimal)
    winopts = {
      height = wininfo.height,
      width = wininfo.width,
      split = self.winopts.split,
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
      relative = self.winopts.relative or "editor",
      zindex = self.winopts.zindex,
      hide = self.winopts.hide,
    }),
    preview = vim.tbl_extend("force", pwopts, {
      style = "minimal",
      zindex = self.winopts.zindex,
      border = pborder,
      focusable = true,
      hide = self.winopts.hide,
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
    cols = math.floor(cols * percent / 100)
  end
  return cols
end

function FzfWin:columns(no_fullscreen)
  assert(self.winopts)
  -- When called from `core.preview_window` we need to get the no-fullscreen columns
  -- in order to get an accurate alternate layout trigger that will also be consistent
  -- when starting with `winopts.fullscreen == true`
  local winopts = no_fullscreen and self._o.winopts or self.winopts
  return self._o._is_fzf_tmux and self:tmux_columns()
      or winopts.split and vim.api.nvim_win_get_width(self.fzf_winid or 0)
      or self:normalize_size(winopts.width, vim.o.columns)
end

function FzfWin:fzf_preview_layout_str()
  assert(self.winopts)
  local columns = self:columns()
  local is_hsplit = self.winopts.preview.layout == "horizontal"
      or self.winopts.preview.layout == "flex" and columns > self.winopts.preview.flip_columns
  return is_hsplit and self._o.winopts.preview.horizontal or self._o.winopts.preview.vertical
end

---@alias fzf-lua.win.borderMetadata { type: "nvim"|"fzf", name: "fzf"|"prev", nwin: integer, layout: fzf-lua.win.previewPos }
---@param border any
---@param metadata fzf-lua.win.borderMetadata
---@return string|table, integer, integer
function FzfWin:normalize_border(border, metadata)
  if type(border) == "function" then
    border = border(self, metadata)
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
        utils.warn("Invalid border style '%s', will use 'rounded'.", border)
      end
      border = "rounded"
    else
      border = valid_borders[border]
    end
  elseif type(border) ~= "table" then
    if not self._o.silent then
      utils.warn("Invalid border type '%s', will use 'rounded'.", type(border))
    end
    border = "rounded"
  end
  if vim.o.ambiwidth == "double" and type(border) ~= "string" then
    -- when ambiwdith="double" `nvim_open_win` with border chars fails:
    -- with "border chars must be one cell", force string border (#874)
    if not self._o.silent then
      utils.warn("Invalid border type for 'ambiwidth=double', will use 'rounded'.", border)
    end
    border = "rounded"
  end
  local up, down, left, right ---@type integer, integer, integer, integer
  if border == "none" then
    up, down, left, right = 0, 0, 0, 0
  elseif type(border) == "table" then
    up = (not border[2] or #border[2] == 0) and 0 or 1
    right = (not border[4] or #border[4] == 0) and 0 or 1
    down = (not border[6] or #border[6] == 0) and 0 or 1
    left = (not border[8] or #border[8] == 0) and 0 or 1
  else
    up, down, left, right = 1, 1, 1, 1
  end
  return border, up + down, left + right
end

---@param size number
---@param max integer
---@return integer
function FzfWin:normalize_size(size, max)
  return size <= 1 and math.floor(max * size) or math.min(size, max)
end

---@return fzf-lua.config.Winopts|{}
function FzfWin:normalize_winopts()
  -- make a local copy of winopts so we don't pollute the user's options
  local winopts = utils.tbl_deep_clone(self._o.winopts) or {}
  self.winopts = winopts

  if self.fullscreen then
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
  winopts.width = self:normalize_size(tonumber(winopts.width), max_width)
  winopts.height = self:normalize_size(tonumber(winopts.height), max_height)
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
    -- make row close to the center of screen (include cmdheight)
    -- avoid breaking existing test
    winopts.row = self:normalize_size(tonumber(winopts.row), vim.o.lines - winopts.height)
    winopts.col = self:normalize_size(tonumber(winopts.col), max_width - winopts.width)
    winopts.row = math.min(winopts.row, max_height - winopts.height)
  end
  -- width/height can be used for text area
  winopts.width = math.max(1, winopts.width - w)
  winopts.height = math.max(1, winopts.height - h)
  return winopts
end

---@param win integer
function FzfWin:reset_win_highlights(win)
  -- derive the highlights from the window type
  local key = "main"
  local hl
  if win == self.preview_winid then
    key = "prev"
    hl = self._previewer:gen_winopts().winhl
  end
  if not hl then
    for _, h in ipairs(self.winopts.__winhls[key]) do
      if h[2] then
        hl = string.format("%s%s:%s", hl and hl .. "," or "", h[1], h[2])
      end
    end
  end
  utils.wo[win].winhl = hl
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
  utils.wo[self.backdrop_win].winhl = "Normal:" .. self.hls.backdrop
  utils.wo[self.backdrop_win].winblend = self.winopts.backdrop
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

---@param o fzf-lua.Config
---@return fzf-lua.Win
function FzfWin:new(o)
  if not _self then
  elseif _self:was_hidden() or _self:hidden() then
    _self:close(nil, nil, true) -- do not clear info
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
    -- detach previewer and refresh signal handler
    -- e.g. when switch from fzf previewer to builtin previewer
    _self._o = o
    o.winopts.preview.hidden = _self.preview_hidden
    _self:attach_previewer(nil)
    return _self
  end
  o = o or {}
  self._o = o
  -- gc is unused now, only used to test _self is nullrified
  self = utils.setmetatable({},
    { __index = self, __gc = function() _G._fzf_lua_gc_called = true end })
  self.hls = o.hls
  self.actions = o.actions
  self.fullscreen = o.winopts.fullscreen
  self.toggle_behavior = o.winopts.toggle_behavior
  self.preview_wrap = not not o.winopts.preview.wrap     -- force boolean
  self.preview_hidden = not not o.winopts.preview.hidden -- force boolean
  self.keymap = o.keymap
  self.previewer = o.previewer
  self:_set_autoclose(o.autoclose)
  self:normalize_winopts()
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

---@param win integer
---@param opts vim.wo|{}
---@return vim.wo|{}
function FzfWin:get_winopts(win, opts)
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
function FzfWin:set_winopts(win, opts, ignore_events)
  if not win or not api.nvim_win_is_valid(win) then return end
  -- NOTE: Do not trigger "OptionSet" as this will trigger treesitter-context's
  -- `update_single_context` which will in turn close our treesitter-context
  local ei = ignore_events and "all" or vim.o.eventignore
  utils.eventignore(function()
    for opt, value in pairs(opts) do
      utils.wo[win][opt] = value
    end
  end, ei)
end

---@param previewer fzf-lua.previewer.Builtin? nil to "detach" previewer
function FzfWin:attach_previewer(previewer)
  if previewer then
    previewer.win = self
    previewer.delay = self.winopts.preview.delay or 100
    previewer.title = self.winopts.preview.title
    previewer.title_pos = self.winopts.preview.title_pos
    previewer.winopts = self.winopts.preview.winopts
    previewer.winblend = previewer.winblend or previewer.winopts.winblend or vim.o.winblend
  end
  -- clear the previous previewer if existed
  if self._previewer and self._previewer.close then
    -- if we press ctrl-g too quickly 'previewer.preview_bufnr' will be nil
    -- and even though the temp buffer is set to 'bufhidden:wipe' the buffer
    -- won't be closed properly and remain lingering (visible in `:ls!`)
    -- make sure the previewer is aware of this buffer
    if not self._previewer.preview_bufnr and self:validate_preview() then
      self._previewer.preview_bufnr = vim.api.nvim_win_get_buf(self.preview_winid)
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
  self._previewer:update_ts_context()
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
    vim.o.cursorline = cursorline
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
  TSInjector.deregister()
  TSInjector.clear_cache(buf)
end

function FzfWin:treesitter_attach()
  if not self._o.winopts.treesitter then return end
  -- local utf8 = require("fzf-lua.lib.utf8")
  local function trim(s) return (string.gsub(s, "^%s*(.-)%s*$", "%1")) end
  ---@type fun(filepath: string, _lnum: string?, text: string?)
  local line_parser = vim.is_callable(self._o._treesitter) and self._o._treesitter or function(line)
    return line:match("(.-):?(%d+)[: ](.+)$")
  end
  vim.api.nvim_buf_attach(self.fzf_bufnr, false, {
    on_lines = function(_, bufnr)
      -- Called after `:close` triggers an attach after clear_cache (#2322)
      if self.closing then return end
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
          local layout = self:normalize_preview_layout()
          local prev_width = self:normalize_size(layout.size, win_width)
          if layout.pos == "left" then
            min = prev_width
          elseif layout.pos == "right" then
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
          local filepath, _lnum, text, _ft = line_parser(line:sub(min_col))
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
              local __CTX = utils.__CTX()
              local b = tonumber(filepath:match("^%d+") or __CTX and __CTX.bufnr)
              return b and vim.api.nvim_buf_is_valid(b) and b or nil
            end
          end)()

          local ft = _ft or (ft_bufnr and vim.bo[ft_bufnr].ft
            or vim.filetype.match({ filename = path.tail(filepath) }))
          if not ft then return end

          local lang = vim.treesitter.language.get_lang(ft)
          if not lang then return end
          local loaded = lang and utils.has_ts_parser(lang, "highlights")
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

function FzfWin:set_style_minimal(winid)
  if not tonumber(winid) or not api.nvim_win_is_valid(winid) then return end
  utils.wo[winid].number = false
  utils.wo[winid].relativenumber = false
  -- TODO: causes issues with winopts.split=enew
  -- why do we need this in a terminal window?
  -- utils.wo[winid].cursorline = false
  utils.wo[winid].cursorcolumn = false
  utils.wo[winid].spell = false
  utils.wo[winid].list = false
  utils.wo[winid].signcolumn = "no"
  utils.wo[winid].foldcolumn = "0"
  utils.wo[winid].colorcolumn = ""
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
  self.src_bufnr = vim.api.nvim_get_current_buf()
  self.src_winid = vim.api.nvim_get_current_win()
  -- save current window layout cmd
  self.winrestcmd = vim.fn.winrestcmd()
  self.cmdheight = vim.o.cmdheight

  if self.winopts.split then
    -- Store the current window styling options (number, cursor, etc)
    self.src_winid_style = self:save_style_minimal(self.src_winid)
    if type(self.winopts.split) == "function" then
      self.winopts.split()
    else
      vim.cmd(tostring(self.winopts.split))
    end

    local split_bufnr = vim.api.nvim_get_current_buf()
    self.fzf_winid = vim.api.nvim_get_current_win()

    if tonumber(self.fzf_bufnr) and vim.api.nvim_buf_is_valid(self.fzf_bufnr) then
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
  utils.wo[self.fzf_winid].foldmethod = "manual"

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

---@param fzf_bufnr? integer
---@param hide? boolean
---@param hidden? boolean
function FzfWin:close(fzf_bufnr, hide, hidden)
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
  self:close_preview(hide)
  -- Abort hidden fzf job?
  if not hide and self._hidden_fzf_bufnr and self._hidden_fzf_bufnr ~= self.fzf_bufnr then
    pcall(vim.api.nvim_buf_delete, self._hidden_fzf_bufnr, { force = true })
  end
  -- Clear treesitter buffer cache and deregister decoration callbacks
  self:treesitter_detach(self._hidden_fzf_bufnr or self.fzf_bufnr)
  -- If this is a hidden buffer closure nothing else to do
  if hidden then return end
  if self.fzf_winid and vim.api.nvim_win_is_valid(self.fzf_winid) then
    -- run in a pcall due to potential errors while closing the window
    -- Vim(lua):E5108: Error executing lua
    -- experienced while accessing 'vim.b[]' from my statusline code
    if self.src_winid == self.fzf_winid then
      -- "split" reused the current win (e.g. "enew")
      -- restore the original buffer and styling options
      self:set_winopts(self.fzf_winid, self.src_winid_style or {})
      -- buf may be invalid if we switched away from a scratch buffer
      if vim.api.nvim_buf_is_valid(self.src_bufnr) then
        utils.win_set_buf_noautocmd(self.fzf_winid, self.src_bufnr)
      end
      -- also restore the original alternate buffer
      local alt_bname = (function()
        local alt_bufnr = utils.__CTX() and utils.__CTX().alt_bufnr
        if alt_bufnr and vim.api.nvim_buf_is_valid(alt_bufnr) then
          return vim.fn.bufname(alt_bufnr)
        end
      end)()
      if alt_bname and #alt_bname > 0 then
        vim.cmd("balt " .. vim.fn.bufname(alt_bname))
      end
    else
      pcall(vim.api.nvim_win_close, self.fzf_winid, true)
    end
  end
  if self.fzf_bufnr then
    pcall(vim.api.nvim_buf_delete, self.fzf_bufnr, { force = true })
  end
  -- when using `split = "belowright new"` closing the fzf
  -- window may not always return to the correct source win
  -- depending on the user's split configuration (#397)
  if self.winopts and self.winopts.split
      and tonumber(self.src_winid)
      and vim.api.nvim_win_is_valid(self.src_winid)
      and self.src_winid ~= vim.api.nvim_get_current_win()
  then
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
  -- Restore insert/normal-terminal mode (#2054)
  if utils.__CTX().mode == "nt" then
    utils.feed_keys_termcodes([[<C-\><C-n>]])
  elseif utils.__CTX().mode == "i" then
    vim.cmd [[noautocmd lua vim.api.nvim_feedkeys('i', 'n', true)]]
  end
  if self.winopts and type(self.winopts.on_close) == "function" then
    self.winopts.on_close()
  end
  self.closing = nil
  self._reuse = nil
  _self = nil
end

function FzfWin.win_leave()
  local self = _self
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
  return tonumber(self._hidden_fzf_bufnr)
      and tonumber(self._hidden_fzf_bufnr) > 0
      and vim.api.nvim_buf_is_valid(self._hidden_fzf_bufnr)
end

-- True after a `:new()` call for a different picker, used in `core.fzf`
-- to avoid post processing an fzf process that was discarded (e.g. kill by :%bw!)
function FzfWin:was_hidden()
  return tonumber(self._hidden_fzf_bufnr)
      and tonumber(self._hidden_fzf_bufnr) > 0
      and not vim.api.nvim_buf_is_valid(self._hidden_fzf_bufnr)
end

---SIGWINCH/on_SIGWINCH is nop if fzf < v0.46
---@param opts table
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
  if not tonumber(bufnr) or not vim.api.nvim_buf_is_valid(bufnr) then return end
  local ok, pid = pcall(fn.jobpid, vim.bo[bufnr].channel)
  if ok and tonumber(pid) > 0 then
    self._o.__sigwinches = scopes or {}
    vim.tbl_map(function(_pid) libuv.process_kill(_pid, 28) end, api.nvim_get_proc_children(pid))
  end
  return true
end

function FzfWin.unhide()
  local self = _self
  if not self or not self:hidden() then return end
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
      utils.wo[self._swin1].eventignorewin = "WinResized"
      local hl = self.hls.scrollfloat_e or "PmenuSbar"
      utils.wo[self._swin1].winhl =
          ("Normal:%s,NormalNC:%s,NormalFloat:%s,EndOfBuffer:%s"):format(hl, hl, hl, hl)
    end
  end
  if self._swin2 and vim.api.nvim_win_is_valid(self._swin2) then
    vim.api.nvim_win_set_config(self._swin2, full)
  else
    full.noautocmd = true
    self._sbuf2 = ensure_tmp_buf(self._sbuf2)
    self._swin2 = utils.nvim_open_win0(self._sbuf2, false, full)
    utils.wo[self._swin2].eventignorewin = "WinResized"
    local hl = self.hls.scrollfloat_f or "PmenuThumb"
    utils.wo[self._swin2].winhl =
        ("Normal:%s,NormalNC:%s,NormalFloat:%s,EndOfBuffer:%s"):format(hl, hl, hl, hl)
  end
end

function FzfWin:update_statusline()
  if not self.winopts.split then return end
  local parts = self.winopts.title or string.format(" %s ", tostring(FzfLua.get_info().cmd))
  parts = type(parts) == "table" and parts
      or type(parts) == "string" and { parts }
      or {}
  for i, t in ipairs(parts) do
    local hl, str = (function()
      if type(t) == "table" then
        return t[2], (t[1] or self.hls.title)
      else
        return self.hls.title, tostring(t)
      end
    end)()
    parts[i] = string.format("%%#%s#%s%%#fzf3#", hl, str)
  end
  local picker = table.remove(parts, 1) or ""
  vim.wo[self.fzf_winid].statusline = "%#fzf1# > %#fzf2#fzf-lua%#fzf3#"
      .. string.format(" %s %s", picker, table.concat(parts, ""))
end

---@param winid integer
---@param winopts table
---@param o table
function FzfWin.update_win_title(winid, winopts, o)
  if type(o.title) ~= "string" and type(o.title) ~= "table" then
    return
  end
  utils.fast_win_set_config(winid,
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

function FzfWin.focus_preview()
  if not _self then return end
  local self = _self
  vim.api.nvim_set_current_win(self.preview_winid)
end

function FzfWin.toggle_preview()
  if not _self then return end
  local self = _self
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
    -- vim.api.nvim_chan_send(vim.bo.channel, vim.keycode(self._fzf_toggle_prev_bind))
  end
  if self.preview_hidden then
    if self:validate_preview() then self:close_preview(true) end
    self:redraw_main()
  elseif not self.preview_hidden then
    self:redraw_main()
    self:redraw_preview()
  end
end

function FzfWin.toggle_preview_wrap()
  if not _self or not _self:validate_preview() then return end
  local self = _self
  self.preview_wrap = not utils.wo[self.preview_winid].wrap
  if self and self:validate_preview() then
    utils.wo[self.preview_winid].wrap = self.preview_wrap
  end
end

function FzfWin.toggle_preview_cw(direction)
  if not _self then return end
  local self = _self
  local curpos = self:normalize_preview_layout().pos
  local pos = { "up", "right", "down", "left" }
  local idx
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

function FzfWin.toggle_preview_behavior()
  if not _self then return end
  local self = _self
  self.toggle_behavior = not self.toggle_behavior and "extend" or nil
  utils.info("preview toggle behavior set to %s", self.toggle_behavior or "default")
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

---@param direction "top"|"bottom"|"half-page-up"|"half-page-down"|"page-up"|"page-down"|"line-up"|"line-down"|"reset"
function FzfWin.preview_scroll(direction)
  if not _self then return end
  local self = _self
  if self:validate_preview()
      and self._previewer
      and self._previewer.scroll then
    -- Do not trigger "ModeChanged"
    utils.eventignore(function() self._previewer:scroll(direction) end)
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
          v = type(v) == "function" and config.get_action_helpstr(v) or tostring(v)
          table.insert(keymaps,
            format_bind(m, k, v, opts.mode_width, opts.keybind_width, opts.name_width))
        end
      end
    end
  end

  ---TODO: we can always parse the action into table to avoid this duplicated logic
  ---(e.g. profile/hide.lua, config.lua)
  ---@param v fzf-lua.ActionSpec
  ---@return string?
  local get_desc = function(v)
    if type(v) == "table" then
      return v.desc or config.get_action_helpstr(v[1]) or config.get_action_helpstr(v.fn) or
          tostring(v)
    elseif v then
      return config.get_action_helpstr(v) or tostring(v)
    end
  end

  -- action keymaps
  if self.actions then
    for k, v in pairs(self.actions) do
      if v then -- skips 'v == false'
        if k == "default" then k = "enter" end
        local desc = get_desc(v)
        table.insert(keymaps,
          format_bind("action", k,
            ("%s"):format(desc):gsub(" ", ""),
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

  local zindex = self.winopts.zindex + 2
  local ch = zindex >= 200 and 0 or vim.o.cmdheight
  local winopts = {
    relative = "editor",
    style = "minimal",
    width = vim.o.columns,
    height = height,
    row = vim.o.lines - height - ch - 1,
    col = 1,
    -- top border only
    border = { "─", "─", "─", " ", " ", " ", " ", " " },
    -- topmost popup (+2 for float border empty/full)
    zindex = zindex,
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
  utils.wo[self.km_winid].winhl =
      string.format("Normal:%s,FloatBorder:%s", opts.normal_hl, opts.border_hl)
  utils.wo[self.km_winid].winblend = opts.winblend
  utils.wo[self.km_winid].foldenable = false
  utils.wo[self.km_winid].wrap = false
  utils.wo[self.km_winid].spell = false
  vim.bo[self.km_bufnr].filetype = "help"

  vim.api.nvim_buf_set_lines(self.km_bufnr, 0, -1, false, lines)
end

return FzfWin
