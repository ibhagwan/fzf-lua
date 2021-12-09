local path = require "fzf-lua.path"
local shell = require "fzf-lua.shell"
local utils = require "fzf-lua.utils"
local Object = require "fzf-lua.class"

local Previewer = {}

Previewer.base = Object:extend()

-- Previewer base object
function Previewer.base:new(o, opts)
  o = o or {}
  self.type = "cmd";
  self.cmd = o.cmd;
  self.args = o.args or "";
  self.relative = o.relative
  self.opts = opts;
  return self
end

function Previewer.base:preview_window(_)
  return nil
end

-- Generic shell command previewer
Previewer.cmd = Previewer.base:extend()

function Previewer.cmd:new(o, opts)
  Previewer.cmd.super.new(self, o, opts)
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
  local act = shell.raw_action(function (items, fzf_lines, _)
    -- only preview first item
    local file = path.entry_to_file(items[1], not self.relative and self.opts.cwd)
    return file.path
  end, filespec)
  return act
end

-- Specialized bat previewer
Previewer.bat = Previewer.cmd:extend()

function Previewer.bat:new(o, opts)
  Previewer.bat.super.new(self, o, opts)
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
Previewer.head = Previewer.cmd:extend()

function Previewer.head:new(o, opts)
  Previewer.head.super.new(self, o, opts)
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
Previewer.cmd_async = Previewer.base:extend()

function Previewer.cmd_async:new(o, opts)
  Previewer.cmd_async.super.new(self, o, opts)
  return self
end

function Previewer.cmd_async:cmdline(o)
  o = o or {}
  local act = shell.preview_action_cmd(function(items)
    local file = path.entry_to_file(items[1], not self.relative and self.opts.cwd)
    local cmd = string.format('%s %s %s', self.cmd, self.args, vim.fn.shellescape(file.path))
    -- uncomment to see the command in the preview window
    -- cmd = vim.fn.shellescape(cmd)
    return cmd
  end, "{}")
  return act
end

Previewer.bat_async = Previewer.cmd_async:extend()

function Previewer.bat_async:new(o, opts)
  Previewer.bat_async.super.new(self, o, opts)
  self.theme = o.theme
  return self
end

function Previewer.bat_async:cmdline(o)
  o = o or {}
  local highlight_line = ""
  if self.opts._line_placeholder then
    highlight_line = string.format("--highlight-line=", self.opts._line_placeholder)
  end
  local act = shell.preview_action_cmd(function(items)
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

Previewer.git_diff = Previewer.cmd_async:extend()

function Previewer.git_diff:new(o, opts)
  Previewer.git_diff.super.new(self, o, opts)
  self.cmd = path.git_cwd(self.cmd, opts.cwd)
  self.pager = o.pager
  return self
end

function Previewer.git_diff:cmdline(o)
  o = o or {}
  local act = shell.preview_action_cmd(function(items)
    local is_deleted = items[1]:match("D"..utils.nbsp) ~= nil
    local is_untracked = items[1]:match("[?RAC]"..utils.nbsp) ~= nil
    local file = path.entry_to_file(items[1], not self.relative and self.opts.cwd)
    local cmd = self.cmd
    local args = self.args
    local pager = ""
    if self.pager and #self.pager>0 and
      vim.fn.executable(self.pager:match("[^%s]+")) == 1 then
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

Previewer.man_pages = Previewer.cmd_async:extend()

function Previewer.man_pages:new(o, opts)
  Previewer.man_pages.super.new(self, o, opts)
  self.cmd = self.cmd or "man"
  return self
end

function Previewer.man_pages:cmdline(o)
  o = o or {}
  local act = shell.preview_action_cmd(function(items)
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
