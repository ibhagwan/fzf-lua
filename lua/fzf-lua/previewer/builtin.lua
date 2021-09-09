local path = require "fzf-lua.path"
local utils = require "fzf-lua.utils"
local previewer_base = require "fzf-lua.previewer"
local raw_action = require("fzf.actions").raw_action

local api = vim.api
local fn = vim.fn

local Previewer = {}
Previewer.base = {}
Previewer.buffer_or_file = {}
Previewer.help_tags = {}
Previewer.man_pages = {}

-- signgleton instance used for our keymappings
local _self = nil

-- Constructors call on Previewer.base.<o>()
for c, _ in pairs(Previewer) do
  setmetatable(Previewer[c], {
    __call = function (cls, ...)
      return cls:new(...)
    end,
  })
end

function Previewer.base:setup_keybinds()
  if not self.win or not self.win.fzf_bufnr then return end
  local keymap_tbl = {
    toggle_full   = { module = 'previewer.builtin', fnc = 'base.toggle_full()' },
    toggle_wrap   = { module = 'previewer.builtin', fnc = 'base.toggle_wrap()' },
    toggle_hide   = { module = 'previewer.builtin', fnc = 'base.toggle_hide()' },
    page_up       = { module = 'previewer.builtin', fnc = 'base.scroll(-1)' },
    page_down     = { module = 'previewer.builtin', fnc = 'base.scroll(1)' },
    page_reset    = { module = 'previewer.builtin', fnc = 'base.scroll(0)' },
  }
  local function funcref_str(keymap)
    return ([[<Cmd>lua require('fzf-lua.%s').%s<CR>]]):format(keymap.module, keymap.fnc)
  end
  for action, key in pairs(self.keymap) do
    local keymap = keymap_tbl[action]
    if keymap and not vim.tbl_isempty(keymap) and key ~= false then
      api.nvim_buf_set_keymap(self.win.fzf_bufnr, 't', key,
        funcref_str(keymap), {nowait = true, noremap = true})
    end
  end
end

function Previewer.base:new(o, opts, fzf_win)
  self = setmetatable(previewer_base(o, opts), {
    __index = vim.tbl_deep_extend("keep",
      self, previewer_base
    )})
  self.type = "builtin"
  self.win = fzf_win
  self.wrap = o.wrap
  self.title = o.title
  self.scrollbar = o.scrollbar
  if o.scrollchar then
    self.win.winopts.scrollchar = o.scrollchar
  end
  self.expand = o.expand or o.fullscreen
  self.hidden = o.hidden
  self.syntax = o.syntax
  self.syntax_delay = o.syntax_delay
  self.syntax_limit_b = o.syntax_limit_b
  self.syntax_limit_l = o.syntax_limit_l
  self.hl_cursor = o.hl_cursor
  self.hl_cursorline = o.hl_cursorline
  self.hl_range = o.hl_range
  self.keymap = o.keymap
  self.backups = {}
  _self = self
  return self
end

function Previewer.base:close()
  self:restore_winopts(self.win.preview_winid)
  self:clear_preview_buf()
  self.backups = {}
  _self = nil
end

function Previewer.base:gen_winopts()
  return {
    wrap            = self.wrap,
    number          = true,
    relativenumber  = false,
    cursorline      = true,
    cursorlineopt   = 'both',
    cursorcolumn    = false,
    signcolumn      = 'no',
    list            = false,
    foldenable      = false,
    foldmethod      = 'manual',
  }
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
  self.preview_bufloaded = nil
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
  self.preview_bufnr = self:clear_preview_buf()

  -- specialized previewer populate function
  self:populate_preview_buf(entry_str)

  -- set preview window options
  if not utils.is_term_buffer(self.preview_bufnr) then
    self:set_winopts(self.win.preview_winid)
  end

  -- reset the preview window highlights
  self.win:reset_win_highlights(self.win.preview_winid)
end

function Previewer.base:action(_)
  local act = raw_action(function (items, _, _)
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

function Previewer.base.scroll(direction)
  if not _self then return end
  local self = _self
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
    if utils.is_term_buffer(self.preview_bufnr) then
      -- can't use ":norm!" with terminal buffers due to:
      -- 'Vim(normal):Can't re-enter normal mode from terminal mode'
      -- TODO: this is hacky and disgusting figure
      -- out why it's failing or at the very least
      -- hide the typed command from the user
      local input = direction > 0 and "<C-d>" or "<C-u>"
      utils.feed_keys_termcodes(('<C-\\><C-n>:noa lua vim.api.nvim_win_call(' ..
        '%d, function() vim.cmd("norm! <C-v>%s") end)<CR>i'):
        format(tonumber(preview_winid), input))
      --[[ local input = ('%c'):format(utils._if(direction>0, 0x04, 0x15))
      vim.cmd(('noa lua vim.api.nvim_win_call(' ..
        '%d, function() vim.cmd("norm! %s") end)'):
        format(tonumber(preview_winid), input)) ]]
    else
      -- local input = direction > 0 and [[]] or [[]]
      -- local input = direction > 0 and [[]] or [[]]
      -- ^D = 0x04, ^U = 0x15 ('g8' on char to display)
      local input = ('%c'):format(utils._if(direction>0, 0x04, 0x15))
      vim.api.nvim_win_call(preview_winid, function()
        vim.cmd([[norm! ]] .. input)
        utils.zz()
      end)
    end
  end
  if self.scrollbar then
    self.win:update_scrollbar()
  end
end

function Previewer.base.toggle_wrap()
  if not _self then return end
  local self = _self
  self.wrap = not self.wrap
  if self.win and self.win:validate_preview() then
    api.nvim_win_set_option(self.win.preview_winid, 'wrap', self.wrap)
  end
end

function Previewer.base.toggle_full()
  if not _self then return end
  local self = _self
  self.expand = not self.expand
  if self.win and self.win:validate_preview() then
    self.win:redraw_preview()
  end
end

function Previewer.base.toggle_hide()
  if not _self then return end
  local self = _self
  self.hidden = not self.hidden
  if self.win then
    if self.win:validate_preview() then
      self.win:close_preview()
      self.win:redraw()
    else
      self.win:redraw()
      self.win:redraw_preview()
      self:display_last_entry()
    end
  end
  -- close_preview() calls Previewer.base:close()
  -- which will clear out our singleton so
  -- we must save it again to call redraw
  _self = self
end

function Previewer.buffer_or_file:new(o, opts, fzf_win)
  self = setmetatable(Previewer.base(o, opts, fzf_win), {
    __index = vim.tbl_deep_extend("keep",
      self, Previewer.base
    )})
  return self
end

function Previewer.buffer_or_file:populate_preview_buf(entry_str)
  local entry = path.entry_to_file(entry_str, self.opts.cwd)
  if entry.bufnr and api.nvim_buf_is_loaded(entry.bufnr) then
    -- must convert to number or our backup will have conflicting keys
    local bufnr = tonumber(entry.bufnr)
    -- display the buffer in the preview
    api.nvim_win_set_buf(self.win.preview_winid, bufnr)
    -- store current preview buffer
    self.preview_bufnr = bufnr
    self:preview_buf_post(entry)
  else
    -- mark the buffer for unloading the next call
    self.preview_bufloaded = true
    -- make sure the file is readable (or bad entry.path)
    if not vim.loop.fs_stat(entry.path) then return end
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
  if not entry then return end
  if not self.preview_bufnr then return end
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
        -- prepend the buffer number to the path and
        -- set as buffer name, this makes sure 'filetype detect'
        -- gets the right filetype which enables the syntax
        local tempname = path.join({tostring(bufnr), entry.path})
        pcall(api.nvim_buf_set_name, bufnr, tempname)
        -- nvim_buf_call has less side-effects than window switch
        api.nvim_buf_call(bufnr, function()
          vim.cmd('filetype detect')
        end)
      end
    end
  end
end

local function set_cursor_hl(self, entry)
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

    if lnum and lnum > 0 and col and col > 1 then
      fn.matchaddpos(self.hl_cursor, {{lnum, math.max(1, col)}}, 11)
    end
end

function Previewer.buffer_or_file:update_border(entry)
  if self.title then
    if self.opts.cwd then
      entry.path = path.relative(entry.path, self.opts.cwd)
    end
    local title = (' %s '):format(entry.path)
    if entry.bufnr then
      -- local border_width = api.nvim_win_get_width(self.win.preview_winid)
      local buf_str = ('buf %d:'):format(entry.bufnr)
      title = (' %s %s '):format(buf_str, entry.path)
    end
    self.win:update_title(title)
  end
  if self.scrollbar then
    self.win:update_scrollbar()
  end
end

function Previewer.buffer_or_file:preview_buf_post(entry)
  -- set preview win options or load the file
  -- if not already loaded from buffer
  vim.api.nvim_win_call(self.win.preview_winid, function()
    set_cursor_hl(self, entry)
  end)

  -- local ml = vim.bo[entry.bufnr].ml
  -- vim.bo[entry.bufnr].ml = false

  if self.syntax then
    vim.defer_fn(function()
      self:do_syntax(entry)
      -- vim.bo[entry.bufnr].ml = ml
    end, self.syntax_delay)
  end

  self:update_border(entry)
end


function Previewer.help_tags:new(o, opts, fzf_win)
  self = setmetatable(Previewer.base(o, opts, fzf_win), {
    __index = vim.tbl_deep_extend("keep",
      self, Previewer.base
    )})
  self.split = o.split
  self.help_cmd = o.help_cmd or "help"
  self:init_help_win()
  return self
end

function Previewer.help_tags:gen_winopts()
  return {
    wrap            = self.wrap,
    number          = false,
    relativenumber  = false,
    cursorline      = true,
    cursorlineopt   = 'both',
    cursorcolumn    = false,
    signcolumn      = 'no',
    list            = false,
    foldenable      = false,
    foldmethod      = 'manual',
  }
end

function Previewer.help_tags:exec_cmd(str)
  str = str or ''
  vim.cmd(("%s %s %s"):format(self.split, self.help_cmd, str))
end

function Previewer.help_tags:parse_entry(entry_str)
  return entry_str
end

function Previewer.help_tags:init_help_win(str)
  if not self.split or
    (self.split ~= "topleft" and self.split ~= "botright") then
    self.split = "botright"
  end
  local orig_winid = api.nvim_get_current_win()
  self:exec_cmd(str)
  self.help_bufnr = api.nvim_get_current_buf()
  self.help_winid = api.nvim_get_current_win()
  pcall(vim.api.nvim_win_set_height, 0, 0)
  pcall(vim.api.nvim_win_set_width, 0, 0)
  api.nvim_set_current_win(orig_winid)
end

function Previewer.help_tags:populate_preview_buf(entry_str)
  local entry = self:parse_entry(entry_str)
  vim.api.nvim_win_call(self.help_winid, function()
    self.prev_help_bufnr = api.nvim_get_current_buf()
    self:exec_cmd(entry)
    self.preview_bufnr = api.nvim_get_current_buf()
    self.orig_pos = api.nvim_win_get_cursor(0)
  end)
  api.nvim_win_set_buf(self.win.preview_winid, self.preview_bufnr)
  api.nvim_win_set_cursor(self.win.preview_winid, self.orig_pos)
  if self.scrollbar then
    self.win:update_scrollbar()
  end
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
  if vim.api.nvim_win_is_valid(self.help_winid) then
    api.nvim_win_close(self.help_winid, true)
  end
  if vim.api.nvim_buf_is_valid(self.help_bufnr) then
    vim.api.nvim_buf_delete(self.help_bufnr, {force=true})
  end
  if vim.api.nvim_buf_is_valid(self.prev_help_bufnr) then
    vim.api.nvim_buf_delete(self.prev_help_bufnr, {force=true})
  end
  self.help_winid = nil
  self.help_bufnr = nil
  self.prev_help_bufnr = nil
end

-- inherit from help_tags
function Previewer.man_pages:new(o, opts, fzf_win)
  self = setmetatable(Previewer.base(o, opts, fzf_win), {
    __index = vim.tbl_deep_extend("keep",
      self, Previewer.help_tags, Previewer.base
    )})
  self.split = o.split
  self.help_cmd = o.help_cmd or "Man"
  self:init_help_win("echo")
  return self
end

function Previewer.man_pages:parse_entry(entry_str)
  return entry_str:match("[^[,( ]+")
  -- return require'fzf-lua.providers.manpages'.getmanpage(entry_str)
end

return Previewer
