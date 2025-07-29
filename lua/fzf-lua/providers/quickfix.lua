local uv = vim.uv or vim.loop
local core = require "fzf-lua.core"
local utils = require "fzf-lua.utils"
local config = require "fzf-lua.config"
local make_entry = require "fzf-lua.make_entry"

local M = {}

local quickfix_run = function(opts, cfg)
  opts = config.normalize_opts(opts, cfg)
  if not opts then return end

  if not opts.cwd then opts.cwd = uv.cwd() end

  local function getlist()
    if opts.__locations then return nil end
    opts.__locations = opts.is_loclist and vim.fn.getloclist(utils.CTX().winid) or vim.fn.getqflist()
    if opts.is_loclist then
      for _, value in pairs(opts.__locations) do
        value.filename = vim.api.nvim_buf_get_name(value.bufnr)
      end
    end
  end

  -- Get the initial list
  getlist()

  if utils.tbl_isempty(opts.__locations) or opts.__locations[2] == "No entries" then
    utils.info("%s list is empty.", opts.is_loclist and "Location" or "Quickfix")
    return
  end

  local contents = function(cb)
    getlist()
    for _, loc in ipairs(opts.__locations) do
      (function()
        if opts.valid_only and loc.valid ~= 1 then return end
        loc.text = loc.text:gsub("\r?\n", " ")
        local entry = make_entry.lcol(loc, opts)
        entry = make_entry.file(entry, opts)
        if not entry then return end
        cb(string.format("[%s]%s%s",
            utils.ansi_codes.yellow(tostring(loc.bufnr)),
            utils.nbsp,
            entry),
          function(err)
            if err then return end
            -- close the pipe to fzf, this
            -- removes the loading indicator in fzf
            cb(nil)
          end)
      end)()
    end
    -- Nullify list so `getlist()` refreshes
    opts.__locations = nil
    cb(nil)
  end

  opts = core.set_fzf_field_index(opts)
  return core.fzf_exec(contents, opts)
end

M.quickfix = function(opts)
  return quickfix_run(opts, "quickfix")
end

M.loclist = function(opts)
  opts = opts or {}
  opts.is_loclist = true
  return quickfix_run(opts, "loclist")
end


local qfstack_exec = function(opts, cfg)
  opts = config.normalize_opts(opts, cfg)
  if not opts then return end

  opts.__gethist = function()
    opts.__history = vim.split(
      vim.fn.execute(opts.is_loclist and "lhistory" or "chistory"), "\n")
  end

  -- Get once to determine if empty
  opts.__gethist()

  if utils.tbl_isempty(opts.__history) or opts.__history[2] == "No entries" then
    utils.info("No %s", opts.is_loclist and "location lists" or "quickfix lists")
    return
  end

  local contents = function(cb)
    coroutine.wrap(function()
      local co = coroutine.running()

      -- Get the list again for accuracy on resume
      opts.__gethist()

      for _, line in ipairs(opts.__history) do
        local is_current = line:match("^>")
        local nr, name = line:match("list (%d+) of %d+; %d+ errors%s+(.*)$")
        if nr and tonumber(nr) > 0 then
          local entry = string.format("[%s] %s %s",
            utils.ansi_codes.yellow(nr), is_current
            and utils.ansi_codes.red(opts.marker)
            or " ", name)
          cb(entry, function(err)
            coroutine.resume(co)
            if err then cb(nil) end
          end)
          coroutine.yield()
        end
      end
      -- done
      cb(nil)
    end)()
  end

  return core.fzf_exec(contents, opts)
end

M.quickfix_stack = function(opts)
  return qfstack_exec(opts, "quickfix_stack")
end

M.loclist_stack = function(opts)
  opts = opts or {}
  opts.is_loclist = true
  return qfstack_exec(opts, "loclist_stack")
end

return M
