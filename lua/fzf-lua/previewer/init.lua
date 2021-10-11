local utils = require "fzf-lua.utils"

local Previewer = {}

-- Constructor
setmetatable(Previewer, {
  __call = function (cls, ...)
    return cls:new(...)
  end,
})

-- Previewer base object
function Previewer:new(o, opts)
  o = o or {}
  self = setmetatable({}, { __index = self })
  self.cmd = o.cmd;
  self.args = o.args or "";
  self.relative = o.relative
  self.pager = o.pager
  self.opts = opts;
  return self
end

function Previewer:preview_window(_)
  utils.warn("Previewer:preview_window wasn't implemented, will use defaults")
  return nil
end

Previewer.fzf = {}
Previewer.fzf.cmd = function() return require 'fzf-lua.previewer.fzf'.cmd end
Previewer.fzf.bat = function() return require 'fzf-lua.previewer.fzf'.bat end
Previewer.fzf.head = function() return require 'fzf-lua.previewer.fzf'.head end
Previewer.fzf.cmd_async = function() return require 'fzf-lua.previewer.fzf'.cmd_async end
Previewer.fzf.bat_async = function() return require 'fzf-lua.previewer.fzf'.bat_async end
Previewer.fzf.git_diff = function() return require 'fzf-lua.previewer.fzf'.git_diff end
Previewer.fzf.man_pages = function() return require 'fzf-lua.previewer.fzf'.man_pages end

Previewer.builtin = {}
Previewer.builtin.buffer_or_file = function() return require 'fzf-lua.previewer.builtin'.buffer_or_file end
Previewer.builtin.help_tags = function() return require 'fzf-lua.previewer.builtin'.help_tags end
Previewer.builtin.man_pages = function() return require 'fzf-lua.previewer.builtin'.man_pages end
Previewer.builtin.marks = function() return require 'fzf-lua.previewer.builtin'.marks end

return Previewer
