-- context/info

local M = {}

---@type fzf-lua.Ctx?
local ctx

---@class fzf-lua.Ctx
---@field mode string
---@field bufnr integer
---@field bname string
---@field winid integer
---@field alt_bufnr integer
---@field tabnr integer
---@field tabh integer
---@field cursor integer[]
---@field line string
---@field curtab_wins { [string]: boolean }
---@field winopts { winhl: string, cursorline: boolean }
---@field bufmap? { [string]: boolean }
---@field buflist? integer[]

-- IMPORTANT: use the `__CTX` version that doesn't trigger a new context
---@return fzf-lua.Ctx?
M.get = function() return ctx end

M.reset = function() ctx = nil end

---conditionally update the context if fzf-lua
---interface isn't open
---@param opts? { includeBuflist?: boolean, buf?: integer|string, bufnr?: integer|string }
---@return fzf-lua.Ctx
M.refresh = function(opts)
  opts = opts or {}
  -- save caller win/buf context, ignore when fzf
  -- is already open (actions.sym_lsym|grep_lgrep)
  local winobj = require("fzf-lua.utils").fzf_winobj()
  if not ctx
      -- when called from the LSP module in "sync" mode when no results are found
      -- the fzf window won't open (e.g. "No references found") and the context is
      -- never cleared. The below condition validates the source window when the
      -- UI is not open (#907)
      or (not winobj and ctx.bufnr ~= vim.api.nvim_get_current_buf())
      -- we should never get here when fzf process is hidden unless the user requested
      -- not to resume or a different picker, i.e. hide files and open buffers
      or winobj and winobj:hidden()
  then
    ctx = {
      mode = vim.api.nvim_get_mode().mode,
      bufnr = vim.api.nvim_get_current_buf(),
      bname = vim.api.nvim_buf_get_name(0),
      winid = vim.api.nvim_get_current_win(),
      alt_bufnr = vim.fn.bufnr("#"),
      tabnr = vim.fn.tabpagenr(),
      tabh = vim.api.nvim_win_get_tabpage(0),
      cursor = vim.api.nvim_win_get_cursor(0),
      line = vim.api.nvim_get_current_line(),
      curtab_wins = (function()
        local ret = {}
        local wins = vim.api.nvim_tabpage_list_wins(0)
        for _, w in ipairs(wins) do
          ret[tostring(w)] = true
        end
        return ret
      end)(),
      winopts = {
        winhl = vim.wo.winhl,
        cursorline = vim.wo.cursorline,
      },
    }
  end
  -- perhaps a min impact optimization but since only
  -- buffers/tabs use these we only include the current
  -- list of buffers when requested
  if opts.includeBuflist and not ctx.buflist then
    -- also add a map for faster lookups than `utils.tbl_contains`
    -- TODO: is it really faster since we must use string keys?
    ctx.bufmap = {}
    ctx.buflist = vim.api.nvim_list_bufs()
    for _, b in ipairs(ctx.buflist) do
      ctx.bufmap[tostring(b)] = true
    end
  end
  -- custom bufnr from caller? (#1757)
  local bufnr = tonumber(opts.buf) or tonumber(opts.bufnr)
  if bufnr then
    ctx.bufnr = bufnr
    ctx.bname = vim.api.nvim_buf_get_name(bufnr)
  end
  return ctx
end

---@class fzf-lua.Info
---@field cmd string?
---@field mod string?
---@field fnc string?
---@field selected string?
---@field winobj fzf-lua.Win?
---@field last_query string?

---@type fzf-lua.Info
local info = {}

---@param filter table?
---@return fzf-lua.Info
M.info = function(filter)
  if filter and filter.winobj then
    info.winobj = require("fzf-lua.utils").fzf_winobj()
  end
  info.last_query = FzfLua.config.__resume_data and FzfLua.config.__resume_data.last_query
  return info
end

---@param x fzf-lua.Info
M.set_info = function(x)
  info = x
end

return M
