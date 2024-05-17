local uv = vim.uv or vim.loop
local core = require "fzf-lua.core"
local utils = require "fzf-lua.utils"
local config = require "fzf-lua.config"
local make_entry = require "fzf-lua.make_entry"

local M = {}

local quickfix_run = function(opts, cfg, locations)
  if not locations then return {} end
  local results = {}

  opts = config.normalize_opts(opts, cfg)
  if not opts then return end

  if not opts.cwd then opts.cwd = uv.cwd() end

  for _, entry in ipairs(locations) do
    if entry.valid == 1 or not opts.only_valid then
      entry.text = entry.text:gsub("\r?\n", " ")
      table.insert(results, make_entry.lcol(entry, opts))
    end
  end

  local contents = function(cb)
    for _, x in ipairs(results) do
      x = make_entry.file(x, opts)
      if x then
        cb(x, function(err)
          if err then return end
          -- close the pipe to fzf, this
          -- removes the loading indicator in fzf
          cb(nil)
        end)
      end
    end
    cb(nil)
  end

  opts = core.set_fzf_field_index(opts)
  return core.fzf_exec(contents, opts)
end

M.quickfix = function(opts)
  local locations = vim.fn.getqflist()
  if utils.tbl_isempty(locations) then
    utils.info("Quickfix list is empty.")
    return
  end

  return quickfix_run(opts, "quickfix", locations)
end

M.loclist = function(opts)
  local locations = vim.fn.getloclist(0)

  for _, value in pairs(locations) do
    value.filename = vim.api.nvim_buf_get_name(value.bufnr)
  end

  if utils.tbl_isempty(locations) then
    utils.info("Location list is empty.")
    return
  end

  return quickfix_run(opts, "loclist", locations)
end


local qfstack_exec = function(opts, cfg, is_loclist)
  opts = config.normalize_opts(opts, cfg)
  if not opts then return end

  opts.fn_pre_fzf = function()
    opts.__history = vim.split(
      vim.fn.execute(is_loclist and "lhistory" or "chistory"), "\n")
  end
  opts.fn_pre_fzf()

  if utils.tbl_isempty(opts.__history) or opts.__history[2] == "No entries" then
    utils.info(string.format("No %s",
      is_loclist and "location lists" or "quickfix lists"))
    return
  end

  local contents = function(cb)
    coroutine.wrap(function()
      local co = coroutine.running()

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
  opts._is_loclist = true
  return qfstack_exec(opts, "loclist_stack", true)
end

return M
