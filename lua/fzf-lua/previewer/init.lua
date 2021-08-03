local path = require "fzf-lua.path"
local utils = require "fzf-lua.utils"
local raw_action = require("fzf.actions").raw_action

local Previewer = {}
Previewer.base = {}
Previewer.head = {}
Previewer.cmd = {}
Previewer.bat = {}
Previewer.buffer = {}

-- Constructors call on Previewer.<o>()
for c, _ in pairs(Previewer) do
  setmetatable(Previewer[c], {
    __call = function (cls, ...)
      return cls:new(...)
    end,
  })
end

-- Previewer base object
function Previewer.base:new(o, opts)
  o = o or {}
  self = setmetatable({}, { __index = self })
  self.type = "cmd";
  self.cmd = o.cmd;
  self.args = o.args or "";
  self.opts = opts;
  return self
end

function Previewer.base:filespec(entry)
  local file = path.entry_to_file(entry, nil, true)
  print(file.file, file.line, file.col)
  return file
end

-- Generic shell command previewer
function Previewer.cmd:new(o, opts)
  self = setmetatable(Previewer.base(o, opts), {
    __index = vim.tbl_deep_extend("keep",
      self, Previewer.base
    )})
  return self
end


function Previewer.cmd:cmdline(o)
  o = o or {}
  o.action = o.action or self:action(o)
  return string.format("%s %s `%s`", self.cmd, self.args, o.action)
end

function Previewer.cmd:action(o)
  o = o or {}
  local filespec = "{+}"
  if self.opts._line_placeholder then
    filespec = "{1}"
  end
  local act = raw_action(function (items, fzf_lines, _)
    -- only preview first item
    local file = path.entry_to_file(items[1], self.opts.cwd)
    return file.path
  end, filespec)
  return act
end

-- Specialized bat previewer
function Previewer.bat:new(o, opts)
  self = setmetatable(Previewer.cmd(o, opts), {
    __index = vim.tbl_deep_extend("keep",
      self, Previewer.cmd, Previewer.base
    )})
  self.theme = o.theme
  return self
end

function Previewer.bat:cmdline(o)
  o = o or {}
  o.action = o.action or self:action(o)
  local highlight_line = ""
  if self.opts._line_placeholder then
    highlight_line = string.format("--highlight-line={%d}", self.opts._line_placeholder)
  end
  return string.format("%s %s %s -- `%s`",
    self.cmd, self.args, highlight_line, self:action(o))
  --[[ return string.format("%s %s `%s` -- `%s`",
    self.cmd, self.args, self:action_line(), o.action) ]]
end

-- not in use
function Previewer.bat:action_line(o)
  o = o or {}
  local act = raw_action(function (items, _, _)
    local file = path.entry_to_file(items[1], self.opts.cwd)
    return string.format("--highlight-line=%s", tostring(file.line))
  end)
  return act
end

-- Specialized head previewer
function Previewer.head:new(o, opts)
  self = setmetatable(Previewer.cmd(o, opts), {
    __index = vim.tbl_deep_extend("keep",
      self, Previewer.cmd, Previewer.base
    )})
  self.theme = o.theme
  return self
end

function Previewer.head:cmdline(o)
  o = o or {}
  o.action = o.action or self:action(o)
  local lines = ""
  if self.opts._line_placeholder then
    lines = string.format("--lines={%d}", self.opts._line_placeholder)
  end
  return string.format("%s %s %s -- `%s`",
    self.cmd, self.args, lines, self:action(o))
  --[[ return string.format("%s %s `%s` -- `%s`",
    self.cmd, self.args, self:action_line(), o.action) ]]
end

return Previewer
