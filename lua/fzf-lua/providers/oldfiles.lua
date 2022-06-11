local core = require "fzf-lua.core"
local config = require "fzf-lua.config"

local M = {}

M.oldfiles = function(opts)
  opts = config.normalize_opts(opts, config.globals.oldfiles)
  if not opts then return end

  local current_buffer = vim.api.nvim_get_current_buf()
  local current_file = vim.api.nvim_buf_get_name(current_buffer)
  local sess_tbl = {}
  local sess_map = {}

  if opts.include_current_session then
    for _, buffer in ipairs(vim.split(vim.fn.execute(':buffers! t'), "\n")) do
      local bufnr = tonumber(buffer:match('%s*(%d+)'))
      if bufnr then
        local file = vim.api.nvim_buf_get_name(bufnr)
        local fs_stat = not opts.stat_file and true or vim.loop.fs_stat(file)
        if #file>0 and fs_stat and bufnr ~= current_buffer then
          sess_map[file] = true
          table.insert(sess_tbl, file)
        end
      end
    end
  end

  local contents = function (cb)

    local function add_entry(x, co)
      x = core.make_entry_file(opts, x)
      if not x then return end
      cb(x, function(err)
        coroutine.resume(co)
        if err then
          -- close the pipe to fzf, this
          -- removes the loading indicator in fzf
          cb(nil, function() end)
        end
      end)
      coroutine.yield()
    end

    -- run in a coroutine for async progress indication
    coroutine.wrap(function()
      local co = coroutine.running()

      for _, file in ipairs(sess_tbl) do
        add_entry(file, co)
      end

      -- local start = os.time(); for _ = 1,10000,1 do
      for _, file in ipairs(vim.v.oldfiles) do
        local fs_stat = not opts.stat_file and true or vim.loop.fs_stat(file)
        if fs_stat and file ~= current_file and not sess_map[file] then
          add_entry(file, co)
        end
      end
      -- end; print("took", os.time()-start, "seconds.")

      -- done
      cb(nil, function() coroutine.resume(co) end)
      coroutine.yield()
    end)()

  end

  opts = core.set_header(opts, opts.headers or {"cwd"})
  return core.fzf_files(opts, contents)
end

return M
