local path = require "fzf-lua.path"
local shell = require "fzf-lua.shell"
local utils = require "fzf-lua.utils"
local Object = require "fzf-lua.class"

local api = vim.api
local uv = vim.loop
local fn = vim.fn

-- is treesitter available?
local __has_ts, __ts_configs, __ts_parsers

local Previewer = {}

Previewer.base = Object:extend()

function Previewer.base:new(o, opts, fzf_win)
  local function default(var, def)
    if var ~= nil then
      return var
    else
      return def
    end
  end

  o = o or {}
  self.type = "builtin"
  self.opts = opts;
  self.win = fzf_win
  self.delay = self.win.winopts.preview.delay or 100
  self.title = self.win.winopts.preview.title
  self.title_align = self.win.winopts.preview.title_align
  self.winopts = self.win.winopts.preview.winopts
  self.syntax = default(o.syntax, true)
  self.syntax_delay = default(o.syntax_delay, 0)
  self.syntax_limit_b = default(o.syntax_limit_b, 1024 * 1024)
  self.syntax_limit_l = default(o.syntax_limit_l, 0)
  self.limit_b = default(o.limit_b, 1024 * 1024 * 10)
  self.treesitter = o.treesitter or {}
  self.toggle_behavior = o.toggle_behavior
  self.backups = {}
  -- convert extension map to lower case
  if o.extensions then
    self.extensions = {}
    for k, v in pairs(o.extensions) do
      self.extensions[k:lower()] = v
    end
  end
  -- validate the ueberzug image scaler
  local uz_scalers = {
    ["crop"]         = "crop",
    ["distort"]      = "distort",
    ["contain"]      = "contain",
    ["fit_contain"]  = "fit_contain",
    ["cover"]        = "cover",
    ["forced_cover"] = "forced_cover",
  }
  self.ueberzug_scaler = o.ueberzug_scaler and uz_scalers[o.ueberzug_scaler]
  if o.ueberzug_scaler and not self.ueberzug_scaler then
    utils.warn(("Invalid ueberzug image scaler '%s', option will be omitted.")
      :format(o.ueberzug_scaler))
  end
  -- cached buffers
  self.cached_buffers = {}
  -- store currently listed buffers, this helps us determine which buffers
  -- navigaged with 'vim.lsp.util.jump_to_location' we can safely unload
  -- since jump_to_location reuses buffers and I couldn't find a better way
  -- to determine if the destination buffer was listed prior to the jump
  self.listed_buffers = (function()
    local map = {}
    vim.tbl_map(function(b)
      if vim.fn.buflisted(b) == 1 then
        -- Save key as string or this gets treated as an array
        map[tostring(b)] = true
      end
    end, vim.api.nvim_list_bufs())
    return map
  end)()
  return self
end

function Previewer.base:close()
  self:restore_winopts(self.win.preview_winid)
  self:clear_preview_buf()
  self:clear_cached_buffers()
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
    -- PROBABLY DOESN'T MATTER (WHO USES 0.5?) BUT WHY NOT LOL
    -- minor backward compatibility fix, with neovim version < 0.7
    -- nvim_win_get_option("scroloff") which should return -1
    -- returns an invalid (really big number insead which panics
    -- when called with nvim_win_set_option, wrapping in a pcall
    -- ensures this plugin still works for neovim version as low as 0.5!
    pcall(vim.api.nvim_win_set_option, win, opt, value)
  end
end

function Previewer.base:set_winopts(win)
  if self.do_not_set_winopts then return end
  if not win or not api.nvim_win_is_valid(win) then return end
  for opt, v in pairs(self:gen_winopts()) do
    if utils.nvim_has_option(opt) then
      api.nvim_win_set_option(win, opt, v)
    end
  end
end

function Previewer.base:preview_is_terminal()
  if not self.win or not self.win:validate_preview() then return end
  return vim.fn.getwininfo(self.win.preview_winid)[1].terminal == 1
end

function Previewer.base:get_tmp_buffer()
  local tmp_buf = api.nvim_create_buf(false, true)
  api.nvim_buf_set_option(tmp_buf, "bufhidden", "wipe")
  return tmp_buf
end

function Previewer.base:set_preview_buf(newbuf)
  if not self.win or not self.win:validate_preview() then return end
  -- Set the preview window to the new buffer
  utils.win_set_buf_noautocmd(self.win.preview_winid, newbuf)
  self.preview_bufnr = newbuf
  -- set preview window options
  self:set_winopts(self.win.preview_winid)
end

local function force_delete_buffer(bufnr)
  if tonumber(bufnr) and vim.api.nvim_buf_is_valid(bufnr) then
    api.nvim_buf_call(bufnr, function()
      vim.cmd([[delm \"]])
    end)
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end
end

function Previewer.base:cache_buffer(bufnr, key, do_not_unload)
  if not key then return end
  if not bufnr then
    -- can happen with slow loading buffers such as image previews
    -- with viu while spamming f5/f6 to rotate the preview window
    return
  end
  local cached = self.cached_buffers[key]
  if cached then
    if cached.bufnr == bufnr then
      -- already cached, nothing to do
      return
    else
      -- new cached buffer for key
      -- wipe current cached buf
      if not cached.do_not_unload then
        force_delete_buffer(cached.bufnr)
      end
    end
  end
  self.cached_buffers[key] = {
    bufnr = bufnr,
    do_not_unload = do_not_unload,
  }
  -- remove buffer auto-delete since it's now cached
  api.nvim_buf_set_option(bufnr, "bufhidden", "hide")
end

function Previewer.base:clear_cached_buffers()
  -- clear the buffer cache
  for _, c in pairs(self.cached_buffers) do
    if not c.do_not_unload then
      force_delete_buffer(c.bufnr)
    end
  end
  self.cached_buffers = {}
end

function Previewer.base:clear_preview_buf(newbuf)
  local retbuf = nil
  if ((self.win and self.win._reuse) or newbuf)
      -- Attach a temp buffer to the window when reusing (`ctrl-g`)
      -- so we don't invalidate the window when deting the buffer
      -- in `force_delete_buffer` call below
      -- We don't use 'self.win:validate_preview()' because we want
      -- to detach the buffer even when 'self.win.closing = true'
      and self.win and self.win.preview_winid
      and tonumber(self.win.preview_winid) > 0
      and api.nvim_win_is_valid(self.win.preview_winid) then
    -- attach a temp buffer to the window
    -- so we can safely delete the buffer
    -- ('nvim_buf_delete' removes the attached win)
    retbuf = self:get_tmp_buffer()
    utils.win_set_buf_noautocmd(self.win.preview_winid, retbuf)
  end
  -- since our temp buffers have 'bufhidden=wipe' the tmp
  -- buffer will be automatically wiped and 'nvim_buf_is_valid'
  -- will return false
  -- one case where the buffer may remain valid after detaching
  -- from the preview window is with URI type entries after calling
  -- 'vim.lsp.util.jump_to_location' which can reuse existing buffers,
  -- so technically this should never be executed unless the
  -- user wrote an fzf-lua extension and set the preview buffer to
  -- a random buffer without the 'bufhidden' property
  if not self.do_not_unload then
    force_delete_buffer(self.preview_bufnr)
  end
  self.preview_bufnr = nil
  self.loaded_entry = nil
  return retbuf
end

function Previewer.base:display_last_entry()
  self:display_entry(self.last_entry)
end

function Previewer.base:display_entry(entry_str)
  if not entry_str then
    return
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

  -- clears the current preview buffer and set to a new temp buffer
  -- recommended to return false from 'should_clear_preview' and use
  -- 'self:set_preview_buf()' instead for flicker-free experience
  if self.should_clear_preview and self:should_clear_preview(entry_str) then
    self.preview_bufnr = self:clear_preview_buf(true)
  end

  local populate_preview_buf = function(entry_str_)
    if not self.win or not self.win:validate_preview() then return end

    -- specialized previewer populate function
    self:populate_preview_buf(entry_str_)

    -- set preview window options
    if not self.do_not_set_winopts then
      self:set_winopts(self.win.preview_winid)
    else
      -- removes 'number', 'signcolumn', 'cursorline', etc
      -- call after 'set_preview_buf' or 'cursorline' becomes true
      self.win:set_style_minimal(self.win.preview_winid)
    end

    -- reset the preview window highlights
    self.win:reset_win_highlights(self.win.preview_winid)
  end

  -- debounce preview entries
  if tonumber(self.delay) > 0 then
    if not self._entry_count then
      self._entry_count = 1
    else
      self._entry_count = self._entry_count + 1
    end
    local entry_count = self._entry_count
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

function Previewer.base:cmdline(_)
  local act = shell.raw_action(function(items, _, _)
    self:display_entry(items[1])
    return ""
  end, "{}", self.opts.debug)
  return act
end

function Previewer.base:preview_window(_)
  if self.win and not self.win.winopts.split then
    return "nohidden:right:0"
  else
    return nil
  end
end

function Previewer.base:scroll(direction)
  local preview_winid = self.win.preview_winid
  if preview_winid < 0 or not direction then return end
  if not api.nvim_win_is_valid(preview_winid) then return end

  if direction == 0 then
    pcall(vim.api.nvim_win_call, preview_winid, function()
      -- for some reason 'nvim_win_set_cursor'
      -- only moves forward, so set to (1,0) first
      api.nvim_win_set_cursor(0, { 1, 0 })
      if self.orig_pos then
        api.nvim_win_set_cursor(0, self.orig_pos)
      end
      utils.zz()
    end)
  elseif not self:preview_is_terminal() then
    -- local input = direction > 0 and [[]] or [[]]
    -- local input = direction > 0 and [[]] or [[]]
    -- ^D = 0x04, ^U = 0x15 ('g8' on char to display)
    local input = ("%c"):format(utils._if(direction > 0, 0x04, 0x15))
    pcall(vim.api.nvim_win_call, preview_winid, function()
      vim.cmd([[norm! ]] .. input)
      utils.zz()
    end)
  else
    -- we get here when using custom term commands using
    -- the extensions map (i.e. view term images with 'vui')
    -- we can't use ":norm!" with terminal buffers due to:
    -- 'Vim(normal):Can't re-enter normal mode from terminal mode'
    -- https://github.com/neovim/neovim/issues/4895#issuecomment-303073838
    -- according to the above comment feedkeys is the correct workaround
    -- TODO: hide the typed command from the user (possible?)
    local input = direction > 0 and "<C-d>" or "<C-u>"
    vim.cmd("stopinsert")
    utils.feed_keys_termcodes((":noa lua vim.api.nvim_win_call(" ..
      [[%d, function() vim.cmd("norm! <C-v>%s") vim.cmd("startinsert") end)<CR>]]):
      format(tonumber(preview_winid), input))
  end
  -- 'cursorline' is effectively our match highlight. Once the
  -- user scrolls, the highlight is no longer relevant (#462).
  -- Conditionally toggle 'cursorline' based on cursor position
  if self.orig_pos and self.winopts.cursorline then
    local wininfo = vim.fn.getwininfo(preview_winid)
    if wininfo and wininfo[1] and
        self.orig_pos[1] >= wininfo[1].topline and
        self.orig_pos[1] <= wininfo[1].botline then
      -- reset cursor pos even when it's already there, no bigggie
      -- local curpos = vim.api.nvim_win_get_cursor(preview_winid)
      vim.api.nvim_win_set_cursor(preview_winid, self.orig_pos)
      vim.api.nvim_win_set_option(preview_winid, "cursorline", true)
    else
      vim.api.nvim_win_set_option(preview_winid, "cursorline", false)
    end
  end
  self.win:update_scrollbar()
end

Previewer.buffer_or_file = Previewer.base:extend()

function Previewer.buffer_or_file:new(o, opts, fzf_win)
  Previewer.buffer_or_file.super.new(self, o, opts, fzf_win)
  return self
end

function Previewer.buffer_or_file:close()
  self:restore_winopts(self.win.preview_winid)
  self:clear_preview_buf()
  self:clear_cached_buffers()
  self:stop_ueberzug()
  self.backups = {}
end

function Previewer.buffer_or_file:parse_entry(entry_str)
  local entry = path.entry_to_file(entry_str, self.opts)
  return entry
end

function Previewer.buffer_or_file:should_clear_preview(_)
  return false
end

function Previewer.buffer_or_file:should_load_buffer(entry)
  -- we don't have a previous entry to compare to
  -- return 'true' so the buffer will be loaded in
  -- ::populate_preview_buf
  if not self.loaded_entry then return true end
  if type(entry) == "string" then
    entry = self:parse_entry(entry)
  end
  if (entry.bufnr and entry.bufnr == self.loaded_entry.bufnr) or
      (not entry.bufnr and entry.path and entry.path == self.loaded_entry.path) then
    return false
  end
  return true
end

function Previewer.buffer_or_file:start_ueberzug()
  if self._ueberzug_fifo then return self._ueberzug_fifo end
  local fifo = ("fzf-lua-%d-ueberzug"):format(vim.fn.getpid())
  self._ueberzug_fifo = vim.fn.systemlist({ "mktemp", "--dry-run", "--suffix", fifo })[1]
  vim.fn.system({ "mkfifo", self._ueberzug_fifo })
  self._ueberzug_job = vim.fn.jobstart({ "sh", "-c",
    ("tail --follow %s | ueberzug layer --parser json")
        :format(vim.fn.shellescape(self._ueberzug_fifo))
  }, {
    on_exit = function(_, rc, _)
      if rc ~= 0 and rc ~= 143 then
        utils.warn(("ueberzug exited with error %d"):format(rc) ..
          ", run ':messages' to see the detailed error.")
      end
    end,
    on_stderr = function(_, data, _)
      for _, l in ipairs(data or {}) do
        if #l > 0 then
          utils.info(l)
        end
      end
      -- populate the preview buffer with the error message
      if self.preview_bufnr and self.preview_bufnr > 0 and
          vim.api.nvim_buf_is_valid(self.preview_bufnr) then
        local lines = vim.api.nvim_buf_get_lines(self.preview_bufnr, 0, -1, false)
        for _, l in ipairs(data or {}) do
          table.insert(lines, l)
        end
        vim.api.nvim_buf_set_lines(self.preview_bufnr, 0, -1, false, lines)
      end
    end
  }
  )
  self._ueberzug_pid = vim.fn.jobpid(self._ueberzug_job)
  return self._ueberzug_fifo
end

function Previewer.buffer_or_file:stop_ueberzug()
  if self._ueberzug_job then
    vim.fn.jobstop(self._ueberzug_job)
    if type(uv.os_getpriority(self._ueberzug_pid)) == "number" then
      uv.kill(self._ueberzug_pid, 9)
    end
    self._ueberzug_job = nil
    self._ueberzug_pid = nil
  end
  if self._ueberzug_fifo and uv.fs_stat(self._ueberzug_fifo) then
    vim.fn.delete(self._ueberzug_fifo)
    self._ueberzug_fifo = nil
  end
end

function Previewer.buffer_or_file:populate_terminal_cmd(tmpbuf, cmd, entry)
  if not cmd then return end
  cmd = type(cmd) == "table" and utils.deepcopy(cmd) or { cmd }
  if not cmd[1] or vim.fn.executable(cmd[1]) ~= 1 then
    return false
  end
  -- set this to prevent calling 'set_winopts'
  -- preview buf must be attached beforehand
  -- for terminal image previews to have the
  -- correct size
  self.loaded_entry = nil
  self.do_not_cache = true
  self.do_not_set_winopts = true
  -- both ueberzug and terminal cmds need a clear
  -- on redraw to fit the new window dimentions
  self.clear_on_redraw = true
  self:set_preview_buf(tmpbuf)
  if cmd[1]:match("ueberzug") then
    local fifo = self:start_ueberzug()
    if not fifo then return end
    local wincfg = vim.api.nvim_win_get_config(self.win.preview_winid)
    local winpos = vim.api.nvim_win_get_position(self.win.preview_winid)
    local params = {
      action     = "add",
      identifier = "preview",
      x          = winpos[2],
      y          = winpos[1],
      width      = wincfg.width,
      height     = wincfg.height,
      scaler     = self.ueberzug_scaler,
      path       = path.starts_with_separator(entry.path) and entry.path or
          path.join({ self.opts.cwd or uv.cwd(), entry.path }),
    }
    local json = vim.json.encode(params)
    -- both 'fs_open|write|close' and 'vim.fn.system' work.
    -- We prefer the libuv method as it doesn't rely on the shell
    -- cmd = { "sh", "-c", ("echo '%s' > %s"):format(json, self._ueberzug_fifo) }
    -- vim.fn.system(cmd)
    local fd = uv.fs_open(self._ueberzug_fifo, "a", -1)
    if fd then
      uv.fs_write(fd, json .. "\n", nil, function(_)
        uv.fs_close(fd)
      end)
    end
  else
    -- add filename as last parameter
    table.insert(cmd, entry.path)
    -- must be modifiable or 'termopen' fails
    vim.bo[tmpbuf].modifiable = true
    vim.api.nvim_buf_call(tmpbuf, function()
      self._job_id = vim.fn.termopen(cmd, {
        cwd = self.opts.cwd,
        on_exit = function()
          -- run post only after terminal job finished
          if self._job_id then
            self:preview_buf_post(entry)
            self._job_id = nil
          end
        end
      })
    end)
  end
  -- run here so title gets updated
  -- even if the image is still loading
  self:preview_buf_post(entry)
  return true
end

function Previewer.buffer_or_file:populate_from_cache(entry)
  local key = entry and (entry.path or entry.uri)
  local cached = self.cached_buffers[key]
  if cached and vim.api.nvim_buf_is_valid(cached.bufnr) then
    self:set_preview_buf(cached.bufnr)
    self:preview_buf_post(entry)
    return true
  end
  return false
end

function Previewer.buffer_or_file:populate_preview_buf(entry_str)
  if not self.win or not self.win:validate_preview() then return end
  local entry = self:parse_entry(entry_str)
  if vim.tbl_isempty(entry) then return end
  if not self:should_load_buffer(entry) then
    -- same file/buffer as previous entry
    -- no need to reload content
    -- call post to set cursor location
    self:preview_buf_post(entry)
    return
  end
  -- stop ueberzug shell job
  self:stop_ueberzug()
  -- kill previously running terminal jobs
  -- when using external commands extension map
  if self._job_id and self._job_id > 0 then
    vim.fn.jobstop(self._job_id)
    self._job_id = nil
  end
  -- mark terminal buffers so we don't call 'set_winopts'
  self.clear_on_redraw = false
  self.do_not_cache = false
  self.do_not_unload = false
  self.do_not_set_winopts = entry.terminal
  if self:populate_from_cache(entry) then
    -- already populated
    return
  elseif entry.bufnr and api.nvim_buf_is_loaded(entry.bufnr) then
    -- WE NO LONGER REUSE THE CURRENT BUFFER
    -- this changes the buffer's 'getbufinfo[1].lastused'
    -- which messes up our `buffers()` sort
    entry.filetype = vim.api.nvim_buf_get_option(entry.bufnr, "filetype")
    local lines = vim.api.nvim_buf_get_lines(entry.bufnr, 0, -1, false)
    local tmpbuf = self:get_tmp_buffer()
    vim.api.nvim_buf_set_lines(tmpbuf, 0, -1, false, lines)
    self:set_preview_buf(tmpbuf)
    self:preview_buf_post(entry)
  elseif entry.uri then
    -- LSP 'jdt://' entries, see issue #195
    -- https://github.com/ibhagwan/fzf-lua/issues/195
    pcall(vim.api.nvim_win_call, self.win.preview_winid, function()
      vim.lsp.util.jump_to_location(entry, "utf-16", false)
      self.preview_bufnr = vim.api.nvim_get_current_buf()
      -- since 'jump_to_location' reuses existing buffers we have to
      -- make sure we aren't unloading an exisiting buffer (#609)
      -- NOTE: listed buffers map key must use 'tostring'
      if self.listed_buffers[tostring(self.preview_bufnr)] then
        self.do_not_unload = true
      end
    end)
    self:preview_buf_post(entry)
  else
    if entry.bufnr and vim.api.nvim_buf_is_valid(entry.bufnr) then
      -- buffer was unloaded, can happen when calling `lines`
      -- with `set nohidden`, fix entry.path since it contains
      -- filename only
      entry.path = path.relative(vim.api.nvim_buf_get_name(entry.bufnr), vim.loop.cwd())
    end
    assert(entry.path)
    -- check the buffer cache again since the first check
    -- may have missed it due to entry.path being nil
    if self:populate_from_cache(entry) then
      return
    end
    -- not found in cache, attempt to load
    local tmpbuf = self:get_tmp_buffer()
    if self.extensions and not vim.tbl_isempty(self.extensions) then
      local ext = path.extension(entry.path)
      local cmd = ext and self.extensions[ext:lower()]
      if cmd and self:populate_terminal_cmd(tmpbuf, cmd, entry) then
        -- will return 'false' when cmd isn't executable.
        -- If we get here it means preview was successful
        -- it can still fail if using wrong command flags
        -- but the user will be able to see the error in
        -- the preview win
        return
      end
    end
    do
      local lines = nil
      -- make sure the file is readable (or bad entry.path)
      local fs_stat = vim.loop.fs_stat(entry.path)
      if not entry.path or not fs_stat then
        lines = { string.format("Unable to stat file %s", entry.path) }
      elseif fs_stat.size > 0 and utils.perl_file_is_binary(entry.path) then
        lines = { "Preview is not supported for binary files." }
      elseif tonumber(self.limit_b) > 0 and fs_stat.size > self.limit_b then
        lines = {
          ("Preview file size limit (>%dMB) reached, file size %dMB.")
              :format(self.limit_b / (1024 * 1024), fs_stat.size / (1024 * 1024)),
          -- "(configured via 'previewers.builtin.limit_b')"
        }
      end
      if lines then
        vim.api.nvim_buf_set_lines(tmpbuf, 0, -1, false, lines)
        -- swap preview buffer with new one
        self:set_preview_buf(tmpbuf)
        self:preview_buf_post(entry)
        return
      end
    end
    -- read the file into the buffer
    utils.read_file_async(entry.path, vim.schedule_wrap(function(data)
      local lines = vim.split(data, "[\r]?\n")

      -- if file ends in new line, don't write an empty string as the last
      -- line.
      if data:sub(#data, #data) == "\n" or data:sub(#data - 1, #data) == "\r\n" then
        table.remove(lines)
      end
      vim.api.nvim_buf_set_lines(tmpbuf, 0, -1, false, lines)
      -- swap preview buffer with new one
      self:set_preview_buf(tmpbuf)
      self:preview_buf_post(entry)
    end))
  end
end

-- Attach ts highlighter
local ts_attach = function(bufnr, ft)
  if not __has_ts then
    __has_ts, _ = pcall(require, "nvim-treesitter")
    if __has_ts then
      _, __ts_configs = pcall(require, "nvim-treesitter.configs")
      _, __ts_parsers = pcall(require, "nvim-treesitter.parsers")
    end
  end

  if not __has_ts or not ft or ft == "" then
    return false
  end

  local lang = __ts_parsers.ft_to_lang(ft)
  if not __ts_configs.is_enabled("highlight", lang, bufnr) then
    return false
  end

  local config = __ts_configs.get_module "highlight"
  vim.treesitter.highlighter.new(__ts_parsers.get_parser(bufnr, lang))
  local is_table = type(config.additional_vim_regex_highlighting) == "table"
  if
      config.additional_vim_regex_highlighting
      and (not is_table or vim.tbl_contains(config.additional_vim_regex_highlighting, lang))
  then
    vim.api.nvim_buf_set_option(bufnr, "syntax", ft)
  end
  return true
end

function Previewer.buffer_or_file:do_syntax(entry)
  if not self.preview_bufnr then return end
  if not entry or not entry.path then return end
  local bufnr = self.preview_bufnr
  local preview_winid = self.win.preview_winid
  if api.nvim_buf_is_valid(bufnr) and vim.bo[bufnr].filetype == "" then
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
          utils._if(syntax_limit_reached == 1,
            ("%d lines"):format(lcount),
            ("%db"):format(bytes)),
          utils._if(syntax_limit_reached == 1, "syntax_limit_l", "syntax_limit_b"),
          utils._if(syntax_limit_reached == 1, self.syntax_limit_l, self.syntax_limit_b)
        ))
      end
      if syntax_limit_reached == 0 then
        -- 'vim.filetype' was added with v0.7 but panics with the below
        -- limit treesitter manual attachment to 0.8 instead (0.7.2 also errs)
        -- Error executing vim.schedule lua callback:
        --   vim/filetype.lua:0: attempt to call method 'gsub' (a nil value)
        local fallback = vim.fn.has("nvim-0.8") == 0
        if not fallback then
          fallback = (function()
            local ft = vim.filetype.match({ buf = bufnr, filename = entry.path })
            if type(ft) ~= "string" then
              return true
            end
            local ts_enabled = (function()
              if not self.treesitter or
                  self.treesitter.enable == false or
                  self.treesitter.disable == true or
                  (type(self.treesitter.enable) == "table" and
                  not vim.tbl_contains(self.treesitter.enable, ft)) or
                  (type(self.treesitter.disable) == "table" and
                  vim.tbl_contains(self.treesitter.disable, ft)) then
                return false
              end
              return true
            end)()
            local ts_success
            if ts_enabled then
              ts_success = ts_attach(bufnr, ft)
            end
            if not ts_enabled or not ts_success then
              pcall(vim.api.nvim_buf_set_option, bufnr, "syntax", ft)
            end
          end)()
        end
        if fallback then
          if entry.filetype == "help" then
            -- if entry.filetype and #entry.filetype>0 then
            -- filetype was saved from a loaded buffer
            -- this helps avoid losing highlights for help buffers
            -- which are '.txt' files with 'ft=help'
            -- api.nvim_buf_set_option(bufnr, 'filetype', entry.filetype)
            pcall(api.nvim_buf_set_option, bufnr, "filetype", entry.filetype)
          else
            -- prepend the buffer number to the path and
            -- set as buffer name, this makes sure 'filetype detect'
            -- gets the right filetype which enables the syntax
            local tempname = path.join({ tostring(bufnr), entry.path })
            pcall(api.nvim_buf_set_name, bufnr, tempname)
          end
          -- nvim_buf_call has less side-effects than window switch
          local ok, _ = pcall(api.nvim_buf_call, bufnr, function()
            vim.cmd("filetype detect")
          end)
          if not ok then
            utils.warn(("syntax highlighting failed for filetype '%s', ")
              :format(entry.path and path.extension(entry.path) or "<null>") ..
              "open the file and run ':filetype detect' for more info.")
          end
        end
      end
    end
  end
end

function Previewer.buffer_or_file:set_cursor_hl(entry)
  pcall(vim.api.nvim_win_call, self.win.preview_winid, function()
    local lnum, col = tonumber(entry.line), tonumber(entry.col)
    local pattern = entry.pattern or entry.text

    if not lnum or lnum < 1 then
      api.nvim_win_set_cursor(0, { 1, 0 })
      if pattern ~= "" then
        fn.search(pattern, "c")
      end
    else
      if not pcall(api.nvim_win_set_cursor, 0, { lnum, math.max(0, col - 1) }) then
        return
      end
    end

    utils.zz()

    self.orig_pos = api.nvim_win_get_cursor(0)

    fn.clearmatches()

    if self.win.winopts.__hl.cursor and not (lnum <= 1 and col <= 1) then
      fn.matchaddpos(self.win.winopts.__hl.cursor, { { lnum, math.max(1, col) } }, 11)
    end
  end)
end

function Previewer.buffer_or_file:update_border(entry)
  if self.title then
    local filepath = entry.path
    if filepath then
      if self.opts.cwd then
        filepath = path.relative(entry.path, self.opts.cwd)
      end
      filepath = path.HOME_to_tilde(filepath)
    end
    local title = (" %s "):format(filepath or entry.uri)
    if entry.bufnr then
      -- local border_width = api.nvim_win_get_width(self.win.preview_winid)
      local buf_str = ("buf %d:"):format(entry.bufnr)
      title = (" %s %s "):format(buf_str, entry.path)
    end
    self.win:update_title(title)
  end
  self.win:update_scrollbar()
end

function Previewer.buffer_or_file:preview_buf_post(entry)
  if not self.win or not self.win:validate_preview() then return end

  if not self:preview_is_terminal() then
    -- set cursor highlights for line|col or tag
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
  end

  self:update_border(entry)

  -- save the loaded entry so we can compare
  -- bufnr|path with the next entry. If equal
  -- we can skip loading the buffer again
  self.loaded_entry = entry

  -- Should we cache the current preview buffer?
  -- we cache only named buffers with valid path/uri
  if not self.do_not_cache then
    local key = self.loaded_entry and (self.loaded_entry.path or self.loaded_entry.uri)
    self:cache_buffer(self.preview_bufnr, key, self.do_not_unload)
  end
end

Previewer.help_tags = Previewer.base:extend()

function Previewer.help_tags:should_clear_preview(_)
  return false
end

function Previewer.help_tags:new(o, opts, fzf_win)
  Previewer.help_tags.super.new(self, o, opts, fzf_win)
  self.split = o.split
  self.help_cmd = o.help_cmd or "help"
  self.filetype = "help"
  -- do not unload preview buffer
  -- it's our dedicated ':help' buffer
  self.do_not_unload = true
  self:init_help_win()
  return self
end

function Previewer.help_tags:gen_winopts()
  local winopts = {
    wrap   = self.win.preview_wrap,
    number = false
  }
  return vim.tbl_extend("keep", winopts, self.winopts)
end

function Previewer.help_tags:exec_cmd(str)
  str = str or ""
  vim.cmd(("noauto %s %s %s"):format(self.split, self.help_cmd, str))
end

function Previewer.help_tags:parse_entry(entry_str)
  return entry_str:match("[^%s]+")
end

local function curtab_helpbuf()
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local bufnr = vim.api.nvim_win_get_buf(w)
    local bufinfo = vim.fn.getbufinfo(bufnr)[1]
    if bufinfo.variables and bufinfo.variables.current_syntax == "help" then
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
  pcall(vim.api.nvim_win_call, self.help_winid, function()
    self.prev_help_bufnr = api.nvim_get_current_buf()
    self:exec_cmd(entry)
    vim.api.nvim_buf_set_option(0, "filetype", self.filetype)
    self.preview_bufnr = api.nvim_get_current_buf()
    self.orig_pos = api.nvim_win_get_cursor(0)
  end)
  utils.win_set_buf_noautocmd(self.win.preview_winid, self.preview_bufnr)
  api.nvim_win_set_cursor(self.win.preview_winid, self.orig_pos)
  self.win:update_scrollbar()
  if self.prev_help_bufnr ~= self.preview_bufnr and
      -- only delete the help buffer when the help
      -- tag triggers opening a different help file
      api.nvim_buf_is_valid(self.prev_help_bufnr) then
    api.nvim_buf_delete(self.prev_help_bufnr, { force = true })
    -- save the last buffer so we can close it
    -- at the win_leave event
    self.prev_help_bufnr = self.preview_bufnr
  end
end

function Previewer.help_tags:win_leave()
  if self.help_winid and vim.api.nvim_win_is_valid(self.help_winid) then
    utils.nvim_win_close(self.help_winid, true)
  end
  if self.help_bufnr and vim.api.nvim_buf_is_valid(self.help_bufnr) then
    vim.api.nvim_buf_delete(self.help_bufnr, { force = true })
  end
  if self.prev_help_bufnr and vim.api.nvim_buf_is_valid(self.prev_help_bufnr) then
    vim.api.nvim_buf_delete(self.prev_help_bufnr, { force = true })
  end
  self.help_winid = nil
  self.help_bufnr = nil
  self.prev_help_bufnr = nil
end

Previewer.help_file = Previewer.buffer_or_file:extend()

function Previewer.help_file:new(o, opts, fzf_win)
  Previewer.help_file.super.new(self, o, opts, fzf_win)
  return self
end

function Previewer.help_file:parse_entry(entry_str)
  local tag, filename = entry_str:match("(.*)%s+(.*)$")
  return {
    htag = tag,
    hregex = ([[\V*%s*]]):format(tag:gsub([[\]], [[\\]])),
    path = filename,
    filetype = "help",
  }
end

function Previewer.help_file:gen_winopts()
  local winopts = {
    wrap   = self.win.preview_wrap,
    number = false
  }
  return vim.tbl_extend("keep", winopts, self.winopts)
end

function Previewer.help_file:set_cursor_hl(entry)
  pcall(api.nvim_win_call, self.win.preview_winid, function()
    -- start searching at line 1 in case we
    -- didn't reload the buffer (same file)
    api.nvim_win_set_cursor(0, { 1, 0 })
    fn.clearmatches()
    fn.search(entry.hregex, "W")
    if self.win.winopts.__hl.search then
      fn.matchadd(self.win.winopts.__hl.search, entry.hregex)
    end
    self.orig_pos = api.nvim_win_get_cursor(0)
    utils.zz()
  end)
end

Previewer.man_pages = Previewer.base:extend()

function Previewer.man_pages:should_clear_preview(_)
  return false
end

function Previewer.man_pages:gen_winopts()
  local winopts = {
    wrap   = self.win.preview_wrap,
    number = false
  }
  return vim.tbl_extend("keep", winopts, self.winopts)
end

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
  local cmd = self.cmd:format(entry)
  if type(cmd) == "string" then cmd = { "sh", "-c", cmd } end
  local output, _ = utils.io_systemlist(cmd)
  local tmpbuf = self:get_tmp_buffer()
  -- vim.api.nvim_buf_set_option(tmpbuf, 'modifiable', true)
  vim.api.nvim_buf_set_lines(tmpbuf, 0, -1, false, output)
  vim.api.nvim_buf_set_option(tmpbuf, "filetype", self.filetype)
  self:set_preview_buf(tmpbuf)
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
  if filepath and #filepath > 0 then
    local ok, res = pcall(vim.fn.expand, filepath)
    if not ok then
      filepath = ""
    else
      filepath = res
    end
    filepath = path.relative(filepath, vim.loop.cwd())
  end
  return {
    bufnr = bufnr,
    path  = filepath,
    line  = tonumber(lnum) or 1,
    col   = tonumber(col) or 1,
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
  if filepath then
    local ok, res = pcall(vim.fn.expand, filepath)
    if ok then
      filepath = path.relative(res, vim.loop.cwd())
    end
    if not vim.loop.fs_stat(filepath) then
      -- file is not accessible,
      -- text is a string from current buffer
      bufnr = self.win.src_bufnr
      filepath = vim.api.nvim_buf_get_name(self.win.src_bufnr)
    end
  end
  return {
    bufnr = bufnr,
    path  = filepath,
    line  = tonumber(lnum) or 1,
    col   = tonumber(col) + 1 or 1,
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
  pcall(api.nvim_win_call, self.win.preview_winid, function()
    -- start searching at line 1 in case we
    -- didn't reload the buffer (same file)
    api.nvim_win_set_cursor(0, { 1, 0 })
    fn.clearmatches()
    fn.search(entry.ctag, "W")
    if self.win.winopts.__hl.search then
      fn.matchadd(self.win.winopts.__hl.search, entry.ctag)
    end
    self.orig_pos = api.nvim_win_get_cursor(0)
    utils.zz()
  end)
end

Previewer.highlights = Previewer.base:extend()

function Previewer.highlights:should_clear_preview(_)
  return false
end

function Previewer.highlights:gen_winopts()
  local winopts = {
    wrap   = self.win.preview_wrap,
    number = false
  }
  return vim.tbl_extend("keep", winopts, self.winopts)
end

function Previewer.highlights:new(o, opts, fzf_win)
  Previewer.highlights.super.new(self, o, opts, fzf_win)
  self.ns_previewer = vim.api.nvim_create_namespace("fzf-lua.previewer.hl")
  return self
end

function Previewer.highlights:close()
  Previewer.highlights.super.close(self)
  self.tmpbuf = nil
end

function Previewer.highlights:populate_preview_buf(entry_str)
  if not self.tmpbuf then
    local output = vim.split(vim.fn.execute "highlight", "\n")
    local hl_groups = {}
    for _, v in ipairs(output) do
      if v ~= "" then
        if v:sub(1, 1) == " " then
          local part_of_old = v:match "%s+(.*)"
          hl_groups[#hl_groups] = hl_groups[#hl_groups] .. part_of_old
        else
          table.insert(hl_groups, v)
        end
      end
    end

    self.tmpbuf = self:get_tmp_buffer()
    vim.api.nvim_buf_set_lines(self.tmpbuf, 0, -1, false, hl_groups)
    for k, v in ipairs(hl_groups) do
      local startPos = string.find(v, "xxx", 1, true) - 1
      local endPos = startPos + 3
      local hlgroup = string.match(v, "([^ ]*)%s+.*")
      pcall(vim.api.nvim_buf_add_highlight, self.tmpbuf, 0, hlgroup, k - 1, startPos, endPos)
    end
    self:set_preview_buf(self.tmpbuf)
  end

  local selected_hl = "^" .. utils.strip_ansi_coloring(entry_str) .. "\\>"
  pcall(vim.api.nvim_buf_clear_namespace, self.tmpbuf, self.ns_previewer, 0, -1)
  pcall(api.nvim_win_call, self.win.preview_winid, function()
    -- start searching at line 1 in case we
    -- didn't reload the buffer (same file)
    api.nvim_win_set_cursor(0, { 1, 0 })
    fn.clearmatches()
    fn.search(selected_hl, "W")
    if self.win.winopts.__hl.search then
      fn.matchadd(self.win.winopts.__hl.search, selected_hl)
    end
    self.orig_pos = api.nvim_win_get_cursor(0)
    utils.zz()
  end)
  self.win:update_scrollbar()
end

Previewer.quickfix = Previewer.base:extend()

function Previewer.quickfix:should_clear_preview(_)
  return true
end

function Previewer.quickfix:gen_winopts()
  local winopts = {
    wrap       = self.win.preview_wrap,
    cursorline = false,
    number     = false
  }
  return vim.tbl_extend("keep", winopts, self.winopts)
end

function Previewer.quickfix:new(o, opts, fzf_win)
  Previewer.quickfix.super.new(self, o, opts, fzf_win)
  return self
end

function Previewer.quickfix:close()
  Previewer.highlights.super.close(self)
end

function Previewer.quickfix:populate_preview_buf(entry_str)
  local nr = entry_str:match("[(%d+)]")
  if not nr or tonumber(nr) <= 0 then
    return
  end

  local qf_list = self.opts._is_loclist
      and vim.fn.getloclist(self.win.src_winid, { all = "", nr = tonumber(nr) })
      or vim.fn.getqflist({ all = "", nr = tonumber(nr) })
  if vim.tbl_isempty(qf_list) or vim.tbl_isempty(qf_list.items) then
    return
  end

  local lines = {}
  for _, e in ipairs(qf_list.items) do
    table.insert(lines, string.format("%s|%d col %d|%s",
      path.HOME_to_tilde(path.relative(
        vim.api.nvim_buf_get_name(e.bufnr), vim.loop.cwd())),
      e.lnum, e.col, e.text))
  end
  self.tmpbuf = self:get_tmp_buffer()
  vim.api.nvim_buf_set_lines(self.tmpbuf, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(self.tmpbuf, "filetype", "qf")
  self:set_preview_buf(self.tmpbuf)
  self.win:update_title(string.format("%s: %s", nr, qf_list.title))
  self.win:update_scrollbar()
end

Previewer.autocmds = Previewer.buffer_or_file:extend()

function Previewer.autocmds:new(o, opts, fzf_win)
  Previewer.autocmds.super.new(self, o, opts, fzf_win)
  return self
end

function Previewer.autocmds:gen_winopts()
  if not self._is_vimL_command then
    return self.winopts
  end
  -- set wrap and no cursorline/numbers for vimL commands
  local winopts = {
    wrap       = true,
    cursorline = false,
    number     = false
  }
  return vim.tbl_extend("keep", winopts, self.winopts)
end

function Previewer.autocmds:populate_preview_buf(entry_str)
  if not self.win or not self.win:validate_preview() then return end
  local entry = self:parse_entry(entry_str)
  if vim.tbl_isempty(entry) then return end
  self._is_vimL_command = false
  if entry.path == "<none>" then
    self._is_vimL_command = true
    entry.path = entry_str:match("[^:]+│")
    local viml = entry_str:match("[^│]+$")
    local lines = vim.split(viml, "\n")
    local tmpbuf = self:get_tmp_buffer()
    vim.api.nvim_buf_set_lines(tmpbuf, 0, -1, false, lines)
    vim.api.nvim_buf_set_option(tmpbuf, "filetype", "vim")
    self:set_preview_buf(tmpbuf)
    self:preview_buf_post(entry)
  else
    self.super.populate_preview_buf(self, entry_str)
  end
end

return Previewer
