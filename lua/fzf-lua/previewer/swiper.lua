local Object = require "fzf-lua.class"
local path = require "fzf-lua.path"
local utils = require "fzf-lua.utils"
local libuv = require "fzf-lua.libuv"
local shell = require "fzf-lua.shell"

local M = {}

---@class fzf-lua.previewer.SwiperBase: fzf-lua.Object,{}
M.base = Object:extend()

function M.base:new(o, opts)
  o = o or {}
  self.opts = opts;
  local ctx = utils.__CTX()
  assert(ctx, "CTX shoud not be nil")
  self.ctx_winid = ctx.winid
  self.ctx_bufnr = ctx.bufnr
  self.ctx_winopts = vim.deepcopy(ctx.winopts)
  assert(vim.api.nvim_buf_is_valid(self.ctx_bufnr), "origin buf is not valid")
  assert(vim.api.nvim_win_is_valid(self.ctx_winid), "origin win is not valid")
  assert(self.ctx_bufnr == vim.api.nvim_win_get_buf(self.ctx_winid), "win buf mismatch")
  self.ns = vim.api.nvim_create_namespace("fzf-lua.preview.swiper")
  self.picker = FzfLua.get_info().cmd
  if not utils.tbl_contains({
        "blines", "grep_curbuf", "lgrep_curbuf", "git_blame", "treesitter", "lsp_document_symbols"
      }, self.picker)
  then
    utils.warn("swiper previewer is not supported for '%s'", self.picker)
    return
  end
  return self
end

---@param opts table
---@return table
function M.base:setup_opts(opts)
  -- for `win:treesitter_attach.on_lines` max_col calc
  opts.winopts.preview.vertical = "up:0%"
  opts.winopts.preview.horizontal = "right:0%"
  opts.fzf_opts["--preview-window"] = "nohidden:right:0"
  opts.preview = self:preview_cmd()
  table.insert(opts._fzf_cli_args, "--bind=" .. libuv.shellescape("result:+" .. self:result_cmd()))
  -- NOTE: I don't feel we need the zero event, we just leave the cursor where it's at instead
  -- if utils.has(opts, "fzf", { 0, 40 }) then
  --   table.insert(opts._fzf_cli_args, "--bind=" .. libuv.shellescape("zero:+" .. self:zero_cmd()))
  -- end
  return opts
end

-- function M.base:zero_cmd(_)
--   return string.format("execute-silent:%s", shell.stringify_data(function(_, _, _)
--   end, self.opts))
-- end

---@param line string
---@param is_entry boolean?
---@return integer? lnum
---@return integer? col
---@return integer? col_valid_idx
---@return integer? col_offset
function M.base:parse_lnum_col(line, is_entry)
  local off = 0
  local prefix, lnum, col
  if self.picker == "git_blame" then
    prefix, lnum = line:match("^(.-)(%d+)%)")
    off = 1 + (lnum and #tostring(lnum) or 0)
  elseif is_entry then
    local parsed = path.entry_to_file(line, self.opts, self.opts._uri)
    lnum, col = parsed.line, parsed.col
  elseif self.picker == "blines" then
    prefix, lnum = line:match("^(.-)(%d+)")
    off = 1 + (lnum and #tostring(lnum) or 0)
  elseif self.picker:match("l?grep_curbuf") then
    prefix, lnum, col = line:match("^(.-)(%d+):(%d+):")
    if not lnum then
      -- col may be missing if search=""
      prefix, lnum = line:match("^(.-)(%d+):")
    end
    off = (lnum and #tostring(lnum) or 0) + (col and (#tostring(col) + 1) or 0)
  elseif self.picker == "treesitter" or self.picker == "lsp_document_symbols" then
    prefix = line:gsub("%s+$", ""):match("(.*%s+).+$")
    lnum, col = line:match("^.-(%d+):(%d+)%s")
    off = col and (1 - tonumber(col) - 1)
  end
  if lnum then
    -- use `vin.fn.strwidth` for proper adjustment of fzf's marker/pointer if unicode
    return tonumber(lnum), tonumber(col), prefix and vim.fn.strwidth(prefix) or 0, off or 0
  end
end

function M.base:preview_cmd()
  return shell.stringify_data(function(items, _, _)
    ---@type string?, string?, string?
    local entry, _, idx = unpack(items, 1, 3)
    if not tonumber(idx) then return end
    local lnum, col = self:parse_lnum_col(entry, true)
    if not lnum or lnum < 1 then return end
    vim.api.nvim_win_set_cursor(self.ctx_winid, { lnum, col or 0 })
    vim.wo[self.ctx_winid].cursorline = true
    vim.wo[self.ctx_winid].winhl = "CursorLine:" .. self.opts.hls.cursorline
    vim.defer_fn(function() self:highlight_matches() end, 10)
    if col and col > 0 then
      vim.hl.range(self.ctx_bufnr, self.ns, self.opts.hls.cursor,
        { lnum - 1, col - 1 }, { lnum - 1, col }, {})
    end
  end, self.opts, "{} {q} {n}")
end

function M.base:result_cmd()
  return string.format("execute-silent:%s", shell.stringify_data(function(_, _, _)
    vim.defer_fn(function() self:highlight_matches() end, 10)
  end, self.opts, "{q}"))
end

function M.base:highlight_matches()
  -- Credit to phanen@GitHub:
  -- https://github.com/ibhagwan/fzf-lua/issues/1754#issuecomment-2944053022
  local hl = function(start_row, start_col, end_row, end_col)
    assert(start_col >= 0 and end_col >= 0, "start_col and end_col must be non-negative")
    vim.hl.range(self.ctx_bufnr, self.ns, "IncSearch",
      { start_row, start_col }, { end_row, end_col }, {})
  end
  vim.api.nvim_buf_clear_namespace(self.ctx_bufnr, self.ns, 0, -1)
  local hlgroup = self.opts.fzf_colors.hl and self.opts.fzf_colors.hl[2]
  if type(hlgroup) == "table" then
    hlgroup = hlgroup[1]
  end
  local fg = (function()
    local hldef = vim.api.nvim_get_hl(0, { link = false, name = hlgroup })
    return hldef and hldef.fg
  end)()
  local fzf_win = utils.fzf_winobj().fzf_winid
  local fzf_buf = utils.fzf_winobj().fzf_bufnr
  if not vim.api.nvim_win_is_valid(fzf_win) or not vim.api.nvim_buf_is_valid(fzf_buf) then
    return
  end
  local height = vim.api.nvim_win_get_height(fzf_win)
  local off = vim.o.cmdheight + (vim.o.laststatus and 1 or 0)
  local lines = vim.o.lines
  local l_s = lines - height - off + 1
  local l_e = lines - off - 1
  local max_columns = vim.o.columns
  local buf_lines = vim.api.nvim_buf_get_lines(fzf_buf, 0, -1, false)
  for r = l_s, l_e do
    (function()
      local buf_lnum = r - l_s + 2
      local lnum, _, col_valid_idx, col_off = self:parse_lnum_col(buf_lines[buf_lnum])
      if not lnum or lnum < 1 then return end
      local state = { bytelen = 0 }
      for c = 1, max_columns do
        local ok, ret = pcall(vim.api.nvim__inspect_cell, 1, r, c)
        if not ok or not ret[1] then break end
        (function()
          local in_match = ret[2] and (ret[2].reverse or ret[2].foreground == fg)
          if in_match and not state.matchlen then
            if c < col_valid_idx then return end
            state.start_col = math.max(state.bytelen - col_valid_idx - col_off, 0)
            state.matchlen = ret[1]:len()
            return
          end
          if in_match then
            state.matchlen = state.matchlen + ret[1]:len()
            return
          end
          if state.matchlen then
            hl(lnum - 1, state.start_col, lnum - 1, state.start_col + state.matchlen)
            state.matchlen = nil
          end
        end)()
        state.bytelen = state.bytelen + vim.fn.strwidth(ret[1])
      end
    end)()
  end
end

function M.base:close()
  vim.api.nvim_buf_clear_namespace(self.ctx_bufnr, self.ns, 0, -1)
  -- on hide + change picker ctx will be nil
  local ctx = utils.__CTX()
  if not ctx then return end
  vim.wo[ctx.winid].winhl = ctx.winopts.winhl
  vim.wo[ctx.winid].cursorline = ctx.winopts.cursorline
  vim.api.nvim_win_set_cursor(ctx.winid, ctx.cursor)
  utils.zz()
end

---@class fzf-lua.previewer.Swiper : fzf-lua.previewer.SwiperBase,{}
---@field super fzf-lua.previewer.SwiperBase
M.default = M.base:extend()

function M.default:new(o, opts)
  M.default.super.new(self, o, opts)
  return self
end

return M
