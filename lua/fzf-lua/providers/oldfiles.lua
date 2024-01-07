local core = require("fzf-lua.core")
local config = require("fzf-lua.config")
local make_entry = require("fzf-lua.make_entry")

local M = {}

M._recent_buffers = {}
M._recent_counter = 0

vim.api.nvim_create_autocmd("BufEnter", {
  pattern = "*",
  callback = function()
    local buffer = vim.api.nvim_get_current_buf()
    local file = vim.api.nvim_buf_get_name(buffer)
    if file ~= "" then
      M._recent_buffers[file] = M._recent_counter
      M._recent_counter = M._recent_counter + 1
    end
  end,
})

M.oldfiles = function(opts)
  opts = config.normalize_opts(opts, "oldfiles")
  if not opts then
    return
  end

  local current_buffer = vim.api.nvim_get_current_buf()
  local current_file = vim.api.nvim_buf_get_name(current_buffer)

  local result_list = {}
  local result_map = {}
  local old_files_map = {}

  local function add_recent_file(file)
    if not file or #file == 0 or result_map[file] then
      return
    end

    local fs_stat = not opts.stat_file and true or vim.loop.fs_stat(file)
    if not fs_stat then
      return
    end

    table.insert(result_list, file)
    result_map[file] = true
  end

  for i, file in ipairs(vim.v.oldfiles) do
    if opts.show_current_file or file ~= current_file then
      add_recent_file(file)
      old_files_map[file] = i
    end
  end

  if opts.include_current_session then
    for buffer_file in pairs(M._recent_buffers) do
      if opts.show_current_file or buffer_file ~= current_file then
        add_recent_file(buffer_file)
      end
    end
  end

  table.sort(result_list, function(a, b)
    local a_recency = M._recent_buffers[a]
    local b_recency = M._recent_buffers[b]
    if a_recency == nil and b_recency == nil then
      local a_old = old_files_map[a]
      local b_old = old_files_map[b]
      if a_old == nil and b_old == nil then
        return a < b
      end
      if a_old == nil then
        return false
      end
      if b_old == nil then
        return true
      end
      return a_old < b_old
    end
    if a_recency == nil then
      return false
    end
    if b_recency == nil then
      return true
    end
    return b_recency < a_recency
  end)

  local contents = function(cb)
    local function add_entry(x, co)
      x = make_entry.file(x, opts)
      if not x then
        return
      end
      cb(x, function(err)
        coroutine.resume(co)
        if err then
          -- close the pipe to fzf, this
          -- removes the loading indicator in fzf
          cb(nil)
        end
      end)
      coroutine.yield()
    end

    -- run in a coroutine for async progress indication
    coroutine.wrap(function()
      local co = coroutine.running()

      for _, file in ipairs(result_list) do
        add_entry(file, co)
      end

      -- done
      cb(nil)
    end)()
  end

  -- for 'file_ignore_patterns' to work on relative paths
  opts.cwd = opts.cwd or vim.loop.cwd()
  opts = core.set_header(opts, opts.headers or { "cwd" })
  return core.fzf_exec(contents, opts)
end

return M
