-- cache entry for preview buf

---rename bufnr to buf?
---@class fzf-lua.BcacheEntry
---@field bufnr integer
---@field tick? integer
---@field min_winopts? boolean
---@field pos? [integer, integer]|true cached cursor positions

---@class fzf-lua.Bcache
---@field private entries table<any, fzf-lua.BcacheEntry> cached preview entries
---@field private buffers table<integer, fzf-lua.BcacheEntry> cached bufnrs
---@field private bufdel fun(buf: integer) callback to delete a buffer when evicted from cache
local M = {}
M.__index = M

---@param bufdel fun(buf: integer)
---@return fzf-lua.Bcache
function M.new(bufdel)
  return setmetatable({ entries = {}, buffers = {}, bufdel = bufdel }, M)
end

---Prioritize entry.cache_key since override self:key_from_entry is not allowed now
---@param entry fzf-lua.buffer_or_file.Entry
---@return string?
local key_from_entry = function(entry)
  -- entry.do_not_cache -> entry.cache_key=false?
  if entry.do_not_cache then return nil end
  return entry.cache_key
      or entry.bufnr and ("bufnr:%d"):format(entry.bufnr)
      or entry.uri
      or entry.path
end

---@param entry fzf-lua.buffer_or_file.Entry
---@return fzf-lua.BcacheEntry?
function M:get(entry)
  return self.entries[key_from_entry(entry)]
end

---cache only buffer have key_from_entry
---@param entry fzf-lua.buffer_or_file.Entry
---@param buf integer buf should be valid
---@param min_winopts boolean?
function M:set(entry, buf, min_winopts)
  local key = key_from_entry(entry)
  if not key then return end
  local cached = self.entries[key]
  if cached and cached.bufnr == buf then
    cached.tick = entry.tick
    return
  elseif cached then
    self.bufdel(cached.bufnr)
  end
  ---@type fzf-lua.BcacheEntry
  local newcache = {
    bufnr = buf,
    tick = entry.tick,
    min_winopts = min_winopts,
    pos = true, -- reset scroll position
  }
  self.entries[key] = newcache
  self.buffers[buf] = newcache
  -- remove buffer auto-delete since it's now cached
  vim.bo[buf].bufhidden = "hide"
end

---@param entry fzf-lua.buffer_or_file.Entry
---@return fzf-lua.BcacheEntry?, boolean? true: stale, false: valid, nil: not cached
function M:check(entry)
  local cached = self.entries[key_from_entry(entry)]
  return cached, cached and entry.tick ~= cached.tick or nil
end

---nop if update on a un-managed buf
---@param buf integer
---@param pos [integer, integer]|true set/reset cursor position
function M:update_pos(buf, pos)
  local cached = self.buffers[buf]
  if cached then cached.pos = pos end
end

---nop if update on a un-managed buf
---@param buf integer
function M:reset_pos(buf)
  self:update_pos(buf, true)
end

---@param buf integer
---@return [integer, integer]|true?
function M:get_pos(buf)
  local cached = self.buffers[buf]
  return cached and cached.pos or nil
end

function M:clear()
  for _, entry in pairs(self.entries) do
    self.bufdel(entry.bufnr)
  end
  self.entries = {}
  self.buffers = {}
end

return M
