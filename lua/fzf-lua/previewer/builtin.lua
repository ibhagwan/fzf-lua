local path = require "fzf-lua.path"
local utils = require "fzf-lua.utils"
local previewer_base = require "fzf-lua.previewer".base
local raw_action = require("fzf.actions").raw_action

local api = vim.api
local fn = vim.fn
local cmd = vim.cmd

local Previewer = {}

-- signgleton instance used for our keymappings
local _self = nil

setmetatable(Previewer, {
  __call = function (cls, ...)
    return cls:new(...)
  end,
})

function Previewer:setup_keybinds()
  if not self.win or not self.win.fzf_bufnr then return end
  local keymap_tbl = {
    toggle_full   = { module = 'previewer.builtin', fnc = 'toggle_full()' },
    toggle_wrap   = { module = 'previewer.builtin', fnc = 'toggle_wrap()' },
    toggle_hide   = { module = 'previewer.builtin', fnc = 'toggle_hide()' },
    page_up       = { module = 'previewer.builtin', fnc = 'scroll(-1)' },
    page_down     = { module = 'previewer.builtin', fnc = 'scroll(1)' },
    page_reset    = { module = 'previewer.builtin', fnc = 'scroll(0)' },
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

function Previewer:new(o, opts, fzf_win)
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
  self.fullscreen = o.fullscreen
  self.syntax = o.syntax
  self.syntax_delay = o.syntax_delay
  self.hl_cursor = o.hl_cursor
  self.hl_range = o.hl_range
  self.keymap = o.keymap
  self.backups = {}
  _self = self
  return self
end

function Previewer:close()
  -- restore winopts backup for those that weren't restored
  -- (usually the last previewed loaded buffer)
  for bufnr, _ in pairs(self.backups) do
    self:restore_winopts(bufnr, self.win.preview_winid)
  end
  self:clear_preview_buf()
  self.backups = {}
  _self = nil
end

function Previewer:update_border(entry)
  if self.title then
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

function Previewer:gen_winopts()
  return {
    wrap            = self.wrap,
    number          = true,
    relativenumber  = false,
    cursorline      = true,
    cursorcolumn    = false,
    signcolumn      = 'no',
    foldenable      = false,
    foldmethod      = 'manual',
  }
end

function Previewer:backup_winopts(key, win)
  if not key then return end
  if not win or not api.nvim_win_is_valid(win) then return end
  self.backups[key] = {}
  for opt, _ in pairs(self:gen_winopts()) do
    self.backups[key][opt] = api.nvim_win_get_option(win, opt)
  end
end

function Previewer:restore_winopts(key, win)
  if not self.backups[key] then return end
  if not win or not api.nvim_win_is_valid(win) then return end
  for opt, v in pairs(self.backups[key]) do
    api.nvim_win_set_option(win, opt, v)
  end
  self.backups[key] = nil
end

function Previewer:set_winopts(win)
  if not win or not api.nvim_win_is_valid(win) then return end
  for opt, v in pairs(self:gen_winopts()) do
    api.nvim_win_set_option(win, opt, v)
    --[[ api.nvim_win_call(win, function()
      api.nvim_win_set_option(0, opt, v)
    end) ]]
  end
end

local function set_cursor_hl(self, entry)
    local lnum, col = tonumber(entry.line), tonumber(entry.col)
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

    cmd(('noa call nvim_set_current_win(%d)'):format(self.win.preview_winid))
end

function Previewer:do_syntax(entry)
  if not self.preview_bufnr then return end
  local bufnr = self.preview_bufnr
  local preview_winid = self.win.preview_winid
  if self.preview_bufloaded and vim.bo[bufnr].filetype == '' then
    if fn.bufwinid(bufnr) == preview_winid then
      -- do not enable for lage files, treesitter still has perf issues:
      -- https://github.com/nvim-treesitter/nvim-treesitter/issues/556
      -- https://github.com/nvim-treesitter/nvim-treesitter/issues/898
      local lcount = api.nvim_buf_line_count(bufnr)
      local bytes = api.nvim_buf_get_offset(bufnr, lcount)
      if bytes / lcount < 1000 then
        -- nvim_buf_call is less side-effects than changing window
        -- make sure that buffer in preview window must not in normal window
        -- greedy match anything after last dot
        local ext = entry.path:match("[^.]*$")
        if ext then
          pcall(api.nvim_buf_set_option, bufnr, 'filetype', ext)
        end
        api.nvim_buf_call(bufnr, function()
          vim.cmd('filetype detect')
        end)
      end
    end
  end
end

function Previewer:set_tmp_buffer()
  if not self.win or not self.win:validate_preview() then return end
  local tmp_buf = api.nvim_create_buf(false, true)
  api.nvim_buf_set_option(tmp_buf, 'bufhidden', 'wipe')
  api.nvim_win_set_buf(self.win.preview_winid, tmp_buf)
  return tmp_buf
end

function Previewer:clear_preview_buf()
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

function Previewer:display_last_entry()
  self:display_entry(self.last_entry)
end

function Previewer:preview_buf_post(entry)
  -- backup window options
  local bufnr = self.preview_bufnr
  local preview_winid = self.win.preview_winid
  self:backup_winopts(bufnr, preview_winid)

  -- set preview win options or load the file
  -- if not already loaded from buffer
  utils.win_execute(preview_winid, function()
    set_cursor_hl(self, entry)
  end)

  -- set preview window options
  self:set_winopts(preview_winid)

  -- reset the preview window highlights
  self.win:reset_win_highlights(preview_winid)

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

function Previewer:display_entry(entry)
  if not entry then return
  else
    -- save last entry even if we don't display
    self.last_entry = entry
  end
  if not self.win or not self.win:validate_preview() then return end
  local preview_winid = self.win.preview_winid
  local previous_bufnr = api.nvim_win_get_buf(preview_winid)
  assert(not self.preview_bufnr or previous_bufnr == self.preview_bufnr)
  -- restore settings for the buffer we were previously viewing
  self:restore_winopts(previous_bufnr, preview_winid)
  -- clear the current preview buffer
  local bufnr = self:clear_preview_buf()
  -- store the preview buffer
  self.preview_bufnr = bufnr

  if entry.bufnr and api.nvim_buf_is_loaded(entry.bufnr) then
    -- must convert to number or our backup will have conflicting keys
    bufnr = tonumber(entry.bufnr)
    -- display the buffer in the preview
    api.nvim_win_set_buf(preview_winid, bufnr)
    -- store current preview buffer
    self.preview_bufnr = bufnr
    self:preview_buf_post(entry)
  else
    -- mark the buffer for unloading the next call
    self.preview_bufloaded = true
    -- read the file into the buffer
    utils.read_file_async(entry.path, vim.schedule_wrap(function(data)
      if not vim.api.nvim_buf_is_valid(bufnr) then
        return
      end
      local ok = pcall(vim.api.nvim_buf_set_lines, bufnr, 0, -1, false, vim.split(data, "[\r]?\n"))
      if not ok then
        return
      end
      self:preview_buf_post(entry)
    end))
  end

end

function Previewer:action(_)
  local act = raw_action(function (items, _, _)
    local entry = path.entry_to_file(items[1], self.opts.cwd)
    self:display_entry(entry)
    return ""
  end)
  return act
end

function Previewer:cmdline(_)
  return vim.fn.shellescape(self:action())
  -- return 'true'
end

function Previewer:preview_window(_)
  return 'nohidden:right:0'
end

function Previewer:override_fzf_preview_window()
  return self.win and not self.win.winopts.split
end

function Previewer.scroll(direction)
  if not _self then return end
  local self = _self
  local preview_winid = self.win.preview_winid
  if preview_winid < 0 or not direction then
    return
  end
  local fzf_winid = self.win.fzf_winid
  utils.win_execute(preview_winid, function()
    if direction == 0 then
      api.nvim_win_set_cursor(preview_winid, self.orig_pos)
    else
      -- ^D = 0x04, ^U = 0x15
      fn.execute(('norm! %c'):format(direction > 0 and 0x04 or 0x15))
    end
    utils.zz()
    cmd(('noa call nvim_set_current_win(%d)'):format(fzf_winid))
  end)
  if self.scrollbar then
    self.win:update_scrollbar()
  end
end

function Previewer.toggle_wrap()
  if not _self then return end
  local self = _self
  self.wrap = not self.wrap
  if self.win and self.win:validate_preview() then
    api.nvim_win_set_option(self.win.preview_winid, 'wrap', self.wrap)
  end
end

function Previewer.toggle_full()
  if not _self then return end
  local self = _self
  self.fullscreen = not self.fullscreen
  if self.win and self.win:validate_preview() then
    self.win:redraw_preview()
  end
end

function Previewer.toggle_hide()
  if not _self then return end
  local self = _self
  if self.win then
    if self.win:validate_preview() then
      self.win:close_preview()
    else
      self.win:redraw_preview()
      self:display_last_entry()
    end
  end
  -- close_preview() calls Previewer:close()
  -- which will clear out our singleton so
  -- we must save it again to call redraw
  _self = self
end

return Previewer
