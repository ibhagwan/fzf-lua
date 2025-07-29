---@diagnostic disable: undefined-field, param-type-mismatch
local uv = vim.uv or vim.loop
local core = require "fzf-lua.core"
local utils = require "fzf-lua.utils"
local config = require "fzf-lua.config"
local make_entry = require "fzf-lua.make_entry"

local _has_dap
local _dap

local M = {}

-- attempt to load 'nvim-dap' every call
-- in case the plugin was lazy loaded
local function dap()
  if _has_dap and _dap then return _dap end
  _has_dap, _dap = pcall(require, "dap")
  if not _has_dap or not _dap then
    utils.info("DAP requires 'mfussenegger/nvim-dap'")
    return false
  end
  return true
end

M.commands = function(opts)
  if not dap() then return end

  ---@type fzf-lua.config.DapCommands
  opts = config.normalize_opts(opts, "dap.commands")
  if not opts then return end

  local entries = {}
  for k, v in pairs(_dap) do
    if type(v) == "function" then
      table.insert(entries, k)
    end
  end

  opts.actions = {
    ["enter"] = function(selected, _)
      _dap[selected[1]]()
    end,
  }

  return core.fzf_exec(entries, opts)
end

M.configurations = function(opts)
  if not dap() then return end

  ---@type fzf-lua.config.DapConfigurations
  opts = config.normalize_opts(opts, "dap.configurations")
  if not opts then return end

  local entries = {}
  local cfgs = {}
  for lang, lang_cfgs in pairs(_dap.configurations) do
    for _, cfg in ipairs(lang_cfgs) do
      cfgs[#entries + 1] = cfg
      table.insert(entries, ("[%s] %s. %s"):format(
        utils.ansi_codes.green(lang),
        utils.ansi_codes.magenta(tostring(#entries + 1)),
        cfg.name
      ))
    end
  end

  opts.actions = {
    ["enter"] = function(selected, _)
      -- cannot run while in session
      if _dap.session() then return end
      local idx = selected and tonumber(selected[1]:match("(%d+).")) or nil
      if idx and cfgs[idx] then
        _dap.run(cfgs[idx])
      end
    end,
  }

  return core.fzf_exec(entries, opts)
end

M.breakpoints = function(opts)
  ---@type fzf-lua.config.DapBreakpoints
  opts = config.normalize_opts(opts, "dap.breakpoints")
  if not opts then return end

  if not dap() then return end
  local dap_bps = require "dap.breakpoints"

  if utils.tbl_isempty(dap_bps.get()) then
    utils.info("Breakpoint list is empty.")
    return
  end

  -- display relative paths by default
  if opts.cwd == nil then opts.cwd = uv.cwd() end

  local contents = function(cb)
    coroutine.wrap(function()
      local co = coroutine.running()
      local bps = dap_bps.to_qf_list(dap_bps.get())
      for _, b in ipairs(bps) do
        vim.schedule(function()
          local entry = make_entry.lcol(b, opts)
          entry = string.format("[%s]%s%s",
            -- tostring(opts._locations[i].bufnr),
            utils.ansi_codes.yellow(tostring(b.bufnr)),
            utils.nbsp,
            make_entry.file(entry, opts))
          cb(entry, function()
            coroutine.resume(co)
          end)
        end)
        coroutine.yield()
      end
      cb(nil)
    end)()
  end

  opts = core.set_fzf_field_index(opts, "{3}", opts._is_skim and "{}" or "{..-2}")
  return core.fzf_exec(contents, opts)
end

M.variables = function(opts)
  if not dap() then return end

  ---@type fzf-lua.config.DapVariables
  opts = config.normalize_opts(opts, "dap.variables")
  if not opts then return end

  local session = _dap.session()
  if not session then
    utils.info("No active DAP session.")
    return
  end

  local entries = {}
  for _, s in pairs(session.current_frame.scopes or {}) do
    if s.variables then
      for _, v in pairs(s.variables) do
        if v.type ~= "" and v.value ~= "" then
          table.insert(entries, ("[%s] %s = %s"):format(
            utils.ansi_codes.green(v.type),
            -- utils.ansi_codes.red(v.name),
            v.name,
            v.value
          ))
        end
      end
    end
  end

  return core.fzf_exec(entries, opts)
end

M.frames = function(opts)
  if not dap() then return end

  ---@type fzf-lua.config.DapFrames
  opts = config.normalize_opts(opts, "dap.frames")
  if not opts then return end

  local session = _dap.session()
  if not session then
    utils.info("No active DAP session.")
    return
  end

  if not session.stopped_thread_id then
    utils.info("Unable to switch frames unless stopped.")
    return
  end

  local frames = session.threads[session.stopped_thread_id].frames

  opts.previewer = {
    _ctor = function()
      local p = require("fzf-lua.previewer.builtin").buffer_or_file:extend()
      ---@param entry_str string
      ---@return fzf-lua.buffer_or_file.Entry
      function p:parse_entry(entry_str)
        local idx = entry_str and tonumber(entry_str:match("(%d+).")) or nil
        if not idx then return {} end
        local f = frames[idx]

        if (not f) or not f.source then
          return {}
        end
        if f.source.path then
          local path = f.source.path
          local fs_stat = vim.uv.fs_stat(path)
          if fs_stat and fs_stat.type == "file" then
            return {
              path = path,
              line = f.line,
              -- col = f.column,
            }
          end
        end
        if f.source.sourceReference ~= 0 then
          local source_ref = f.source.sourceReference
          local err, result = nil, nil
          session:request("source", { sourceReference = source_ref }, function(e, r)
            err = e
            result = r
          end)
          vim.wait(100, function()
            return err ~= nil or result ~= nil
          end)
          return {
            path = f.source.path,
            content = result and vim.split(result.content or "", "\n") or nil,
            line = f.line,
          }
        end

        return { path = f.source.path }
      end

      return p
    end,
  }

  opts.actions = {
    ["enter"] = function(selected, _)
      local sess = _dap.session()
      if not sess or not sess.stopped_thread_id then return end
      local idx = selected and tonumber(selected[1]:match("(%d+).")) or nil
      if idx and frames[idx] then
        session:_frame_set(frames[idx])
      end
    end,
  }

  local entries = {}
  for i, f in ipairs(frames) do
    table.insert(entries, ("%s. [%s] %s%s"):format(
      utils.ansi_codes.magenta(tostring(i)),
      utils.ansi_codes.green(f.name),
      f.source and f.source.name or "",
      f.line and ((":%d"):format(f.line)) or ""
    ))
  end

  return core.fzf_exec(entries, opts)
end

return M
