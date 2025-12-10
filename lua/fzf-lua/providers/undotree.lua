---@diagnostic disable-next-line: deprecated
local uv = vim.uv or vim.loop
local core = require "fzf-lua.core"
local path = require "fzf-lua.path"
local utils = require "fzf-lua.utils"
local shell = require "fzf-lua.shell"
local config = require "fzf-lua.config"
local native = require("fzf-lua.previewer.fzf")
local builtin = require("fzf-lua.previewer.builtin")

local M = {}

-- neovim/runtime/pack/dist/opt/nvim.undotree/lua/undotree.lua

--- @param buf integer
--- @return vim.fn.undotree.entry[]
--- @return integer
local function get_undotree_entries(buf)
  local undotree = vim.fn.undotree(buf)
  local entries = undotree.entries

  --Maybe: `:undo 0` and then `undotree` to get seq 0 time
  table.insert(entries, 1, { seq = 0, time = -1 })

  return entries, undotree.seq_cur
end

--- @param ent vim.fn.undotree.entry[]
--- @param _tree vim.undotree.tree?
--- @param _last integer?
--- @return vim.undotree.tree
local function treefy(ent, _tree, _last)
  local tree = _tree or {}
  local last = _last or nil

  for idx, v in ipairs(ent) do
    local seq = v.seq

    if last then
      table.insert(tree[last].child, seq)
    else
      assert(idx == 1 and not _tree)
    end

    tree[seq] = { child = {}, time = v.time }
    if v.alt then
      assert(last)
      treefy(v.alt, tree, last)
    end
    last = seq
  end

  return tree
end

--- Returns the relative time from a given time
--- as ... ago
---@param time number
---@return string
function reltime(time)
  if time == -1 then
    return "origin"
  end
  local delta = os.time() - time
  local tpl = {
    { 1,             60,                "just now",     "just now" },
    { 60,            3600,              "a minute ago", "%d minutes ago" },
    { 3600,          3600 * 24,         "an hour ago",  "%d hours ago" },
    { 3600 * 24,     3600 * 24 * 7,     "yesterday",    "%d days ago" },
    { 3600 * 24 * 7, 3600 * 24 * 7 * 4, "a week ago",   "%d weeks ago" },
  }
  for _, v in ipairs(tpl) do
    if delta < v[2] then
      local value = math.floor(delta / v[1] + 0.5)
      return value == 1 and v[3] or v[4]:format(value)
    end
  end
  if os.date("%Y", time) == os.date("%Y") then
    ---@diagnostic disable-next-line: return-type-mismatch
    return os.date("%b %d", time) ---@type string
  end
  ---@diagnostic disable-next-line: return-type-mismatch
  return os.date("%b %d, %Y", time) ---@type string
end

---@diagnostic disable-next-line: unused
--- @param time integer
--- @return string
local function undo_fmt_time(time)
  if time == -1 then
    return "origin"
  end

  local diff = os.time() - time

  if diff >= 100 then
    if diff < (60 * 60 * 12) then
      return os.date("%H:%M:%S", time) --[[@as string]]
    else
      return os.date("%Y/%m/%d %H:%M:%S", time) --[[@as string]]
    end
  else
    return ("%d second%s ago"):format(diff, diff == 1 and "" or "s")
  end
end

---@diagnostic disable-next-line: duplicate-type
--- @class (partial) vim.undotree.tree.entry
--- @field traversed? boolean

--- @param opts fzf-lua.config.Undotree
--- @param cb function
--- @param tree vim.undotree.tree
--- @param nodes integer[]?
--- @param reverse boolean
--- @param parents integer[]?
--- @param prefix string?
local function draw_tree(opts, cb, tree, nodes, reverse, parents, prefix)
  if not nodes or #nodes == 0 then return end
  local is_root = nodes[1] == 0
  prefix = prefix or ""
  parents = parents or {}
  table.sort(nodes)
  for i, n in ipairs(nodes) do
    local v = tree[n]
    local is_last = i == #nodes
    assert(not v.traversed)
    v.traversed = true
    -- TODO: IMHO the latter (flattened single) is nicer
    -- local is_single = #parents == 1 and #nodes == 1
    local is_single = #nodes == 1
    local leaf = reverse and "┌" or "└"
    local node = utils.ansi_codes[opts.hls.dir_part](
          prefix .. ((is_root or is_single) and "" or is_last and leaf .. "── " or "├── "))
        .. utils.ansi_codes[opts.hls.buf_name](tostring(n))
    -- local w = 64 + string.len(node) - vim.fn.strwidth(node)
    cb(n, string.format("%s\t\t%s", node,
      utils.ansi_codes[opts.hls.path_linenr](reltime(v.time))))
    draw_tree(opts, cb, tree, v.child, reverse, nodes,
      prefix .. ((is_root or is_single) and "" or is_last and "    " or "│   "))
  end
end

---@param opts fzf-lua.config.Undotree|{}?
---@return thread?, string?, table?
M.undotree = function(opts)
  ---@type fzf-lua.config.Undotree
  opts = config.normalize_opts(opts, "undotree")
  if not opts then return end

  local contents = function(cb)
    coroutine.wrap(function()
      local co = coroutine.running()
      local entries, curseq = get_undotree_entries(utils.CTX().bufnr)
      local tree = treefy(entries)
      local count = 0

      local function add_entry(seq, e)
        count = count + 1
        if seq == curseq then
          opts.__locate_pos = count
        end
        cb(e, function(err)
          coroutine.resume(co)
          if err then cb(nil) end
        end)
        coroutine.yield()
      end

      local reverse = utils.map_get(opts, "fzf_opts.--layout") == "default"
      draw_tree(opts, add_entry, tree, { 0 }, reverse)

      cb(nil) -- EOF
    end)()
  end

  return core.fzf_exec(contents, opts)
end

--- @class fzf-lua.UndoInfo
--- @field buf integer buffer id
--- @field changedtick integer last change tick
--- @field tmp_buf integer tmp buffer id
--- @field tmp_file string tmp file path
--- @field tmp_undo string tmp undo file path

---
--- Credit to snacks.nvim:
--- copies the buffer to a temporary file and load the undo history.
--- This is done to prevent the current buffer from being modified,
--- also better for performance as it won't trigger LSP change tracking
---
--- @param buf integer buffer id
--- @return fzf-lua.UndoInfo
local function load_undo_buf(buf)
  local info = M._undoinfo or {}
  M._undoinfo = info
  -- do nothing if buffer is already loaded and unchanged
  local changedtick = vim.b[buf].changedtick
  if info.buf == buf and info.changedtick == changedtick then
    return info
  end
  -- always create a new tmp buffer
  if info.tmp_buf and vim.api.nvim_buf_is_valid(info.tmp_buf) then
    vim.api.nvim_buf_delete(info.tmp_buf, { force = true })
  end
  info.buf = buf
  info.changedtick = changedtick
  info.tmp_file = path.join({ path.parent(utils.tempname()), "fzf-lua-undo" })
  info.tmp_undo = info.tmp_file .. ".undo"
  info.tmp_buf = vim.fn.bufadd(info.tmp_file)
  vim.bo[info.tmp_buf].swapfile = false
  vim.fn.writefile(vim.api.nvim_buf_get_lines(buf, 0, -1, false), info.tmp_file)
  vim.fn.bufload(info.tmp_buf)
  vim.api.nvim_buf_call(buf, function()
    vim.cmd("silent wundo! " .. info.tmp_undo)
  end)
  vim.api.nvim_buf_call(info.tmp_buf, function()
    ---@diagnostic disable-next-line: param-type-mismatch
    pcall(vim.cmd, "silent rundo " .. info.tmp_undo)
  end)
  return info
end

local function unload_undo_buf()
  local info = M._undoinfo
  if not info then return end
  assert(info.tmp_buf)
  assert(info.tmp_file)
  assert(info.tmp_undo)
  if vim.api.nvim_buf_is_valid(info.tmp_buf) then
    vim.api.nvim_buf_delete(info.tmp_buf, { force = true })
  end
  if uv.fs_stat(info.tmp_file) then vim.fn.delete(info.tmp_file) end
  if uv.fs_stat(info.tmp_undo) then vim.fn.delete(info.tmp_undo) end
  M._undoinfo = nil
end

--- @param buf integer buffer id
--- @param seq number
--- @param diff_opts? vim.text.diff.Opts
--- @return string[], integer
local function undo_diff(buf, seq, diff_opts)
  local info = load_undo_buf(buf)
  local file = vim.api.nvim_buf_get_name(buf)

  ---@diagnostic disable-next-line: deprecated
  local diff_fn = vim.text and vim.text.diff or vim.diff

  ---@type string[], string[]
  local before, after = {}, {}

  utils.eventignore(function()
    vim.api.nvim_buf_call(info.tmp_buf, function()
      -- state after the undo
      vim.cmd("noautocmd silent undo " .. tostring(seq))
      after = vim.api.nvim_buf_get_lines(0, 0, -1, false)
      -- state before the undo
      vim.cmd("noautocmd silent undo")
      before = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    end)
  end)

  local diff = diff_fn(table.concat(before, "\n") .. "\n",
    table.concat(after, "\n") .. "\n",
    diff_opts) --[[@as string]]
  local lines = vim.split(diff, "\n")
  table.remove(lines)
  file = path.relative_to(file, utils.cwd())
  table.insert(lines, 1, string.format("diff --git a/%s b/%s", file, file))
  table.insert(lines, 2, string.format("--- a/%s", file))
  table.insert(lines, 3, string.format("+++ b/%s", file))
  return lines, info.tmp_buf
end


--- @class fzf-lua.previewer.Undotree : fzf-lua.previewer.Builtin,{}
--- @field super fzf-lua.previewer.Builtin,{}
--- @field diff_buf integer
--- @field diff_opts vim.text.diff.Opts
--- @field show_buf boolean? # show original buffer instead of diff
M.builtin = builtin.base:extend()

---@diagnostic disable-next-line: unused
---@return boolean
function M.builtin:should_clear_preview(_)
  return false
end

function M.builtin:gen_winopts()
  local winopts = {
    wrap       = self.win.preview_wrap,
    cursorline = false,
  }
  return vim.tbl_extend("keep", winopts, self.winopts)
end

---@param o fzf-lua.config.UndotreePreviewer
---@param opts fzf-lua.config.Undotree
---@return fzf-lua.previewer.Undotree
function M.builtin:new(o, opts)
  M.builtin.super.new(self, o, opts)
  self.buf = utils.CTX().bufnr
  self.file = path.relative_to(vim.api.nvim_buf_get_name(self.buf), utils.cwd())
  self.diff_opts = o.diff_opts
  self.show_buf = o.show_buf
  return self
end

function M.builtin:close()
  if self.diff_buf and vim.api.nvim_buf_is_valid(self.diff_buf) then
    vim.api.nvim_buf_delete(self.diff_buf, { force = true })
  end
  unload_undo_buf()
  M.builtin.super.close(self)
end

function M.builtin:toggle_undo_diff()
  self.show_buf = not self.show_buf
  self.win:redraw_preview()
end

function M.builtin:populate_preview_buf(entry_str)
  local seq = assert(tonumber(entry_str:match("%d+")))
  local lines, buf = undo_diff(self.buf, seq, self.diff_opts)
  if seq > 0 and not self.show_buf then
    if not self.diff_buf or not vim.api.nvim_buf_is_valid(self.diff_buf) then
      self.diff_buf = self:get_tmp_buffer()
      self.diff_buf = vim.api.nvim_create_buf(false, true)
      vim.bo[self.diff_buf].modeline = true
      vim.bo[self.diff_buf].modifiable = true
      vim.bo[self.diff_buf].bufhidden = ""
      vim.bo[self.diff_buf].ft = "diff"
    end
    vim.api.nvim_buf_set_lines(self.diff_buf, 0, -1, false, lines)
    self:set_preview_buf(self.diff_buf, nil, true)
  else
    utils.eventignore(function()
      vim.api.nvim_buf_call(buf, function()
        vim.cmd("noautocmd silent undo " .. tostring(seq))
      end)
    end)
    vim.bo[buf].ft = vim.bo[self.buf].ft
    self:set_preview_buf(buf, nil, true)
  end
  self.win:update_preview_title(self.file)
  self.win:update_preview_scrollbar()
end

---@class fzf-lua.previewer.UndotreeNative: fzf-lua.previewer.Fzf,{}
---@field super fzf-lua.previewer.Fzf
M.native = native.base:extend()

---@param o fzf-lua.config.UndotreePreviewer
---@param opts fzf-lua.config.Undotree
---@return fzf-lua.previewer.UndotreeNative
function M.native:new(o, opts)
  M.native.super.new(self, o, opts)
  setmetatable(self, M.native)
  self.buf = utils.CTX().bufnr
  local pager = opts.preview_pager == nil and o.pager or opts.preview_pager
  if type(pager) == "function" then pager = pager() end
  local cmd = pager and pager:match("[^%s]+") or nil
  if cmd and vim.fn.executable(cmd) == 1 then self.pager = pager end
  self.diff_opts = o.diff_opts
  return self
end

function M.native:close()
  unload_undo_buf()
  M.native.super.close(self)
end

function M.native:cmdline(o)
  o = o or {}
  local act = shell.stringify_data(function(entries, _, _)
    if not entries[1] then return shell.nop() end
    local seq = assert(utils.tointeger(entries[1]:match("%d+")))
    local lines = undo_diff(self.buf, seq, self.diff_opts)
    return table.concat(lines, "\r\n")
  end, self.opts, "{}")
  if self.pager then
    act = act .. " | " .. utils._if_win_normalize_vars(self.pager)
  end
  return act
end

return M
