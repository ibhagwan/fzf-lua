local path = require "fzf-lua.path"
local utils = require "fzf-lua.utils"
local helpers = require("fzf.helpers")
local previewer_base = require "fzf-lua.previewer"
local raw_action = require("fzf.actions").raw_action

local Previewer = {}
Previewer.base = {}
Previewer.head = {}
Previewer.cmd = {}
Previewer.bat = {}
Previewer.cmd_async = {}
Previewer.bat_async = {}
Previewer.git_diff = {}
Previewer.man_pages = {}
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
  self = setmetatable(previewer_base(o, opts), {
    __index = vim.tbl_deep_extend("keep",
      self, previewer_base
  )})
  self.type = "cmd";
  return self
end

function Previewer.base:preview_window(_)
  return nil
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
  return vim.fn.shellescape(string.format('sh -c "%s %s `%s`"',
    self.cmd, self.args, o.action))
end

function Previewer.cmd:action(o)
  o = o or {}
  local filespec = "{}"
  if self.opts._line_placeholder then
    filespec = "{1}"
  end
  local act = raw_action(function (items, fzf_lines, _)
    -- only preview first item
    local file = path.entry_to_file(items[1], not self.relative and self.opts.cwd)
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
  return vim.fn.shellescape(string.format('sh -c "%s %s %s `%s`"',
    self.cmd, self.args, highlight_line, self:action(o)))
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
  return vim.fn.shellescape(string.format('sh -c "%s %s %s `%s`"',
    self.cmd, self.args, lines, self:action(o)))
end

-- new async_action from nvim-fzf
function Previewer.cmd_async:new(o, opts)
  self = setmetatable(Previewer.base(o, opts), {
    __index = vim.tbl_deep_extend("keep",
      self, Previewer.base
    )})
  return self
end

function Previewer.cmd_async:cmdline(o)
  o = o or {}
  local act = helpers.choices_to_shell_cmd_previewer(function(items)
    local file = path.entry_to_file(items[1], not self.relative and self.opts.cwd)
    local cmd = string.format('%s %s %s', self.cmd, self.args, vim.fn.shellescape(file.path))
    -- uncomment to see the command in the preview window
    -- cmd = vim.fn.shellescape(cmd)
    return cmd
  end, "{}")
  return act
end

function Previewer.bat_async:new(o, opts)
  self = setmetatable(Previewer.cmd_async(o, opts), {
    __index = vim.tbl_deep_extend("keep",
      self, Previewer.cmd_async, Previewer.base
    )})
  self.theme = o.theme
  return self
end

function Previewer.bat_async:cmdline(o)
  o = o or {}
  local highlight_line = ""
  if self.opts._line_placeholder then
    highlight_line = string.format("--highlight-line=", self.opts._line_placeholder)
  end
  local act = helpers.choices_to_shell_cmd_previewer(function(items)
    local file = path.entry_to_file(items[1], not self.relative and self.opts.cwd)
    local cmd = string.format('%s %s %s%s "%s"',
      self.cmd, self.args,
      highlight_line,
      utils._if(#highlight_line>0, tostring(file.line), ""),
      file.path)
    -- uncomment to see the command in the preview window
    -- cmd = vim.fn.shellescape(cmd)
    return cmd
  end, "{}")
  return act
end

function Previewer.git_diff:new(o, opts)
  self = setmetatable(Previewer.cmd_async(o, opts), {
    __index = vim.tbl_deep_extend("keep",
      self, Previewer.cmd_async, Previewer.base
    )})
  self.cmd = path.git_cwd(self.cmd, opts.cwd)
  return self
end

function Previewer.git_diff:cmdline(o)
  o = o or {}
  local act = helpers.choices_to_shell_cmd_previewer(function(items)
    local is_deleted = items[1]:match("D"..utils.nbsp) ~= nil
    local is_untracked = items[1]:match("[?RAC]"..utils.nbsp) ~= nil
    local file = path.entry_to_file(items[1], not self.relative and self.opts.cwd)
    local cmd = self.cmd
    local args = self.args
    local pager = nil
    if self.pager and vim.fn.executable(self.pager) == 1 then
      pager = '| ' .. self.pager
    end
    if is_untracked then args = args .. " --no-index /dev/null" end
    if is_deleted then
      cmd = self.cmd:gsub("diff", "show HEAD:")
      cmd = string.format('%s"%s"', cmd, path.relative(file.path, self.opts.cwd))
    else
      cmd = string.format('%s %s %s %s', cmd, args, vim.fn.shellescape(file.path), pager)
    end
    -- uncomment to see the command in the preview window
    -- cmd = vim.fn.shellescape(cmd)
    return cmd
  end, "{}")
  return act
end

function Previewer.man_pages:new(o, opts)
  self = setmetatable(Previewer.cmd_async(o, opts), {
    __index = vim.tbl_deep_extend("keep",
      self, Previewer.cmd_async, Previewer.base
    )})
  self.cmd = self.cmd or "man"
  return self
end

function Previewer.man_pages:cmdline(o)
  o = o or {}
  local act = helpers.choices_to_shell_cmd_previewer(function(items)
    -- local manpage = require'fzf-lua.providers.manpages'.getmanpage(items[1])
    local manpage = items[1]:match("[^[,( ]+")
    local cmd = ("%s %s %s"):format(
      self.cmd, self.args, vim.fn.shellescape(manpage))
    -- uncomment to see the command in the preview window
    -- cmd = vim.fn.shellescape(cmd)
    return cmd
  end, "{}")
  return act
end

return Previewer
