local api = vim.api
local utils = require("fzf-lua.utils")

---@class fzf-lua.TSContext
---@field zindex? integer
---@field private _winids table<integer, integer> win to buf
---@field private _setup_opts TSContext.UserConfig
local M = {}

---@param opts TSContext.UserConfig
---@return boolean
function M.setup(opts)
  if M._setup then return true end
  if not package.loaded["treesitter-context"] then
    return false
  end
  -- Our temp nvim-treesitter-context config
  M._setup_opts = {}
  for k, v in pairs(opts) do
    M._setup_opts[k] = { v }
  end
  local config = require("treesitter-context.config")
  M._config = utils.tbl_deep_clone(config)
  for k, v in pairs(M._setup_opts) do
    v[2] = config[k]
    config[k] = v[1]
  end
  M._winids = {}
  M._setup = true
  return true
end

function M.deregister()
  if not M._setup then return end
  for winid, _ in pairs(M._winids) do
    M.close(winid)
  end
  local config = require("treesitter-context.config")
  for k, v in pairs(M._setup_opts) do
    config[k] = v[2]
  end
  M._config = nil
  M._winids = nil
  M._setup = nil
end

---@param winid integer
---@return boolean?
function M.is_attached(winid)
  if not M._setup then return false end
  return M._winids[winid] and true or false
end

---@param winid integer
function M.close(winid)
  if not M._setup then return end
  require("treesitter-context.render").close(winid)
  M._winids[winid] = nil
end

---@param winid integer
---@param bufnr integer
function M.toggle(winid, bufnr)
  if not M._setup then return end
  if M.is_attached(winid) then
    M.close(winid)
  else
    M.update(winid, bufnr)
  end
end

function M.inc_dec_maxlines(num, winid, bufnr)
  if not M._setup then return end
  local n = tonumber(num)
  if not n then return end
  local config = require("treesitter-context.config")
  local max_lines = config.max_lines or 0
  config.max_lines = math.max(0, max_lines + n)
  utils.info("treesitter-context `max_lines` set to %d.", config.max_lines)
  if M.is_attached(winid) then
    for _, t in ipairs({ 0, 20 }) do
      vim.defer_fn(function() M.update(winid, bufnr) end, t)
    end
  end
end

-- ts-context support global zindex config
-- but we must override zindex to ensure zindex order:
-- normal win's context < fzf win < (fzf) preview's context
---@param win integer
---@param zindex integer
local set_zindex = function(win, zindex)
  if win and api.nvim_win_is_valid(win) then
    utils.win_set_config(win, { zindex = zindex })
    -- noautocmd don't ignore WinResized/WinScrolled
    utils.wo[win].eventignorewin = "WinResized"
  end
end

---@alias TSContext.UserConfig table
---@param winid integer
---@param bufnr integer
---@param opts? TSContext.UserConfig
function M.update(winid, bufnr, opts)
  opts = opts or {}
  if not M.setup(opts) then return end
  assert(not api.nvim_win_is_valid(winid) or bufnr == api.nvim_win_get_buf(winid))
  local render = require("treesitter-context.render")
  local context_ranges, context_lines = require("treesitter-context.context").get(winid)
  if not context_ranges or #context_ranges == 0 then
    M.close(winid)
  else
    assert(context_lines)
    local function open()
      if api.nvim_buf_is_valid(bufnr) and api.nvim_win_is_valid(winid) then
        api.nvim_win_call(winid, function()
          render.open(winid, context_ranges, context_lines)
          M.window_contexts = M.window_contexts or
              utils.upvfind(render.open, "window_contexts")
          if not M.window_contexts then return end
          local window_context = M.window_contexts[winid]
          if not window_context or not M.zindex then return end
          set_zindex(window_context.context_winid, M.zindex)
          set_zindex(window_context.gutter_winid, M.zindex)
        end)
        M._winids[winid] = bufnr
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

return M
