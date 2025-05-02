local path = require "fzf-lua.path"
local shell = require "fzf-lua.shell"
local utils = require "fzf-lua.utils"
local libuv = require "fzf-lua.libuv"
local Object = require "fzf-lua.class"

local uv = vim.uv or vim.loop
local api = vim.api
local fn = vim.fn


local TSContext = {}

function TSContext.setup(opts)
  if TSContext._setup then return true end
  if not package.loaded["treesitter-context"] then
    return false
  end
  -- Our temp nvim-treesitter-context config
  TSContext._setup_opts = {}
  for k, v in pairs(opts) do
    TSContext._setup_opts[k] = { v }
  end
  local config = require("treesitter-context.config")
  TSContext._config = utils.tbl_deep_clone(config)
  for k, v in pairs(TSContext._setup_opts) do
    v[2] = config[k]
    config[k] = v[1]
  end
  TSContext._winids = {}
  TSContext._setup = true
  return true
end

function TSContext.deregister()
  if not TSContext._setup then return end
  for winid, _ in pairs(TSContext._winids) do
    TSContext.close(winid)
  end
  local config = require("treesitter-context.config")
  for k, v in pairs(TSContext._setup_opts) do
    config[k] = v[2]
  end
  TSContext._config = nil
  TSContext._winids = nil
  TSContext._setup = nil
end

function TSContext.is_attached(winid)
  if not TSContext._setup then return false end
  return TSContext._winids[tostring(winid)]
end

---@param winid number
function TSContext.close(winid)
  if not TSContext._setup then return end
  require("treesitter-context.render").close(tonumber(winid))
  TSContext._winids[tostring(winid)] = nil
end

---@param winid number
---@param bufnr number
function TSContext.toggle(winid, bufnr)
  if not TSContext._setup then return end
  if TSContext.is_attached(winid) then
    TSContext.close(winid)
  else
    TSContext.update(winid, bufnr)
  end
end

function TSContext.inc_dec_maxlines(num, winid, bufnr)
  if not TSContext._setup or not tonumber(num) then return end
  local config = require("treesitter-context.config")
  local max_lines = config.max_lines or 0
  config.max_lines = math.max(0, max_lines + tonumber(num))
  utils.info(string.format("treesitter-context `max_lines` set to %d.", config.max_lines))
  if TSContext.is_attached(winid) then
    for _, t in ipairs({ 0, 20 }) do
      vim.defer_fn(function() TSContext.update(winid, bufnr) end, t)
    end
  end
end

---@param winid number
---@param bufnr number
---@param opts? { setup_opts: table, zindex: integer }
function TSContext.update(winid, bufnr, opts)
  opts = opts or {}
  if not TSContext.setup(opts.setup_opts) then return end
  assert(bufnr == vim.api.nvim_win_get_buf(winid))
  -- excerpt from nvim-treesitter-context `update_single_context`
  require("treesitter-context.render").close_leaked_contexts()
  local context_ranges, context_lines = require("treesitter-context.context").get(bufnr, winid)
  if not context_ranges or #context_ranges == 0 then
    TSContext.close(winid)
  else
    assert(context_lines)
    local function open()
      if vim.api.nvim_buf_is_valid(bufnr) and vim.api.nvim_win_is_valid(winid) then
        -- ensure context win is above
        local fix_zindex = function(win, zindex)
          if win and api.nvim_win_is_valid(win) then api.nvim_win_set_config(win, { zindex = zindex }) end
        end
        api.nvim_win_call(winid, function()
          local window_context = require("treesitter-context.render").open(bufnr, winid,
            context_ranges, context_lines)
          if not window_context then return end
          fix_zindex(window_context.context_winid, opts.zindex)
          fix_zindex(window_context.gutter_winid, opts.zindex)
        end)
        TSContext._winids[tostring(winid)] = bufnr
      end
    end
    -- NOTE: no longer required since adding `eventignore` to `FzfWin:set_winopts`
    -- if TSContext.is_attached(winid) == bufnr then
    open()
    -- else
    --   -- HACK: but the entire nvim-treesitter-context is essentially a hack
    --   -- https://github.com/ibhagwan/fzf-lua/issues/1552#issuecomment-2525456813
    --   for _, t in ipairs({ 0, 20 }) do
    --     vim.defer_fn(function() open() end, t)
    --   end
    -- end
  end
end

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
  self.title_pos = self.win.winopts.preview.title_pos
  self.title_fnamemodify = o.title_fnamemodify
  self.render_markdown = type(o.render_markdown) == "table" and o.render_markdown or {}
  self.render_markdown.filetypes =
      type(self.render_markdown.filetypes) == "table" and self.render_markdown.filetypes or {}
  self.snacks_image = type(o.snacks_image) == "table" and o.snacks_image or {}
  self.winopts = self.win.winopts.preview.winopts
  self.syntax = default(o.syntax, true)
  self.syntax_delay = tonumber(default(o.syntax_delay, 0))
  self.syntax_limit_b = tonumber(default(o.syntax_limit_b, 1024 * 1024))
  self.syntax_limit_l = tonumber(default(o.syntax_limit_l, 0))
  self.limit_b = tonumber(default(o.limit_b, 1024 * 1024 * 10))
  self._ts_limit_b_per_line = tonumber(default(o._ts_limit_b_per_line, 1000))
  self.treesitter = type(o.treesitter) == "table" and o.treesitter or {}
  self.toggle_behavior = o.toggle_behavior
  self.winopts_orig = {}
  self.winblend = self.winblend or self.winopts.winblend or vim.o.winblend
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
  self.cached_bufnrs = {}
  self.cached_buffers = {}
  -- store currently listed buffers, this helps us determine which buffers
  -- navigated with 'vim.lsp.util.show_document' we can safely unload
  -- since show_document reuses buffers and I couldn't find a better way
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

function Previewer.base:close(do_not_clear_cache)
  TSContext.deregister()
  self:restore_winopts()
  self:clear_preview_buf()
  if not do_not_clear_cache then
    self:clear_cached_buffers()
  end
  self.winopts_orig = {}
end

function Previewer.base:gen_winopts()
  local winopts = { wrap = self.win.preview_wrap }
  return vim.tbl_extend("keep", winopts, self.winopts)
end

function Previewer.base:backup_winopts()
  if rawequal(next(self.winopts_orig), nil) then
    self.winopts_orig = self.win:get_winopts(self.win.src_winid, self:gen_winopts())
  end
end

function Previewer.base:restore_winopts()
  self.win:set_winopts(self.win.preview_winid, self.winopts_orig)
end

function Previewer.base:set_style_winopts()
  -- NOTE: `true` to ignore events for initial TSContext.update
  self.win:set_winopts(self.win.preview_winid, self:gen_winopts(), true)
end

function Previewer.base:preview_is_terminal()
  if not self.win or not self.win:validate_preview() then return end
  return utils.getwininfo(self.win.preview_winid).terminal == 1
end

function Previewer.base:get_tmp_buffer()
  local tmp_buf = api.nvim_create_buf(false, true)
  vim.bo[tmp_buf].modeline = true
  vim.bo[tmp_buf].modifiable = true
  vim.bo[tmp_buf].bufhidden = "wipe"
  return tmp_buf
end

function Previewer.base:safe_buf_delete(bufnr, del_cached)
  -- can be nil after closing preview with <F4>
  if not bufnr then return end
  assert(type(bufnr) == "number" and bufnr > 0)
  -- NOTE: listed buffers map key must use 'tostring'
  if self.listed_buffers[tostring(bufnr)] then
    -- print("safe_buf_delete LISTED", bufnr)
    return
  elseif not vim.api.nvim_buf_is_valid(bufnr) then
    -- print("safe_buf_delete INVALID", bufnr)
    return
  elseif not del_cached and self.cached_bufnrs[tostring(bufnr)] then
    -- print("safe_buf_delete CACHED", bufnr)
    return
  end
  -- print("safe_buf_delete DELETE", bufnr)
  -- delete buffer marks
  vim.api.nvim_buf_call(bufnr, function()
    vim.cmd([[delm \"]])
  end)
  -- delete the buffer
  vim.api.nvim_buf_delete(bufnr, { force = true })
end

function Previewer.base:set_preview_buf(newbuf, min_winopts)
  if not self.win or not self.win:validate_preview() then return end
  -- Set the preview window to the new buffer
  local curbuf = vim.api.nvim_win_get_buf(self.win.preview_winid)
  if curbuf == newbuf then return end
  -- Something went terribly wrong
  assert(curbuf ~= newbuf)
  utils.win_set_buf_noautocmd(self.win.preview_winid, newbuf)
  -- to make gc work, don't reference `win._previewer` in a callback
  local winid = self.win.fzf_winid
  vim.keymap.set("", "i", function()
    vim.api.nvim_set_current_win(winid)
    vim.cmd("startinsert")
  end, { buffer = newbuf })
  self.preview_bufnr = newbuf
  -- set preview window options
  if min_winopts then
    -- removes 'number', 'signcolumn', 'cursorline', etc
    self.win:set_style_minimal(self.win.preview_winid)
  else
    -- sets the style defined by `winopts.preview.winopts`
    self:set_style_winopts()
  end
  -- although the buffer has 'bufhidden:wipe' it sometimes doesn't
  -- get wiped when pressing `ctrl-g` too quickly
  self:safe_buf_delete(curbuf)
end

function Previewer.base:cache_buffer(bufnr, key, min_winopts)
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
      -- new cached buffer for key, wipe current cached buf
      self.cached_bufnrs[tostring(cached.bufnr)] = nil
      self:safe_buf_delete(cached.bufnr)
    end
  end
  self.cached_bufnrs[tostring(bufnr)] = true
  self.cached_buffers[key] = { bufnr = bufnr, min_winopts = min_winopts }
  -- remove buffer auto-delete since it's now cached
  vim.bo[bufnr].bufhidden = "hide"
end

function Previewer.base:clear_cached_buffers()
  -- clear the buffer cache
  for _, c in pairs(self.cached_buffers) do
    self:safe_buf_delete(c.bufnr, true)
  end
  self.cached_bufnrs = {}
  self.cached_buffers = {}
end

function Previewer.base:clear_preview_buf(newbuf)
  local retbuf = nil
  if ((self.win and self.win._reuse) or newbuf)
      -- Attach a temp buffer to the window when reusing (`ctrl-g`)
      -- so we don't invalidate the window when deting the buffer
      -- in `safe_buf_delete` call below
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
    -- redraw the title line and clear the scrollbar
    self.win:close_preview_scrollbar()
  end
  -- since our temp buffers have 'bufhidden=wipe' the tmp
  -- buffer will be automatically wiped and 'nvim_buf_is_valid'
  -- will return false
  -- one case where the buffer may remain valid after detaching
  -- from the preview window is with URI type entries after calling
  -- 'vim.lsp.util.show_document' which can reuse existing buffers,
  -- so technically this should never be executed unless the
  -- user wrote an fzf-lua extension and set the preview buffer to
  -- a random buffer without the 'bufhidden' property
  self:safe_buf_delete(self.preview_bufnr)
  self.preview_bufnr = nil
  self.loaded_entry = nil
  return retbuf
end

function Previewer.base:display_last_entry()
  self:display_entry(self.last_entry)
end

function Previewer.base:display_entry(entry_str)
  if not entry_str then return end
  if not self.win or not self.win:validate_preview() then return end

  -- verify backup the current window options
  -- will store only of `winopts_orig` is nil
  self:backup_winopts()

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
    local entry, query, idx = unpack(items, 1, 3)
    -- NOTE: see comment regarding {n} in `core.convert_exec_silent_actions`
    -- convert empty string to nil
    if not tonumber(idx) then entry = nil end
    -- on windows, query may not be expanded to a string: #1887
    self.opts._last_query = query or ""
    if self.last_entry ~= entry then
      -- save last entry even if we don't display
      self.last_entry = entry
      self:display_entry(entry)
    end
    return ""
  end, "{} {q} {n}", self.opts.debug)
  return act
end

function Previewer.base:zero(_)
  --
  -- debounce the zero event call to prevent reentry which may
  -- cause a hang of fzf  or the nvim RPC server (#909)
  -- mkdir is an atomic operation and will fail if the directory
  -- already exists effectively creating a singleton shell command
  --
  -- currently awaiting an upstream fix:
  -- https://github.com/junegunn/fzf/issues/3516
  --
  self._zero_lock = self._zero_lock or path.normalize(vim.fn.tempname())
  local act = string.format("execute-silent(mkdir %s && %s)",
    libuv.shellescape(self._zero_lock),
    shell.raw_action(function(_, _, _)
      vim.defer_fn(function()
        if self.win:validate_preview() then
          self:clear_preview_buf(true)
          TSContext.close(self.win.preview_winid)
          self.win:update_preview_title("")
        end
        self.last_entry = nil
        vim.fn.delete(self._zero_lock, "d")
      end, self.delay)
    end, "", self.opts.debug))
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
  if not self.preview_bufnr or preview_winid < 0 or not direction then return end
  if not api.nvim_win_is_valid(preview_winid) then return end

  -- map direction to scroll commands ('g8' on char to display)
  local input = ({
    ["top"]            = "gg",
    ["bottom"]         = "G",
    ["half-page-up"]   = ("%c"):format(0x15), -- [[]]
    ["half-page-down"] = ("%c"):format(0x04), -- [[]]
    ["page-up"]        = ("%c"):format(0x02), -- [[]]
    ["page-down"]      = ("%c"):format(0x06), -- [[]]
    ["line-up"]        = "Mgk",               -- ^Y doesn't seem to work
    ["line-down"]      = "Mgj",               -- ^E doesn't seem to work
    ["reset"]          = true,                -- dummy for exit condition
  })[direction]

  if not input then return end

  if direction == "reset" then
    pcall(vim.api.nvim_win_call, preview_winid, function()
      -- for some reason 'nvim_win_set_cursor'
      -- only moves forward, so set to (1,0) first
      api.nvim_win_set_cursor(0, { 1, 0 })
      if self.orig_pos then
        api.nvim_win_set_cursor(0, self.orig_pos)
      end
      utils.zz()
    end)
  else
    pcall(vim.api.nvim_win_call, preview_winid, function()
      -- ctrl-b (page-up) behaves in a non consistent way, unlike ctrl-u, if it can't
      -- scroll a full page upwards it won't move the cursor, if the cursor is within
      -- the first page it will still move the cursor to the bottom of the page (!?)
      -- we therefore need special handling for both scenarios with `ctrl-b`:
      --   (1) If the cursor is at line 1, do nothing
      --   (2) Else, test the cursor before and after, if the new position is further
      --       down the buffer than the original, we're in the first page ,goto line 1
      local is_ctrl_b = string.byte(input, 1) == 2
      local pos = is_ctrl_b and vim.api.nvim_win_get_cursor(0)
      if is_ctrl_b and pos[1] == 1 then return end
      vim.cmd([[norm! ]] .. input)
      if is_ctrl_b and pos[1] <= vim.api.nvim_win_get_cursor(0)[1] + 1 then
        vim.api.nvim_win_set_cursor(0, { 1, pos[2] })
      end
      utils.zz()
    end)
  end
  -- 'cursorline' is effectively our match highlight. Once the
  -- user scrolls, the highlight is no longer relevant (#462).
  -- Conditionally toggle 'cursorline' based on cursor position
  self:maybe_set_cursorline(preview_winid, self.orig_pos)
  -- HACK: Hijack cached bufnr value as last scroll position
  if self.cached_bufnrs[tostring(self.preview_bufnr)] then
    if direction == "reset" then
      self.cached_bufnrs[tostring(self.preview_bufnr)] = true
    else
      self.cached_bufnrs[tostring(self.preview_bufnr)] = vim.api.nvim_win_get_cursor(preview_winid)
    end
  end
  self.win:update_preview_scrollbar()
  self:update_render_markdown()
  self:update_ts_context()
end

function Previewer.base:ts_ctx_toggle()
  local bufnr, winid = self.preview_bufnr, self.win.preview_winid
  if winid < 0 or not api.nvim_win_is_valid(winid) then return end
  if self.treesitter.context then
    self.treesitter._context = self.treesitter.context
    self.treesitter.context = nil
  else
    self.treesitter.context = self.treesitter._context or true
    self.treesitter._context = nil
  end
  TSContext.toggle(winid, bufnr)
end

function Previewer.base:ts_ctx_inc_dec_maxlines(num)
  local bufnr, winid = self.preview_bufnr, self.win.preview_winid
  if winid < 0 or not api.nvim_win_is_valid(winid) then return end
  TSContext.inc_dec_maxlines(num, winid, bufnr)
end

Previewer.buffer_or_file = Previewer.base:extend()

function Previewer.buffer_or_file:new(o, opts, fzf_win)
  Previewer.buffer_or_file.super.new(self, o, opts, fzf_win)
  return self
end

function Previewer.buffer_or_file:close(do_not_clear_cache)
  Previewer.base.close(self, do_not_clear_cache)
  self:stop_ueberzug()
end

function Previewer.buffer_or_file:parse_entry(entry_str)
  local entry = path.entry_to_file(entry_str, self.opts)
  return entry
end

function Previewer.buffer_or_file:should_clear_preview(_)
  return false
end

function Previewer.buffer_or_file:should_load_buffer(entry)
  -- we don't have a previous entry to compare to or `do_not_cache` is set meaning
  -- it's a terminal command (chafa, viu, ueberzug) which requires a reload
  -- return 'true' so the buffer will be loaded in ::populate_preview_buf
  if not self.loaded_entry or self.loaded_entry.do_not_cache then return true end
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
  self._ueberzug_fifo = path.join({
    vim.fn.fnamemodify(vim.fn.tempname(), ":h"),
    string.format("fzf-lua-%d-ueberzug", vim.fn.getpid())
  })
  utils.io_system({ "mkfifo", self._ueberzug_fifo })
  self._ueberzug_job = vim.fn.jobstart({ "sh", "-c",
    string.format(
      "tail -f %s | ueberzug layer --parser json",
      libuv.shellescape(self._ueberzug_fifo))
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
          utils.info("ueberzug: " .. l)
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
  -- no caching: preview buf must be reattached for
  -- terminal image previews to have the correct size
  entry.do_not_cache = true
  -- when terminal execution ends last line in the buffer
  -- will display "[Process exited 0]", this will enable
  -- the scrollbar which we wish to hide
  entry.no_scrollbar = true
  -- both ueberzug and terminal cmds need a clear
  -- on redraw to fit the new window dimensions
  self.clear_on_redraw = true
  -- 2nd arg `true`: minimal style window
  self:set_preview_buf(tmpbuf, true)
  if cmd[1]:match("ueberzug") then
    local fifo = self:start_ueberzug()
    if not fifo then return end
    local wincfg = vim.api.nvim_win_get_config(self.win.preview_winid)
    local winpos = vim.api.nvim_win_get_position(self.win.preview_winid)
    local params = {
      action     = "add",
      identifier = "preview",
      x          = winpos[2] + 1,
      y          = winpos[1] + 2,
      width      = wincfg.width - 2,
      height     = wincfg.height - 2,
      scaler     = self.ueberzug_scaler,
      path       = path.is_absolute(entry.path) and entry.path or
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
    -- replace `{file}` placeholder with the filename
    local add_file = true
    for i, arg in ipairs(cmd) do
      if type(arg) == "string" and arg:match("[<{]file[}>]") then
        cmd[i] = entry.path
        add_file = false
      end
    end
    -- or add filename as last parameter
    if add_file then
      table.insert(cmd, entry.path)
    end
    -- must be modifiable or 'termopen' fails
    vim.bo[tmpbuf].modifiable = true
    vim.api.nvim_buf_call(tmpbuf, function()
      self._job_id = utils.termopen(cmd, {
        cwd = self.opts.cwd,
        on_exit = function()
          -- run post only after terminal job finished
          if self._job_id then
            self:preview_buf_post(entry, true)
            self._job_id = nil
          end
        end
      })
    end)
  end
  -- run here so title gets updated
  -- even if the image is still loading
  self:preview_buf_post(entry, true)
  return true
end

function Previewer.buffer_or_file:key_from_entry(entry)
  assert(entry)
  return entry.bufnr and string.format("bufnr:%d", entry.bufnr)
      or entry.uri
      or entry.path
end

function Previewer.buffer_or_file:populate_from_cache(entry)
  local key = self:key_from_entry(entry)
  assert(type(key) == "string" and #key > 0)
  local cached = self.cached_buffers[key]
  assert(not cached or self.cached_bufnrs[tostring(cached.bufnr)])
  assert(not cached or vim.api.nvim_buf_is_valid(cached.bufnr))
  if cached and vim.api.nvim_buf_is_valid(cached.bufnr) then
    self:set_preview_buf(cached.bufnr, cached.min_winopts)
    self:preview_buf_post(entry, cached.min_winopts)
    return true
  end
  return false
end

function Previewer.buffer_or_file:populate_preview_buf(entry_str)
  if not self.win or not self.win:validate_preview() then return end
  -- stop ueberzug shell job
  self:stop_ueberzug()
  local entry = self:parse_entry(entry_str)
  if utils.tbl_isempty(entry) then return end
  if entry.bufnr and not api.nvim_buf_is_loaded(entry.bufnr)
      and vim.api.nvim_buf_is_valid(entry.bufnr) then
    -- buffer is not loaded, can happen when calling "lines" with `set nohidden`
    -- or when starting nvim with an arglist, fix entry.path since it contains
    -- filename only
    entry.path = path.relative_to(vim.api.nvim_buf_get_name(entry.bufnr), uv.cwd())
  end
  if not self:should_load_buffer(entry) then
    -- same file/buffer as previous entry no need to reload content
    -- only call post to set cursor location
    if type(self.cached_bufnrs[tostring(self.preview_bufnr)]) == "table"
        and ((tonumber(entry.line) and entry.line > 0 and entry.line ~= self.orig_pos[1])
          or (tonumber(entry.col) and entry.col > 0 and entry.col - 1 ~= self.orig_pos[2]))
    then
      -- entry is within the same buffer but line|col has changed
      -- clear cached buffer position so we scroll to entry's line|col
      self.cached_bufnrs[tostring(self.preview_bufnr)] = true
    end
    self:preview_buf_post(entry)
    return
  elseif self:populate_from_cache(entry) then
    -- already populated
    return
  end
  self.clear_on_redraw = false
  -- kill previously running terminal jobs
  -- when using external commands extension map
  if self._job_id and self._job_id > 0 then
    vim.fn.jobstop(self._job_id)
    self._job_id = nil
  end
  if entry.bufnr and api.nvim_buf_is_loaded(entry.bufnr) then
    -- WE NO LONGER REUSE THE CURRENT BUFFER
    -- this changes the buffer's 'getbufinfo[1].lastused'
    -- which messes up our `buffers()` sort
    entry.filetype = vim.bo[entry.bufnr].filetype
    local lines = vim.api.nvim_buf_get_lines(entry.bufnr, 0, -1, false)
    local tmpbuf = self:get_tmp_buffer()
    vim.api.nvim_buf_set_lines(tmpbuf, 0, -1, false, lines)
    -- terminal buffers use minimal window style (2nd arg)
    self:set_preview_buf(tmpbuf, entry.terminal)
    self:preview_buf_post(entry, entry.terminal)
  elseif entry.uri then
    -- LSP 'jdt://' entries, see issue #195
    -- https://github.com/ibhagwan/fzf-lua/issues/195
    vim.api.nvim_win_call(self.win.preview_winid, function()
      local ok, res = pcall(utils.jump_to_location, entry, "utf-16", false)
      if ok then
        self.preview_bufnr = vim.api.nvim_get_current_buf()
      else
        -- in case of an error display the stacktrace in the preview buffer
        local lines = type(res) == "string" and utils.strsplit(res, "\n") or { "null" }
        table.insert(lines, 1,
          string.format("lsp.util.%s failed for '%s':",
            utils.__HAS_NVIM_011 and "show_document" or "jump_to_location", entry.uri))
        table.insert(lines, 2, "")
        local tmpbuf = self:get_tmp_buffer()
        vim.api.nvim_buf_set_lines(tmpbuf, 0, -1, false, lines)
        self:set_preview_buf(tmpbuf)
      end
    end)
    self:preview_buf_post(entry)
  else
    assert(entry.path)
    -- not found in cache, attempt to load
    local tmpbuf = self:get_tmp_buffer()
    if self.extensions and not utils.tbl_isempty(self.extensions) then
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
    if self:attach_snacks_image_buf(tmpbuf, entry) then
      -- Similar settings as `populate_terminal_cmd`
      entry.do_not_cache = true
      entry.no_scrollbar = true
      self.clear_on_redraw = true
      -- 2nd arg `true`: minimal style window
      self:set_preview_buf(tmpbuf, true)
      self:preview_buf_post(entry)
      return
    end
    do
      local lines = nil
      if entry.path:match("^%[DEBUG]") then
        lines = { tostring(entry.path:gsub("^%[DEBUG]", "")) }
      else
        -- make sure the file is readable (or bad entry.path)
        local fs_stat = uv.fs_stat(entry.path)
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
      end
      if lines then
        pcall(vim.api.nvim_buf_set_lines, tmpbuf, 0, -1, false, lines)
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

-- Attach ts highlighter, neovim >= v0.9
local ts_attach = function(bufnr, ft)
  -- ts is already attach, see $VIMRUNTIME/lua/vim/treesitter/highlighter.lua
  if vim.b[bufnr].ts_highlight then return true end
  local lang = vim.treesitter.language.get_lang(ft)
  local loaded = lang and utils.has_ts_parser(lang)
  if lang and loaded then
    local ok, err = pcall(vim.treesitter.start, bufnr, lang)
    if not ok then
      utils.warn(string.format(
        "unable to attach treesitter highlighter for filetype '%s': %s", ft, err))
    end
    return ok
  end
end

function Previewer.base:update_ts_context()
  local bufnr = self.preview_bufnr
  local ft = vim.b[bufnr] and vim.b[bufnr]._ft
  if not ft
      or not self.win
      or not self.win:validate_preview()
      or not self.treesitter.enabled
      or not self.treesitter.context
  then
    return
  end
  -- HACK: since TS async parsing commit we cannot guarantee the TSContext ranges as these will
  -- return empty unless parsing is complete and we have no access to the `on_parse` event
  -- https://github.com/neovim/neovim/commit/45e606b1fddbfeee8fe28385b5371ca6f2fba71b
  -- For more info see #1922
  local lang = vim.treesitter.language.get_lang(ft)
  if not utils.has_ts_parser(lang) then return end
  local parser = vim.treesitter.get_parser(self.preview_bufnr, lang)
  local context_updated
  for _, t in ipairs({ 0, 20, 50, 100 }) do
    vim.defer_fn(function()
      if context_updated
          or not tonumber(self.preview_bufnr)
          or not vim.api.nvim_buf_is_valid(self.preview_bufnr)
      then
        return
      end
      if parser:is_valid(true) then
        context_updated = true
        TSContext.update(self.win.preview_winid, self.preview_bufnr,
          {
            setup_opts = vim.tbl_extend("force",
              type(self.treesitter.context) == "table" and self.treesitter.context or {}, {
                -- `multiwindow` must be set regardless of user options
                multiwindow = true,
              }),
            zindex = self.win.winopts.zindex + 20,
          })
      end
    end, t)
  end
end

function Previewer.base:update_render_markdown()
  local bufnr, winid = self.preview_bufnr, self.win.preview_winid
  local ft = vim.b[bufnr] and vim.b[bufnr]._ft
  if not ft
      or not self.render_markdown.enabled
      or not self.render_markdown.filetypes[ft]
  then
    return
  end
  if package.loaded["render-markdown"] then
    require("render-markdown.core.ui").update(bufnr, winid, "FzfLua", true)
  elseif package.loaded["markview"] then
    --- Render strictly to save performance.
    ---
    --- Use `strict:render(bufnr, 1000)` to stop rendering if
    --- line count >= 1000.
    local strict = package.loaded["markview"].strict_render;
    if strict then strict:render(bufnr); end
  end
end

function Previewer.base:attach_snacks_image_buf(buf, entry)
  local simg = self.snacks_image.enabled and (Snacks or {}).image
  if not simg or not simg.supports(entry.path) then
    return false
  end
  simg.buf.attach(buf, { src = entry.path })
  return true
end

function Previewer.base:attach_snacks_image_inline()
  local simg = (Snacks or {}).image
  local bufnr, preview_winid = self.preview_bufnr, self.win.preview_winid
  if not simg
      or not self.snacks_image.enabled
      or not simg.supports_terminal()
      or not (simg.config.doc.inline and simg.terminal.env().placeholders)
      or vim.b[bufnr].snacks_image_attached then
    return
  end

  -- restore default winblend when on unsupport ft
  local ft = vim.b[bufnr]._ft
  if not ft then return end
  _G._fzf_lua_snacks_langs = _G._fzf_lua_snacks_langs or simg.langs()
  if not vim.tbl_contains(_G._fzf_lua_snacks_langs, vim.treesitter.language.get_lang(ft)) then
    vim.wo[preview_winid].winblend = self.winblend
    return
  end

  vim.wo[preview_winid].winblend = 0 -- https://github.com/folke/snacks.nvim/pull/1615
  vim.b[bufnr].snacks_image_attached = simg.inline.new(bufnr)
  vim.defer_fn(function()
    self.win:update_preview_scrollbar()
  end, 500)
end

function Previewer.buffer_or_file:do_syntax(entry)
  if not self.preview_bufnr then return end
  if not entry or not entry.path then return end
  local bufnr = self.preview_bufnr
  local preview_winid = self.win.preview_winid
  if not api.nvim_buf_is_valid(bufnr)
      or vim.bo[bufnr].filetype ~= ""
      or fn.bufwinid(bufnr) ~= preview_winid
  then
    return
  end

  -- assign a name for noname scratch buffer
  -- can be used by snacks.image to abspath e.g. [file.png]
  -- https://github.com/folke/snacks.nvim/pull/1618
  vim.b[bufnr].bufpath = entry.path

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
  if syntax_limit_reached > 0 and self.opts.silent == false then
    utils.info(string.format(
      "syntax disabled for '%s' (%s), consider increasing '%s(%d)'", entry.path,
      syntax_limit_reached == 1 and ("%d lines"):format(lcount) or ("%db"):format(bytes),
      syntax_limit_reached == 1 and "syntax_limit_l" or "syntax_limit_b",
      syntax_limit_reached == 1 and self.syntax_limit_l or self.syntax_limit_b
    ))
  end

  if syntax_limit_reached ~= 0 then
    return
  end

  -- filetype detect
  ---@type string
  local ft = (function()
    local ft = entry.filetype or vim.filetype.match({ buf = bufnr, filename = entry.path })
    if type(ft) == "string" then
      return ft
    end
    -- prepend the buffer number to the path and
    -- set as buffer name, this makes sure 'filetype detect'
    -- gets the right filetype which enables the syntax
    local tempname = path.join({ tostring(bufnr), entry.path })
    pcall(api.nvim_buf_set_name, bufnr, tempname)
    -- nvim_buf_call has less side-effects than window switch
    -- doautocmd filetypedetect BufRead (vim.filetype.match + ftdetect) + do_modeline
    local ok, _ = pcall(api.nvim_buf_call, bufnr, function()
      utils.eventignore(function() vim.cmd("filetype detect") end, preview_winid, "FileType")
    end)
    if not ok then
      utils.warn(("':filetype detect' failed for '%s'"):format(entry.path or "<null>"))
    end
    return vim.bo[bufnr].filetype
  end)()

  if ft == "" then return end

  -- Use buf local var as setting ft might have unintended consequences
  -- used in `update_render_markdown`, `attach_snacks_image`
  vim.b[bufnr]._ft = ft

  local ts_enabled = (function()
    -- disable treesitter on minified (long line) file
    if (bytes / lcount) > self._ts_limit_b_per_line then return false end
    if not self.treesitter or
        self.treesitter.enabled == false or
        self.treesitter.disabled == true or
        (type(self.treesitter.enabled) == "table" and
          not utils.tbl_contains(self.treesitter.enabled, ft)) or
        (type(self.treesitter.disabled) == "table" and
          utils.tbl_contains(self.treesitter.disabled, ft)) then
      return false
    end
    return true
  end)()

  local ts_success = ts_enabled and ts_attach(bufnr, ft)
  if not ts_success then
    pcall(function() vim.bo[bufnr].syntax = ft end)
    return
  end

  self:update_render_markdown()
  self:update_ts_context()
end

function Previewer.base:maybe_set_cursorline(win, pos)
  if not pos then return end
  local wininfo = utils.getwininfo(win)
  if wininfo
      and pos[1] >= wininfo.topline
      and pos[1] <= wininfo.botline
  then
    -- reset cursor pos even when it's already there, no bigggie
    -- local curpos = vim.api.nvim_win_get_cursor(win)
    vim.api.nvim_win_set_cursor(win, pos)
    vim.wo[win].cursorline = self.winopts.cursorline
  else
    vim.wo[win].cursorline = false
  end
end

function Previewer.buffer_or_file:set_cursor_hl(entry)
  local mgrep, glob_args = require("fzf-lua.providers.grep"), nil
  local regex = self.opts.__ACT_TO == mgrep.grep and self.opts._last_query
      or self.opts.__ACT_TO == mgrep.live_grep and self.opts.search or nil
  if regex and self.opts.fn_transform_cmd then
    local _, query = self.opts.fn_transform_cmd(regex, self.opts.cmd, self.opts)
    regex = query or regex
  elseif regex and self.opts.rg_glob and self.opts.glob_separator then
    regex, glob_args = require("fzf-lua.make_entry").glob_parse(regex, self.opts)
  end
  if regex then
    (function()
      -- Check both the cmd and glob_args in case the user has a custom
      -- `rg_glob_fn` which uses raw args (as the wiki example)
      for _, s in ipairs({ self.opts.cmd, glob_args }) do
        if s and (s:match("%-%-fixed%-strings") or s:match("%-F")) then
          regex = utils.rg_escape(regex)
          return
        end
      end
    end)()
  end

  -- If called from tags previewer, can happen when using ctags cmd
  -- "ctags -R --c++-kinds=+p --fields=+iaS --extras=+q --excmd=combine"
  regex = regex and #regex > 0 and utils.regex_to_magic(regex)
      or entry.ctag and utils.ctag_to_magic(entry.ctag)

  pcall(vim.api.nvim_win_call, self.win.preview_winid, function()
    local cached_pos = self.cached_bufnrs[tostring(self.preview_bufnr)]
    if type(cached_pos) ~= "table" then cached_pos = nil end
    local lnum, col = tonumber(entry.line), tonumber(entry.col) or 0
    if not lnum or lnum < 1 then
      vim.wo.cursorline = false
      self.orig_pos = { 1, 0 }
      api.nvim_win_set_cursor(self.win.preview_winid, cached_pos or self.orig_pos)
      return
    end

    self.orig_pos = { lnum, math.max(0, col - 1) }
    api.nvim_win_set_cursor(self.win.preview_winid, cached_pos or self.orig_pos)
    self:maybe_set_cursorline(self.win.preview_winid, self.orig_pos)
    fn.clearmatches()

    -- If regex is available (grep/lgrep), match on current line
    local regex_start, regex_end = 0, nil
    if regex and self.win.hls.search then
      -- vim.regex is always magic, see `:help vim.regex`
      local ok, reg = pcall(vim.regex, regex)
      if ok then
        regex_start, regex_end = reg:match_line(self.preview_bufnr, lnum - 1, math.max(1, col) - 1)
        regex_end = tonumber(regex_end) and regex_end - regex_start
        regex_start = tonumber(regex_start) and regex_start + math.max(1, col) or 0
      elseif self.opts.silent ~= true then
        utils.warn(string.format(
          [[Unable to init vim.regex with "%s", %s. . Add 'silent=true' to hide this message.]],
          regex, reg))
      end
      if regex_start > 0 then
        fn.matchaddpos(self.win.hls.search, { { lnum, regex_start, regex_end } }, 11)
      end
    end

    -- Fallback to cursor hl, only if column exists
    if regex_start <= 0 and self.win.hls.cursor and col > 0 then
      fn.matchaddpos(self.win.hls.cursor, { { lnum, math.max(1, col) } }, 11)
    end

    utils.zz()
  end)
end

function Previewer.buffer_or_file:update_title(entry)
  if not self.title then return end
  local filepath = entry.path
  if filepath then
    if filepath:match("^%[DEBUG]") then
      filepath = "[DEBUG]"
    else
      if self.opts.cwd then
        filepath = path.relative_to(entry.path, self.opts.cwd)
      end
      filepath = path.HOME_to_tilde(filepath)
    end
  end
  local title = filepath or entry.uri or entry.bufname
  -- was transform function defined?
  if self.title_fnamemodify then
    local wincfg = vim.api.nvim_win_get_config(self.win.preview_winid)
    title = self.title_fnamemodify(title, wincfg and wincfg.width)
  end
  if entry.bufnr then
    title = string.format("buf %d: %s", entry.bufnr, title)
  end
  self.win:update_preview_title(" " .. title .. " ")
end

function Previewer.buffer_or_file:preview_buf_post(entry, min_winopts)
  if not self.win or not self.win:validate_preview() then return end

  if not self:preview_is_terminal() then
    -- set cursor highlights for line|col or tag
    self:set_cursor_hl(entry)

    -- syntax highlighting
    if self.syntax then
      if self.syntax_delay > 0 then
        local syntax_bufnr = self.preview_bufnr
        vim.defer_fn(function()
          if self.preview_bufnr == syntax_bufnr then
            self:do_syntax(entry)
            self:attach_snacks_image_inline()
          end
        end, self.syntax_delay)
      else
        self:do_syntax(entry)
        self:attach_snacks_image_inline()
      end
    end
  end

  self:update_title(entry)

  if entry.no_scrollbar then
    self.win:close_preview_scrollbar()
  else
    self.win:update_preview_scrollbar()
  end

  -- save the loaded entry so we can compare
  -- bufnr|path with the next entry. If equal
  -- we can skip loading the buffer again
  self.loaded_entry = entry

  -- Should we cache the current preview buffer?
  -- we cache only named buffers with valid path/uri
  if not entry.do_not_cache then
    self:cache_buffer(self.preview_bufnr, self:key_from_entry(entry), min_winopts)
  end
end

Previewer.help_tags = Previewer.buffer_or_file:extend()

function Previewer.help_tags:new(o, opts, fzf_win)
  Previewer.help_tags.super.new(self, o, opts, fzf_win)
  return self
end

function Previewer.help_tags:parse_entry(entry_str)
  local tag = entry_str:match("^[^%s]+")
  if not tag then
    return {}
  end
  local vimdoc = entry_str:match(string.format("[^%s]+$", utils.nbsp))
  local hregex = (function()
    -- lazy.nvim can generate helptags from markdown
    -- https://github.com/folke/lazy.nvim/blob/56a34a825b55e0e30cd9df0e055e428a13afd4aa/lua/lazy/help.lua#L35
    if package.loaded.lazy and vimdoc:match("%.md$") then
      local tagfile = path.join({ path.parent(vimdoc), "tags" })
      if uv.fs_stat(tagfile) then
        for line in io.lines(tagfile) do
          local res = line:match("^" .. vim.pesc(tag) .. "\t[^\t]+\t/(.*)")
          if res then return res end
        end
      end
    end
    return ([[\V*%s*]]):format(tag:gsub([[\]], [[\\]]))
  end)()
  return {
    htag = tag,
    hregex = hregex,
    path = vimdoc,
  }
end

function Previewer.help_tags:gen_winopts()
  local winopts = {
    wrap   = self.win.preview_wrap,
    number = false
  }
  return vim.tbl_extend("keep", winopts, self.winopts)
end

function Previewer.help_tags:set_cursor_hl(entry)
  pcall(api.nvim_win_call, self.win.preview_winid, function()
    -- start searching at line 1 in case we
    -- didn't reload the buffer (same file)
    api.nvim_win_set_cursor(0, { 1, 0 })
    fn.clearmatches()
    fn.search(entry.hregex, "W")
    if self.win.hls.search then
      fn.matchadd(self.win.hls.search, entry.hregex)
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
    wrap       = self.win.preview_wrap,
    cursorline = false,
    number     = false
  }
  return vim.tbl_extend("keep", winopts, self.winopts)
end

function Previewer.man_pages:new(o, opts, fzf_win)
  Previewer.man_pages.super.new(self, o, opts, fzf_win)
  self.filetype = "man"
  self.cmd = o.cmd or "man -c %s | col -bx"
  self.cmd = type(self.cmd) == "function" and self.cmd() or self.cmd
  return self
end

function Previewer.man_pages:parse_entry(entry_str)
  return require("fzf-lua.providers.manpages").manpage_sh_arg(entry_str)
end

function Previewer.man_pages:populate_preview_buf(entry_str)
  local entry = self:parse_entry(entry_str)
  local cmd = self.cmd:format(entry)
  if type(cmd) == "string" then cmd = { "sh", "-c", cmd } end
  local output, _ = utils.io_systemlist(cmd)
  local tmpbuf = self:get_tmp_buffer()
  -- vim.api.nvim_buf_set_option(tmpbuf, 'modifiable', true)
  vim.api.nvim_buf_set_lines(tmpbuf, 0, -1, false, output)
  vim.bo[tmpbuf].filetype = self.filetype
  self:set_preview_buf(tmpbuf)
  self.win:update_preview_scrollbar()
end

Previewer.marks = Previewer.buffer_or_file:extend()

function Previewer.marks:new(o, opts, fzf_win)
  Previewer.marks.super.new(self, o, opts, fzf_win)
  return self
end

function Previewer.marks:parse_entry(entry_str)
  local bufnr = nil
  local mark, lnum, col, filepath = entry_str:match("(.)%s+(%d+)%s+(%d+)%s+(.*)")
  if not mark then return {} end
  -- try to acquire position from sending buffer
  -- if this succeeds (line>0) the mark is inside

  -- nvim_buf_get_mark cannot get `'` mark correctly without curwin
  -- https://github.com/neovim/neovim/issues/29807
  local pos = api.nvim_win_call(self.win.src_winid, function()
    return vim.api.nvim_buf_get_mark(self.win.src_bufnr, mark)
  end)
  if pos and pos[1] > 0 then
    assert(pos[1] == tonumber(lnum))
    bufnr = self.win.src_bufnr
    filepath = api.nvim_buf_get_name(bufnr)
  end
  if #filepath > 0 then
    local ok, res = pcall(libuv.expand, filepath)
    if not ok then
      filepath = ""
    else
      filepath = res
    end
    filepath = path.relative_to(filepath, uv.cwd())
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
    local ok, res = pcall(libuv.expand, filepath)
    if ok then
      filepath = path.relative_to(res, uv.cwd())
    end
    if not uv.fs_stat(filepath) then
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

function Previewer.tags:set_cursor_hl(entry)
  if tonumber(entry.line) and entry.line > 0 then
    Previewer.buffer_or_file.set_cursor_hl(self, entry)
    return
  end
  -- pcall(vim.fn.clearmatches, self.win.preview_winid)
  pcall(api.nvim_win_call, self.win.preview_winid, function()
    -- start searching at line 1 in case we
    -- didn't reload the buffer (same file)
    api.nvim_win_set_cursor(0, { 1, 0 })
    fn.clearmatches()
    fn.search(entry.ctag, "W")
    if self.win.hls.search then
      fn.matchadd(self.win.hls.search, entry.ctag)
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
  -- Remove our scratch buffer from "listed" so it gets wiped
  self.listed_buffers[tostring(self.tmpbuf)] = nil
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

    -- Get a scratch buffer that doesn't wipe on hide (vs `self:get_tmp_buffer`)
    -- and mark it as "listed" so it doesn't get cleared on fzf's zero event
    self.tmpbuf = api.nvim_create_buf(false, true)
    self.listed_buffers[tostring(self.tmpbuf)] = true

    vim.api.nvim_buf_set_lines(self.tmpbuf, 0, -1, false, hl_groups)
    for k, v in ipairs(hl_groups) do
      local startPos = string.find(v, "xxx", 1, true) - 1
      local endPos = startPos + 3
      local hlgroup = string.match(v, "([^ ]*)%s+.*")
      pcall(vim.api.nvim_buf_add_highlight, self.tmpbuf, 0, hlgroup, k - 1, startPos, endPos)
    end
  end

  -- Preview buffer isn't set on init and after fzf's zero event
  if not self.preview_bufnr then
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
    if self.win.hls.search then
      fn.matchadd(self.win.hls.search, selected_hl)
    end
    self.orig_pos = api.nvim_win_get_cursor(0)
    utils.zz()
  end)
  self.win:update_preview_scrollbar()
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
  Previewer.quickfix.super.close(self)
end

function Previewer.quickfix:populate_preview_buf(entry_str)
  local nr = entry_str:match("[(%d+)]")
  if not nr or tonumber(nr) <= 0 then
    return
  end

  local qf_list = self.opts._is_loclist
      and vim.fn.getloclist(self.win.src_winid, { all = "", nr = tonumber(nr) })
      or vim.fn.getqflist({ all = "", nr = tonumber(nr) })
  if utils.tbl_isempty(qf_list) or utils.tbl_isempty(qf_list.items) then
    return
  end

  local lines = {}
  for _, e in ipairs(qf_list.items) do
    table.insert(lines, string.format("%s|%d col %d|%s",
      path.HOME_to_tilde(path.relative_to(
        vim.api.nvim_buf_get_name(e.bufnr), uv.cwd())),
      e.lnum, e.col, e.text))
  end
  self.tmpbuf = self:get_tmp_buffer()
  vim.api.nvim_buf_set_lines(self.tmpbuf, 0, -1, false, lines)
  vim.bo[self.tmpbuf].filetype = "qf"
  self:set_preview_buf(self.tmpbuf)
  self.win:update_preview_title(string.format(" %s: %s ", nr, qf_list.title))
  self.win:update_preview_scrollbar()
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
  if utils.tbl_isempty(entry) then return end
  self._is_vimL_command = false
  if entry.path == "<none>" then
    self._is_vimL_command = true
    entry.path = entry_str:match("[^:|]+│")
    local viml = entry_str:match("[^│]+$")
    local lines = vim.split(viml, "\n")
    local tmpbuf = self:get_tmp_buffer()
    vim.api.nvim_buf_set_lines(tmpbuf, 0, -1, false, lines)
    vim.bo[tmpbuf].filetype = "vim"
    self:set_preview_buf(tmpbuf)
    self:preview_buf_post(entry)
  else
    self.super.populate_preview_buf(self, entry_str)
  end
end

Previewer.keymaps = Previewer.buffer_or_file:extend()

function Previewer.autocmds:keymaps(o, opts, fzf_win)
  Previewer.autocmds.super.new(self, o, opts, fzf_win)
  return self
end

function Previewer.keymaps:parse_entry(entry_str)
  return path.keymap_to_entry(entry_str, self.opts)
end

function Previewer.keymaps:populate_preview_buf(entry_str)
  if not self.win or not self.win:validate_preview() then return end
  local entry = self:parse_entry(entry_str)
  if entry.vmap then
    -- keymap is vimL, there is no source file info
    -- so we display the vimL code instead
    local lines = utils.strsplit(entry.vmap:match("[^%s]+$"), "\n")
    local tmpbuf = self:get_tmp_buffer()
    vim.api.nvim_buf_set_lines(tmpbuf, 0, -1, false, lines)
    vim.bo[tmpbuf].filetype = "vim"
    self:set_preview_buf(tmpbuf)
    local title_fnamemodify = self.title_fnamemodify
    self.title_fnamemodify = nil
    -- hack entry.uri for title display
    self:preview_buf_post({ uri = string.format("%s:%s", entry.mode, entry.key) })
    self.title_fnamemodify = title_fnamemodify
    return
  end
  Previewer.autocmds.super.populate_preview_buf(self, entry_str)
end

Previewer.nvim_options = Previewer.base:extend()

function Previewer.nvim_options:new(o, opts, fzf_win)
  Previewer.nvim_options.super.new(self, o, opts, fzf_win)
  local paths = vim.fn.globpath(vim.o.rtp, "doc/options.txt", false, true)
  self.lines = vim.fn.readfile(paths[1])
end

function Previewer.nvim_options:gen_winopts()
  local winopts = {
    wrap = true,
    number = false,
    relativenumber = false,
    cursorline = false,
  }
  return vim.tbl_extend("keep", winopts, self.winopts)
end

function Previewer.nvim_options:get_help_text(tag)
  local tag_pattern = "%*'" .. tag .. "'%*"

  local start_index
  for i, line in ipairs(self.lines) do
    if line:match(tag_pattern) then
      start_index = i
      break
    end
  end
  if not start_index then
    return nil, nil
  end

  local heading_pattern = "%*'[^']*'%*"
  local end_index = #self.lines
  for j = start_index + 1, #self.lines do
    if self.lines[j]:match(heading_pattern) then
      end_index = j - 1
      break
    end
  end

  -- get lines between start and end
  local lines = {}
  for i = start_index, end_index do
    lines[#lines + 1] = self.lines[i]
  end

  return lines
end

function Previewer.nvim_options:parse_entry(entry_str)
  local parts = vim.split(entry_str, self.opts.separator)
  local option = vim.trim(parts[1])
  local value = vim.trim(parts[2])
  return { name = option, value = value }
end

function Previewer.nvim_options:populate_preview_buf(entry_str)
  if not self.win or not self.win:validate_preview() then return end
  local entry = self:parse_entry(entry_str)
  if utils.tbl_isempty(entry) then return end

  local header = {
    "Value: " .. entry.value,
    "",
    "",
  }

  local tmpbuf = self:get_tmp_buffer()
  vim.api.nvim_set_option_value("filetype", "help", { buf = tmpbuf })

  -- get_help_text might be slow. pcall to prevent errors when scrolling the list too quickly
  pcall(function()
    local lines = vim.list_extend(header, self:get_help_text(entry.name))
    vim.api.nvim_buf_set_lines(tmpbuf, 0, -1, false, lines)
    self:set_preview_buf(tmpbuf)
  end)

  self.win:update_preview_title(string.format(" %s ", entry.name))
  self.win:update_preview_scrollbar()
end

return Previewer
