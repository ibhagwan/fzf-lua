local uv = vim.uv or vim.loop
local path = require "fzf-lua.path"
local shell = require "fzf-lua.shell"
local utils = require "fzf-lua.utils"
local libuv = require "fzf-lua.libuv"
local Object = require "fzf-lua.class"

local Previewer = {}

Previewer.base = Object:extend()

-- Previewer base object
function Previewer.base:new(o, opts)
  o = o or {}
  self.type = "cmd";
  self.cmd = o.cmd;
  if type(self.cmd) == "function" then
    self.cmd = self.cmd()
  end
  self.args = o.args or "";
  self.preview_offset = o.preview_offset
  self.opts = opts;
  return self
end

function Previewer.base:preview_window(_)
  return nil
end

function Previewer.base:_preview_offset()
  if self.opts.preview_offset or self.preview_offset then
    return self.opts.preview_offset or self.preview_offset
  end
  --[[
    #
    #   Explanation of the fzf preview offset options:
    #
    #   ~3    Top 3 lines as the fixed header
    #   +{2}  Base scroll offset extracted from the second field
    #   +3    Extra offset to compensate for the 3-line header
    #   /2    Put in the middle of the preview area
    #
    '--preview-window '~3:+{2}+3/2''
  ]]
  if self.opts.line_field_index then
    return ("+%s-/2"):format(self.opts.line_field_index)
  end
end

function Previewer.base:fzf_delimiter()
  -- set delimiter to ':'
  -- entry format is 'file:line:col: text'
  local delim = self.opts.fzf_opts and self.opts.fzf_opts["--delimiter"]
  if not delim then
    delim = "[:]"
  elseif not delim:match(":") then
    if delim:match("%[.*%]") then
      delim = delim:gsub("%]", ":]")
    else
      -- remove surrounding quotes
      delim = delim:match("^'?(.*)'$?") or delim
      delim = "[" .. utils.rg_escape(delim):gsub("%]", "\\]") .. ":]"
    end
  end
  return delim
end

-- Generic shell command previewer
Previewer.cmd = Previewer.base:extend()

function Previewer.cmd:new(o, opts)
  Previewer.cmd.super.new(self, o, opts)
  return self
end

function Previewer.cmd:format_cmd(cmd, args, action, extra_args)
  return string.format([[%s %s %s "$(%s)"]],
    cmd, args or "", extra_args or "", action)
end

function Previewer.cmd:cmdline(o)
  o = o or {}
  o.action = o.action or self:action(o)
  return self:format_cmd(self.cmd, self.args, o.action)
end

function Previewer.cmd:action(o)
  o = o or {}
  local act = shell.raw_action(function(items, _, _)
    local entry = path.entry_to_file(items[1], self.opts)
    return entry.bufname or entry.path
  end, self.opts.field_index_expr or "{}", self.opts.debug)
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
  local extra_args = ""
  if self.theme then
    extra_args = string.format([[ --theme="%s"]], self.theme)
  end
  if self.opts.line_field_index then
    extra_args = extra_args .. string.format(" --highlight-line=%s", self.opts.line_field_index)
  end
  return self:format_cmd(self.cmd, self.args, o.action, extra_args)
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
  local lines = "--lines=-0"
  -- print all lines instead
  -- if self.opts.line_field_index then
  --   lines = string.format("--lines=%s", self.opts.line_field_index)
  -- end
  return self:format_cmd(self.cmd, self.args, o.action, lines)
end

-- new async_action from nvim-fzf
Previewer.cmd_async = Previewer.base:extend()

function Previewer.cmd_async:new(o, opts)
  Previewer.cmd_async.super.new(self, o, opts)
  return self
end

local grep_tag = function(file, tag)
  local line = 1
  local filepath = file
  local pattern = utils.rg_escape(vim.trim(tag))
  if not pattern or not filepath then return line end
  local grep_cmd = vim.fn.executable("rg") == 1
      and { "rg", "--line-number" }
      or { "grep", "-n", "-P" }
  -- ctags uses '$' at the end of short patterns
  -- 'rg|grep' does not match these properly when
  -- 'fileformat' isn't set to 'unix', when set to
  -- 'dos' we need to prepend '$' with '\r$' with 'rg'
  -- it is simpler to just ignore it completely.
  --[[ local ff = fileformat(filepath)
  if ff == 'dos' then
    pattern = pattern:gsub("\\%$$", "\\r%$")
  else
    pattern = pattern:gsub("\\%$$", "%$")
  end --]]
  -- equivalent pattern to `rg --crlf`
  -- see discussion in #219
  pattern = pattern:gsub("\\%$$", "\\r??%$")
  local cmd = utils.tbl_deep_clone(grep_cmd)
  table.insert(cmd, pattern)
  table.insert(cmd, filepath)
  local out, rc = utils.io_system(cmd)
  if rc == 0 then
    line = tonumber(out:match("[^:]+")) or 1
  else
    utils.warn(("previewer: unable to find pattern '%s' in file '%s'"):format(pattern, file))
  end
  return tonumber(line)
end

function Previewer.cmd_async:parse_entry_and_verify(entrystr)
  local entry = path.entry_to_file(entrystr, self.opts)
  -- make relative for bat's header display
  local filepath = path.relative_to(entry.bufname or entry.path or "", uv.cwd())
  if self.opts._ctag then
    -- NOTE: override `entry.ctag` with the unescaped version
    entry.ctag = path.entry_to_ctag(entry.stripped, true)
    if not tonumber(entry.line) or tonumber(entry.line) < 1 then
      -- default tags are without line numbers
      -- make sure we don't already have line #
      -- (in the case the line no. is actually 1)
      local line = entry.stripped:match("[^:]+(%d+):")
      if not line and entry.ctag then
        entry.line = grep_tag(filepath, entry.ctag)
      end
    end
  end
  local errcmd = nil
  if filepath:match("^%[DEBUG]") then
    errcmd = "echo " .. libuv.shellescape(tostring(filepath:gsub("^%[DEBUG]", "")))
  else
    -- verify the file exists on disk and is accessible
    if #filepath == 0 or not uv.fs_stat(filepath) then
      errcmd = "echo " .. libuv.shellescape(
        string.format("'%s: NO SUCH FILE OR ACCESS DENIED",
          filepath and #filepath > 0 and filepath or "<null>"))
    end
  end
  return filepath, entry, errcmd
end

function Previewer.cmd_async:cmdline(o)
  o = o or {}
  local act = shell.raw_preview_action_cmd(function(items)
    local filepath, _, errcmd = self:parse_entry_and_verify(items[1])
    local cmd = errcmd or ("%s %s %s"):format(
      self.cmd, self.args, libuv.shellescape(filepath))
    return cmd
  end, "{}", self.opts.debug)
  return act
end

Previewer.bat_async = Previewer.cmd_async:extend()

function Previewer.bat_async:_preview_offset()
  if self.opts.preview_offset or self.preview_offset then
    return self.opts.preview_offset or self.preview_offset
  end
  --[[
    #
    #   Explanation of the fzf preview offset options:
    #
    #   ~3    Top 3 lines as the fixed header
    #   +{2}  Base scroll offset extracted from the second field
    #   +3    Extra offset to compensate for the 3-line header
    #   /2    Put in the middle of the preview area
    #
    '--preview-window '~3:+{2}+3/2''
  ]]
  if not self.args or not self.args:match("%-%-style=default") then
    -- we don't need affixed header unless we use bat default style
    -- TODO: should also adjust for "--style=header-filename"
    if self.opts.line_field_index then
      return ("+%s-/2"):format(self.opts.line_field_index)
    end
  else
    if self.opts.line_field_index then
      return ("~3:+%s+3/2"):format(self.opts.line_field_index)
    else
      -- no line offset, affix header
      return "~3"
    end
  end
end

function Previewer.bat_async:new(o, opts)
  Previewer.bat_async.super.new(self, o, opts)
  self.theme = o.theme
  return self
end

function Previewer.bat_async:cmdline(o)
  o = o or {}
  local act = shell.raw_preview_action_cmd(function(items, fzf_lines)
    local filepath, entry, errcmd = self:parse_entry_and_verify(items[1])
    local line_range = ""
    if entry.ctag then
      -- this is a ctag without line numbers, since we can't
      -- provide the preview file offset to fzf via the field
      -- index expression we use '--line-range' instead
      local start_line = math.max(1, entry.line - fzf_lines / 2)
      local end_line = start_line + fzf_lines - 1
      line_range = ("--line-range=%d:%d"):format(start_line, end_line)
    end
    local cmd = errcmd or ("%s %s %s %s %s %s"):format(
      self.cmd, self.args,
      self.theme and string.format([[--theme="%s"]], self.theme) or "",
      self.opts.line_field_index and tonumber(entry.line) and tonumber(entry.line) > 0
      and string.format("--highlight-line=%d", entry.line) or "",
      line_range,
      libuv.shellescape(filepath))
    return cmd
  end, "{}", self.opts.debug)
  return act
end

Previewer.git_diff = Previewer.base:extend()

function Previewer.git_diff:new(o, opts)
  Previewer.git_diff.super.new(self, o, opts)
  self.cmd_deleted = path.git_cwd(o.cmd_deleted, opts)
  self.cmd_modified = path.git_cwd(o.cmd_modified, opts)
  self.cmd_untracked = path.git_cwd(o.cmd_untracked, opts)
  self.pager = opts.preview_pager == nil and o.pager or opts.preview_pager
  if type(self.pager) == "function" then
    self.pager = self.pager()
  end
  do
    -- populate the icon mappings
    local icons_overrides = o._fn_git_icons and o._fn_git_icons()
    self.git_icons = {}
    for _, i in ipairs({ "D", "M", "R", "A", "C", "T", "?" }) do
      self.git_icons[i] =
          icons_overrides and icons_overrides[i] and
          utils.lua_regex_escape(icons_overrides[i].icon) or i
    end
  end
  return self
end

function Previewer.git_diff:cmdline(o)
  o = o or {}
  local act = shell.raw_preview_action_cmd(function(items, fzf_lines, fzf_columns)
    if not items or utils.tbl_isempty(items) then
      utils.warn("shell error while running preview action.")
      return
    end
    local is_deleted = items[1]:match(self.git_icons["D"] .. utils.nbsp) ~= nil
    local is_modified = items[1]:match("[" ..
      self.git_icons["M"] ..
      self.git_icons["R"] ..
      self.git_icons["A"] ..
      self.git_icons["T"] ..
      "]" .. utils.nbsp) ~= nil
    local is_untracked = items[1]:match("[" ..
      self.git_icons["?"] ..
      self.git_icons["C"] ..
      "]" .. utils.nbsp) ~= nil
    local file = items[1]
    if file:match("%s%->%s") then
      -- for renames, we take only the last part (#864)
      file = file:match("%s%->%s(.*)$")
    end
    file = path.entry_to_file(file, self.opts)
    local cmd = nil
    if is_modified then
      cmd = self.cmd_modified
    elseif is_deleted then
      cmd = self.cmd_deleted
    elseif is_untracked then
      local stat = uv.fs_stat(file.path)
      if stat and stat.type == "directory" then
        cmd = utils._if_win({ "dir" }, { "ls", "-la" })
      else
        cmd = self.cmd_untracked
      end
    end
    if not cmd then return "" end
    if type(cmd) == "table" then return table.concat(cmd, " ") end
    local pager = ""
    if self.pager and #self.pager > 0 and
        vim.fn.executable(self.pager:match("[^%s]+")) == 1 then
      -- style 2: as we are unable to use %var% within a "cmd /c" without !var! expansion
      -- https://superuser.com/questions/223104/setting-and-using-variable-within-same-command-line-in-windows-cmd-ex
      pager = "| " .. utils._if_win_normalize_vars(self.pager, 2)
    end
    -- with default commands we add the filepath at the end.
    -- If the user configured a more complex command, e.g.:
    -- git_diff = {
    --   cmd_modified = "git diff --color HEAD %s | less -SEX"
    -- }
    -- we use ':format' directly on the user's command, see
    -- issue #392 for more info (limiting diff output width)
    local fname_escaped = libuv.shellescape(file.path)
    if cmd:match("[<{]file[}>]") then
      cmd = cmd:gsub("[<{]file[}>]", fname_escaped)
    elseif cmd:match("%%s") then
      cmd = cmd:format(fname_escaped)
    else
      cmd = string.format("%s %s", cmd, fname_escaped)
    end
    local env = {
      ["LINES"]               = fzf_lines,
      ["COLUMNS"]             = fzf_columns,
      ["FZF_PREVIEW_LINES"]   = fzf_lines,
      ["FZF_PREVIEW_COLUMNS"] = fzf_columns,
    }
    local setenv = utils.shell_setenv_str(env)
    cmd = string.format("%s %s %s", table.concat(setenv, " "), cmd, pager)
    -- TODO: exlpore why passing env (which we btw don't need anymore)
    -- makes git-delta use a different syntax theme
    return { cmd = cmd, env = nil }
  end, "{}", self.opts.debug)
  return act
end

Previewer.man_pages = Previewer.base:extend()

function Previewer.man_pages:new(o, opts)
  Previewer.man_pages.super.new(self, o, opts)
  self.cmd = o.cmd or "man -c %s | col -bx"
  self.cmd = type(self.cmd) == "function" and self.cmd() or self.cmd
  return self
end

function Previewer.man_pages:cmdline(o)
  o = o or {}
  local act = shell.raw_preview_action_cmd(function(items)
    local manpage = require("fzf-lua.providers.manpages").manpage_sh_arg(items[1])
    local cmd = self.cmd:format(manpage)
    return cmd
  end, "{}", self.opts.debug)
  return act
end

Previewer.help_tags = Previewer.base:extend()

function Previewer.help_tags:fzf_delimiter()
  return self.opts.fzf_opts and self.opts.fzf_opts["--delimiter"] or nil
end

function Previewer.help_tags:new(o, opts)
  Previewer.help_tags.super.new(self, o, opts)
  self.cmd = self.cmd or vim.fn.executable("bat") == 1
      and "bat -p -l help --color=always %s"
      or "cat %s"
  return self
end

function Previewer.help_tags:cmdline(o)
  o = o or {}
  local act = shell.raw_preview_action_cmd(function(items)
    local vimdoc = items[1]:match(string.format("[^%s]+$", utils.nbsp))
    local tag = items[1]:match("^[^%s]+")
    local ext = path.extension(vimdoc)
    local cmd = self.cmd:format(libuv.shellescape(vimdoc))
    -- If 'bat' is available attempt to get the helptag line
    -- and start the display of the help file from the tag
    if self.cmd:match("^bat ") then
      local line = grep_tag(vimdoc, ext == "md" and tag or string.format("*%s*", tag))
      if tonumber(line) > 0 then
        -- this is a ctag without line numbers, since we can't
        -- provide the preview file offset to fzf via the field
        -- index expression we use '--line-range' instead
        cmd = cmd .. string.format(" --line-range=%d:", tonumber(line))
      end
    end
    return cmd
  end, "{}", self.opts.debug)
  return act
end

return Previewer
