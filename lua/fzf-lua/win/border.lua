local M = {}

local utils = require "fzf-lua.utils"

---@class fzf-lua.win.borderMetadata
---@field type? 'nvim'|'fzf'
---@field name? 'fzf'|'prev'
---@field nwin? integer
---@field layout? fzf-lua.win.previewPos
---@field opts? fzf-lua.config.Resolved|{}

---@alias fzf-lua.winborder string[]|"none"|"single"|"double"|"rounded"|"solid"|"shadow"

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
  ["border-line"]       = function(_, metadata)
    return require("fzf-lua.profiles.border-fused").winopts.preview.border(_, metadata)
  end,
}

local neovim2fzf = {
  none       = "noborder",
  single     = "border-sharp",
  double     = "border-double",
  rounded    = "border-rounded",
  solid      = "noborder",
  empty      = "border-block",
  shadow     = "border-thinblock",
  bold       = "border-bold",
  block      = "border-block",
  solidblock = "border-block",
  thicc      = "border-bold",
  thiccc     = "border-block",
  thicccc    = "border-block",
}

-- Best approximation of neovim border types to fzf border types
---@param border any
---@param metadata fzf-lua.win.borderMetadata
---@return string|table?
function M.fzf(border, metadata)
  if type(border) == "function" then border = border(nil, metadata) end
  if not border then return "noborder" end
  if border == true then return "border" end
  return type(border) == "string" and (neovim2fzf[border] or border) or nil
end

---@param border any
---@param metadata fzf-lua.win.borderMetadata
---@param silent? boolean|integer
---@return fzf-lua.winborder, integer, integer
function M.nvim(border, metadata, silent)
  if type(border) == "function" then border = border(nil, metadata) end
  if not border then border = "none" end
  if border == true then border = "rounded" end
  -- nvim_open_win valid border
  if type(border) == "string" then
    if not valid_borders[border] then
      if not silent then
        utils.warn("Invalid border style '%s', will use 'rounded'.", border)
      end
      border = "rounded"
    else
      border = valid_borders[border]
      border = type(border) == "function" and border(_, metadata) or border
    end
  elseif type(border) ~= "table" then
    if not silent then
      utils.warn("Invalid border type '%s', will use 'rounded'.", type(border))
    end
    border = "rounded"
  end
  if vim.o.ambiwidth == "double" and type(border) ~= "string" then
    -- when ambiwdith="double" `nvim_open_win` with border chars fails:
    -- with "border chars must be one cell", force string border (#874)
    if not silent then
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
  ---@diagnostic disable-next-line: return-type-mismatch
  return border, up + down, left + right
end

return M
