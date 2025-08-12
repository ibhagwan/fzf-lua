local Object = require "fzf-lua.class"

local M = {}

---@class fzf-lua.previewer.SwiperBase: fzf-lua.Object,{}
M.base = Object:extend()

---@class fzf-lua.previewer.Swiper : fzf-lua.previewer.SwiperBase,{}
---@field super fzf-lua.previewer.SwiperBase
M.default = M.base:extend()

function M.default:new(o, opts)
  M.default.super.new(self, o, opts)
  return self
end

return M
