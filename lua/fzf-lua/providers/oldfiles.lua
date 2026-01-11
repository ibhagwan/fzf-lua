---@diagnostic disable-next-line: deprecated
local uv = vim.uv or vim.loop
local core = require "fzf-lua.core"
local utils = require "fzf-lua.utils"
local config = require "fzf-lua.config"
local make_entry = require "fzf-lua.make_entry"

local M = {}

---@param opts fzf-lua.config.Oldfiles|{}?
---@param globals string|(fzf-lua.Config|{})?
---@return thread?, string?, table?
M.oldfiles = function(opts, globals)
  ---@type fzf-lua.config.Oldfiles
  opts = config.normalize_opts(opts, globals or "oldfiles")
  if not opts then return end

  -- cwd implies we want `cwd_only=true`
  if opts.cwd and opts.cwd_only == nil then
    opts.cwd_only = true
  end

  -- current buffer as a header line
  if opts.include_current_session and not opts.ignore_current_buffer then
    utils.map_set(opts, "fzf_opts.--header-lines", 1)
  end

  local stat_fn = not opts.stat_file and function(_) return true end
      or type(opts.stat_file) == "function" and opts.stat_file
      or function(file)
        local stat = uv.fs_stat(file)
        return (not utils.path_is_directory(file, stat)
          -- FIFO blocks `fs_open` indefinitely (#908)
          and not utils.file_is_fifo(file, stat)
          and utils.file_is_readable(file))
      end

  local contents = function(cb)
    local curr_buf = utils.CTX().bufnr
    local curr_file = vim.api.nvim_buf_get_name(curr_buf)
    local sess_tbl = {}
    local sess_map = {}

    if opts.include_current_session then
      for _, buffer in ipairs(vim.split(vim.fn.execute(":buffers! t"), "\n")) do
        local bufnr = utils.tointeger(buffer:match("%s*(%d+)"))
        if bufnr then
          local file = vim.api.nvim_buf_get_name(bufnr)
          local fs_stat = stat_fn(file)
          if #file > 0 and fs_stat and (not opts.ignore_current_buffer or bufnr ~= curr_buf)
          then
            sess_map[file] = true
            table.insert(sess_tbl, { file = file, curbuf = bufnr == curr_buf })
          end
        end
      end
    end

    local function add_entry(x, co, force)
      x = make_entry.file(x,
        force and vim.tbl_deep_extend("force", {}, opts, { cwd_only = false }) or opts)
      if not x then return end
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

      for _, e in ipairs(sess_tbl) do
        -- 3rd arg forces addition of current buffer with cwd_only
        add_entry(e.file, co, e.curbuf)
      end

      -- local start = os.time(); for _ = 1,10000,1 do
      for _, file in ipairs(vim.v.oldfiles) do
        local fs_stat = stat_fn(file)
        if fs_stat and file ~= curr_file and not sess_map[file] then
          add_entry(file, co)
        end
      end
      -- end; print("took", os.time()-start, "seconds.")

      -- done
      cb(nil)
    end)()
  end

  -- for 'file_ignore_patterns' to work on relative paths
  opts.cwd = opts.cwd or utils.cwd()
  return core.fzf_exec(contents, opts)
end

---@param opts fzf-lua.config.History|{}?
---@return thread?, string?, table?
M.history = function(opts)
  return M.oldfiles(opts, "history")
end

return M
