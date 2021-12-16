local path = require "fzf-lua.path"
local shell = require "fzf-lua.shell"
local utils = require "fzf-lua.utils"
local Object = require "fzf-lua.class"

local api = vim.api
local fn = vim.fn

local Previewer = {}

Previewer.base = Object:extend()

function Previewer.base:new(o, opts, fzf_win)
  o = o or {}
  self.type = "builtin"
  self.opts = opts;
  self.win = fzf_win
  self.delay = self.win.winopts.preview.delay or 100
  self.title = self.win.winopts.preview.title
  self.winopts = self.win.winopts.preview.winopts
  self.syntax = o.syntax
  self.syntax_delay = o.syntax_delay
  self.syntax_limit_b = o.syntax_limit_b
  self.syntax_limit_l = o.syntax_limit_l
  self.backups = {}
  return self
end

function Previewer.base:close()
  self:restore_winopts(self.win.preview_winid)
  self:clear_preview_buf()
  self.backups = {}
end

function Previewer.base:gen_winopts()
  local winopts = { wrap = self.win.preview_wrap }
  return vim.tbl_extend("keep", winopts, self.winopts)
end

function Previewer.base:backup_winopts(win)
  if not win or not api.nvim_win_is_valid(win) then return end
  for opt, _ in pairs(self:gen_winopts()) do
    if utils.nvim_has_option(opt) then
      self.backups[opt] = api.nvim_win_get_option(win, opt)
    end
  end
end

function Previewer.base:restore_winopts(win)
  if not win or not api.nvim_win_is_valid(win) then return end
  for opt, value in pairs(self.backups) do
    vim.api.nvim_win_set_option(win, opt, value)
  end
end

function Previewer.base:set_winopts(win)
  if not win or not api.nvim_win_is_valid(win) then return end
  for opt, v in pairs(self:gen_winopts()) do
    if utils.nvim_has_option(opt) then
      api.nvim_win_set_option(win, opt, v)
    end
  end
end

function Previewer.base:set_tmp_buffer()
  if not self.win or not self.win:validate_preview() then return end
  local tmp_buf = api.nvim_create_buf(false, true)
  api.nvim_buf_set_option(tmp_buf, 'bufhidden', 'wipe')
  api.nvim_win_set_buf(self.win.preview_winid, tmp_buf)
  return tmp_buf
end

function Previewer.base:clear_preview_buf()
  local retbuf = nil
  if self.win and self.win:validate_preview() then
    -- attach a temp buffer to the window
    -- so we can safely delete the buffer
    -- ('nvim_buf_delete' removes the attached win)
    retbuf = self:set_tmp_buffer()
  end
  if self.preview_bufloaded then
    local bufnr = self.preview_bufnr
    if vim.api.nvim_buf_is_valid(bufnr) then
      api.nvim_buf_call(bufnr, function()
        vim.cmd('delm \\"')
      end)
      vim.api.nvim_buf_delete(bufnr, {force=true})
    end
  end
  self.preview_bufnr = nil
  self.preview_isterm = nil
  self.preview_bufloaded = nil
  self.loaded_entry = nil
  return retbuf
end

function Previewer.base:display_last_entry()
  self:display_entry(self.last_entry)
end

function Previewer.base:display_entry(entry_str)
  if not entry_str then return
  else
    -- save last entry even if we don't display
    self.last_entry = entry_str
  end
  if not self.win or not self.win:validate_preview() then return end
  if rawequal(next(self.backups), nil) then
      self:backup_winopts(self.win.src_winid)
  end
  local previous_bufnr = api.nvim_win_get_buf(self.win.preview_winid)
  assert(not self.preview_bufnr or previous_bufnr == self.preview_bufnr)
  -- clear the current preview buffer
  -- store the new preview buffer
  local should_clear = self.should_clear_preview and
    self:should_clear_preview(entry_str)
  if should_clear == nil or should_clear == true then
    self.preview_bufnr = self:clear_preview_buf()
  end

  local populate_preview_buf = function(entry_str)
    if not self.win or not self.win:validate_preview() then return end

    -- specialized previewer populate function
    self:populate_preview_buf(entry_str)

    -- set preview window options
    if not self.preview_isterm then
      self:set_winopts(self.win.preview_winid)
    end

    -- reset the preview window highlights
    self.win:reset_win_highlights(self.win.preview_winid)
  end

  if not self._entry_count then self._entry_count=1
  else self._entry_count = self._entry_count+1 end
  local entry_count = self._entry_count
  if self.delay>0 then
    vim.defer_fn(function()
      -- only display if entry hasn't changed
      if self._entry_count == entry_count then
        populate_preview_buf(entry_str)
      end
    end, self.delay)
  else
    populate_preview_buf(entry_str)
  end

end

function Previewer.base:action(_)
  local act = shell.raw_action(function (items, _, _)
    self:display_entry(items[1])
    return ""
  end, "{}")
  return act
end

function Previewer.base:cmdline(_)
  return vim.fn.shellescape(self:action())
  -- return 'true'
end

function Previewer.base:preview_window(_)
  if self.win and not self.win.winopts.split then
    return 'nohidden:right:0'
  else
    return nil
  end
end

function Previewer.base:scroll(direction)
  local preview_winid = self.win.preview_winid
  if preview_winid < 0 or not direction then return end

  if direction == 0 then
    vim.api.nvim_win_call(preview_winid, function()
      -- for some reason 'nvim_win_set_cursor'
      -- only moves forward, so set to (1,0) first
      api.nvim_win_set_cursor(0, {1, 0})
      api.nvim_win_set_cursor(0, self.orig_pos)
      utils.zz()
    end)
  else
    -- DO NOT NEED THIS WORKAROUND
    -- since we are no longer setting the terminal buffer
    -- directly into the preview window we can scroll norally
    --[[ if self.preview_isterm then
      -- can't use ":norm!" with terminal buffers due to:
      -- 'Vim(normal):Can't re-enter normal mode from terminal mode'
      -- https://github.com/neovim/neovim/issues/4895#issuecomment-303073838
      -- according to the above comment feedkeys is the correct workaround
      -- TODO: hide the typed command from the user (possible?)
      local input = direction > 0 and "<C-d>" or "<C-u>"
      vim.cmd("stopinsert")
      utils.feed_keys_termcodes((':noa lua vim.api.nvim_win_call(' ..
        '%d, function() vim.cmd("norm! <C-v>%s") vim.cmd("startinsert") end)<CR>'):
        format(tonumber(preview_winid), input))
    else --]]
      -- local input = direction > 0 and [[]] or [[]]
      -- local input = direction > 0 and [[]] or [[]]
      -- ^D = 0x04, ^U = 0x15 ('g8' on char to display)
      local input = ('%c'):format(utils._if(direction>0, 0x04, 0x15))
      vim.api.nvim_win_call(preview_winid, function()
        vim.cmd([[norm! ]] .. input)
        utils.zz()
      end)
    -- end
  end
  self.win:update_scrollbar()
end


Previewer.buffer_or_file = Previewer.base:extend()

function Previewer.buffer_or_file:new(o, opts, fzf_win)
  Previewer.buffer_or_file.super.new(self, o, opts, fzf_win)
  return self
end

function Previewer.buffer_or_file:parse_entry(entry_str)
  local entry = path.entry_to_file(entry_str, self.opts.cwd)
  return entry
end

function Previewer.buffer_or_file:should_clear_preview(entry)
  -- we don't have a previous entry to compare to
  -- return 'true' so the buffer will be loaded in
  -- ::populate_preview_buf
  if not self.loaded_entry then return true end
  if type(entry) == 'string' then
    entry = self:parse_entry(entry)
  end
  if (entry.bufnr and entry.bufnr == self.loaded_entry.bufnr) or
    (not entry.bufnr and entry.path and entry.path == self.loaded_entry.path) then
    return false
  end
  return true
end

function Previewer.buffer_or_file:populate_preview_buf(entry_str)
  if not self.win or not self.win:validate_preview() then return end
  local entry = self:parse_entry(entry_str)
  if vim.tbl_isempty(entry) then return end
  if not self:should_clear_preview(entry) then
    -- same file/buffer as previous entry
    -- no need to reload content
    -- call post to set cusror location
    self:preview_buf_post(entry)
  elseif entry.bufnr and api.nvim_buf_is_loaded(entry.bufnr) then
    -- WE NO LONGER REUSE THE CURRENT BUFFER (except for term)
    -- this changes the buffer's 'getbufinfo[1].lastused'
    -- which messes up our `buffers()` sort
    self.preview_isterm = entry.terminal
    --[[ if self.preview_isterm then
      -- display the buffer in the preview
      api.nvim_win_set_buf(self.win.preview_winid, entry.bufnr)
      -- store current preview buffer
      self.preview_bufnr = entry.bufnr
    else --]]
      -- mark the buffer for unloading the next call
      self.preview_bufloaded = true
      entry.filetype = vim.api.nvim_buf_get_option(entry.bufnr, 'filetype')
      local lines = vim.api.nvim_buf_get_lines(entry.bufnr, 0, -1, false)
      vim.api.nvim_buf_set_lines(self.preview_bufnr, 0, -1, false, lines)
    -- end
    self:preview_buf_post(entry)
  elseif entry.uri then
    -- LSP 'jdt://' entries, see issue #195
    -- https://github.com/ibhagwan/fzf-lua/issues/195
    vim.api.nvim_win_call(self.win.preview_winid, function()
      vim.lsp.util.jump_to_location(entry)
      self.preview_bufnr = vim.api.nvim_get_current_buf()
    end)
    self:preview_buf_post(entry)
  else
    if entry.bufnr then
      -- buffer was unloaded, can happen when calling `lines`
      -- with `set nohidden`, fix entry.path since it contains
      -- filename only
      entry.path = path.relative(vim.api.nvim_buf_get_name(entry.bufnr), vim.loop.cwd())
    end
    -- mark the buffer for unloading the next call
    self.preview_bufloaded = true
    -- make sure the file is readable (or bad entry.path)
    if not entry.path or not vim.loop.fs_stat(entry.path) then return end
    if utils.perl_file_is_binary(entry.path) then
      vim.api.nvim_buf_set_lines(self.preview_bufnr, 0, -1, false, {
        "Preview is not supported for binary files."
      })
      self:preview_buf_post(entry)
      return
    end
    -- read the file into the buffer
    utils.read_file_async(entry.path, vim.schedule_wrap(function(data)
      if not vim.api.nvim_buf_is_valid(self.preview_bufnr) then
        return
      end

      local lines = vim.split(data, "[\r]?\n")

      -- if file ends in new line, don't write an empty string as the last
      -- line.
      if data:sub(#data, #data) == "\n" or data:sub(#data-1,#data) == "\r\n" then
        table.remove(lines)
      end

      local ok = pcall(vim.api.nvim_buf_set_lines, self.preview_bufnr, 0, -1, false, lines)
      if not ok then
        return
      end
      self:preview_buf_post(entry)
    end))
  end
end

function Previewer.buffer_or_file:do_syntax(entry)
  if not self.preview_bufnr then return end
  if not entry or not entry.path then return end
  local bufnr = self.preview_bufnr
  local preview_winid = self.win.preview_winid
  if self.preview_bufloaded and vim.bo[bufnr].filetype == '' then
    if fn.bufwinid(bufnr) == preview_winid then
      -- do not enable for large files, treesitter still has perf issues:
      -- https://github.com/nvim-treesitter/nvim-treesitter/issues/556
      -- https://github.com/nvim-treesitter/nvim-treesitter/issues/898
      local lcount = api.nvim_buf_line_count(bufnr)
      local bytes = api.nvim_buf_get_offset(bufnr, lcount)
      local syntax_limit_reached = 0
      if self.syntax_limit_l > 0 and lcount > self.syntax_limit_l then
        syntax_limit_reached = 1
      end
      if self.syntax_limit_b > 0 and bytes > self.syntax_limit_b then
        syntax_limit_reached = 2
      end
      if syntax_limit_reached > 0 then
        utils.info(string.format(
          "syntax disabled for '%s' (%s), consider increasing '%s(%d)'", entry.path,
          utils._if(syntax_limit_reached==1,
            ("%d lines"):format(lcount),
            ("%db"):format(bytes)),
          utils._if(syntax_limit_reached==1, 'syntax_limit_l', 'syntax_limit_b'),
          utils._if(syntax_limit_reached==1, self.syntax_limit_l, self.syntax_limit_b)
        ))
      end
      if syntax_limit_reached == 0 then
        if entry.filetype == 'help' then
        -- if entry.filetype and #entry.filetype>0 then
          -- filetype was saved from a loaded buffer
          -- this helps avoid losing highlights for help buffers
          -- which are '.txt' files with 'ft=help'
          -- api.nvim_buf_set_option(bufnr, 'filetype', entry.filetype)
          pcall(api.nvim_buf_set_option, bufnr, 'filetype', entry.filetype)
        else
          -- prepend the buffer number to the path and
          -- set as buffer name, this makes sure 'filetype detect'
          -- gets the right filetype which enables the syntax
          local tempname = path.join({tostring(bufnr), entry.path})
          pcall(api.nvim_buf_set_name, bufnr, tempname)
        end
        -- nvim_buf_call has less side-effects than window switch
        api.nvim_buf_call(bufnr, function()
          vim.cmd('filetype detect')
        end)
      end
    end
  end
end

function Previewer.buffer_or_file:set_cursor_hl(entry)
  vim.api.nvim_win_call(self.win.preview_winid, function()
    local lnum, col = tonumber(entry.line), tonumber(entry.col) or 1
    local pattern = entry.pattern or entry.text

    if not lnum or lnum < 1 then
      api.nvim_win_set_cursor(0, {1, 0})
      if pattern ~= '' then
        fn.search(pattern, 'c')
      end
    else
      if not pcall(api.nvim_win_set_cursor, 0, {lnum, math.max(0, col - 1)}) then
        return
      end
    end

    utils.zz()

    self.orig_pos = api.nvim_win_get_cursor(0)

    fn.clearmatches()

    if self.win.winopts.hl.cursor and lnum and lnum > 0 and col and col > 1 then
      fn.matchaddpos(self.win.winopts.hl.cursor, {{lnum, math.max(1, col)}}, 11)
    end
  end)
end

function Previewer.buffer_or_file:update_border(entry)
  if self.title then
    if entry.path and self.opts.cwd then
      entry.path = path.relative(entry.path, self.opts.cwd)
    end
    local title = (' %s '):format(entry.path or entry.uri)
    if entry.bufnr then
      -- local border_width = api.nvim_win_get_width(self.win.preview_winid)
      local buf_str = ('buf %d:'):format(entry.bufnr)
      title = (' %s %s '):format(buf_str, entry.path)
    end
    self.win:update_title(title)
  end
  self.win:update_scrollbar()
end

function Previewer.buffer_or_file:preview_buf_post(entry)
  -- set preview win options or load the file
  -- if not already loaded from buffer
  self:set_cursor_hl(entry)

  -- syntax highlighting
  if self.syntax then
    if self.syntax_delay > 0 then
      vim.defer_fn(function()
        self:do_syntax(entry)
      end, self.syntax_delay)
    else
      self:do_syntax(entry)
    end
  end

  self:update_border(entry)

  -- save the loaded entry so we can compare
  -- bufnr|path with the next entry, if equal
  -- we can skip loading the buffer again
  self.loaded_entry = entry
end


Previewer.help_tags = Previewer.base:extend()

function Previewer.help_tags:new(o, opts, fzf_win)
  Previewer.help_tags.super.new(self, o, opts, fzf_win)
  self.split = o.split
  self.help_cmd = o.help_cmd or "help"
  self.filetype = "help"
  self:init_help_win()
  return self
end

function Previewer.help_tags:gen_winopts()
  local winopts = {
    wrap    = self.win.preview_wrap,
    number  = false
  }
  return vim.tbl_extend("keep", winopts, self.winopts)
end

function Previewer.help_tags:exec_cmd(str)
  str = str or ''
  vim.cmd(("noauto %s %s %s"):format(self.split, self.help_cmd, str))
end

function Previewer.help_tags:parse_entry(entry_str)
  return entry_str
end

local function curtab_helpbuf()
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(nil)) do
    local bufnr = vim.api.nvim_win_get_buf(w)
    local bufinfo = vim.fn.getbufinfo(bufnr)[1]
    if bufinfo.variables and bufinfo.variables.current_syntax == 'help' then
      return bufnr, w
    end
  end
  return nil, nil
end

function Previewer.help_tags:init_help_win(str)
  if not self.split or
    (self.split ~= "topleft" and self.split ~= "botright") then
    self.split = "botright"
  end
  local orig_winid = api.nvim_get_current_win()
  self.help_bufnr, self.help_winid = curtab_helpbuf()
  -- do not open a new 'help' window
  -- if one already exists
  if not self.help_bufnr then
    self:exec_cmd(str)
    self.help_bufnr = api.nvim_get_current_buf()
    self.help_winid = api.nvim_get_current_win()
    pcall(vim.api.nvim_win_set_height, 0, 0)
    pcall(vim.api.nvim_win_set_width, 0, 0)
    api.nvim_set_current_win(orig_winid)
  end
end

function Previewer.help_tags:populate_preview_buf(entry_str)
  local entry = self:parse_entry(entry_str)
  vim.api.nvim_win_call(self.help_winid, function()
    self.prev_help_bufnr = api.nvim_get_current_buf()
    self:exec_cmd(entry)
    vim.api.nvim_buf_set_option(0, 'filetype', self.filetype)
    self.preview_bufnr = api.nvim_get_current_buf()
    self.orig_pos = api.nvim_win_get_cursor(0)
  end)
  api.nvim_win_set_buf(self.win.preview_winid, self.preview_bufnr)
  api.nvim_win_set_cursor(self.win.preview_winid, self.orig_pos)
  self.win:update_scrollbar()
  if self.prev_help_bufnr ~= self.preview_bufnr and
    -- only delete the help buffer when the help
    -- tag triggers opening a different help file
    api.nvim_buf_is_valid(self.prev_help_bufnr) then
    api.nvim_buf_delete(self.prev_help_bufnr, {force=true})
    -- save the last buffer so we can close it
    -- at the win_leave event
    self.prev_help_bufnr = self.preview_bufnr
  end
end

function Previewer.help_tags:win_leave()
  if self.help_winid and vim.api.nvim_win_is_valid(self.help_winid) then
    api.nvim_win_close(self.help_winid, true)
  end
  if self.help_bufnr and vim.api.nvim_buf_is_valid(self.help_bufnr) then
    vim.api.nvim_buf_delete(self.help_bufnr, {force=true})
  end
  if self.prev_help_bufnr and vim.api.nvim_buf_is_valid(self.prev_help_bufnr) then
    vim.api.nvim_buf_delete(self.prev_help_bufnr, {force=true})
  end
  self.help_winid = nil
  self.help_bufnr = nil
  self.prev_help_bufnr = nil
end

-- inherit from help_tags for the specialized
-- 'gen_winopts()' without ':set  number'
Previewer.man_pages = Previewer.help_tags:extend()

function Previewer.man_pages:new(o, opts, fzf_win)
  Previewer.man_pages.super.new(self, o, opts, fzf_win)
  self.filetype = "man"
  self.cmd = o.cmd or "man -c %s | col -bx"
  return self
end

function Previewer.man_pages:parse_entry(entry_str)
  return entry_str:match("[^[,( ]+")
  -- return require'fzf-lua.providers.manpages'.getmanpage(entry_str)
end

function Previewer.man_pages:populate_preview_buf(entry_str)
  local entry = self:parse_entry(entry_str)
  -- mark the buffer for unloading the next call
  self.preview_bufloaded = true
  local cmd = self.cmd:format(entry)
  if type(cmd) == 'string' then cmd = {"sh", "-c", cmd} end
  local output, _ = utils.io_systemlist(cmd)
  -- vim.api.nvim_buf_set_option(self.preview_bufnr, 'modifiable', true)
  vim.api.nvim_buf_set_lines(self.preview_bufnr, 0, -1, false, output)
  vim.api.nvim_buf_set_option(self.preview_bufnr, 'filetype', self.filetype)
  self.win:update_scrollbar()
end

Previewer.marks = Previewer.buffer_or_file:extend()

function Previewer.marks:new(o, opts, fzf_win)
  Previewer.marks.super.new(self, o, opts, fzf_win)
  return self
end

function Previewer.marks:parse_entry(entry_str)
  local bufnr = nil
  local mark, lnum, col, filepath = entry_str:match("(.)%s+(%d+)%s+(%d+)%s+(.*)")
  -- try to acquire position from sending buffer
  -- if this succeeds (line>0) the mark is inside
  local pos = vim.api.nvim_buf_get_mark(self.win.src_bufnr, mark)
  if pos and pos[1] > 0 and pos[1] == tonumber(lnum) then
    bufnr = self.win.src_bufnr
    filepath = api.nvim_buf_get_name(bufnr)
  end
  if filepath and #filepath>0 then
    local ok, res = pcall(vim.fn.expand, filepath)
    if not ok then filepath = ''
    else filepath = res end
    filepath = path.relative(filepath, vim.loop.cwd())
  end
  return {
    bufnr = bufnr,
    path = filepath,
    line = tonumber(lnum) or 1,
    col  = tonumber(col) or 1,
  }
end

Previewer.jumps = Previewer.buffer_or_file:extend()

function Previewer.jumps:new(o, opts, fzf_win)
  Previewer.jumps.super.new(self, o, opts, fzf_win)
  return self
end

function Previewer.jumps:parse_entry(entry_str)
  local bufnr = nil
  local _, lnum, col, filepath = entry_str:match("(%d+)%s+(%d+)%s+(%d+)%s+(.*)")
  if filepath and #filepath>0 and not vim.loop.fs_stat(filepath) then
    -- file is not accessible,
    -- text is a string from current buffer
    bufnr = self.win.src_bufnr
    filepath = vim.api.nvim_buf_get_name(self.win.src_bufnr)
  end
  return {
    bufnr = bufnr,
    path = filepath,
    line = tonumber(lnum) or 1,
    col  = tonumber(col)+1 or 1,
  }
end
Previewer.tags = Previewer.buffer_or_file:extend()

function Previewer.tags:new(o, opts, fzf_win)
  Previewer.tags.super.new(self, o, opts, fzf_win)
  return self
end

function Previewer.tags:parse_entry(entry_str)
  -- first parse as normal entry
  -- must use 'super.' and send self as 1st arg
  -- or the ':' syntactic suger will send super's
  -- self which doesn't have self.opts
  local entry = self.super.parse_entry(self, entry_str)
  entry.ctag = path.entry_to_ctag(entry_str)
  return entry
end

function Previewer.tags:set_cursor_hl(entry)
  -- pcall(vim.fn.clearmatches, self.win.preview_winid)
  api.nvim_win_call(self.win.preview_winid, function()
    -- start searching at line 1 in case we
    -- didn't reload the buffer (same file)
    api.nvim_win_set_cursor(0, {1, 0})
    fn.clearmatches()
    fn.search(entry.ctag, "W")
    if self.win.winopts.hl.search then
      fn.matchadd(self.win.winopts.hl.search, entry.ctag)
    end
    utils.zz()
  end)
end

return Previewer
