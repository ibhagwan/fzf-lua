local uv = vim.uv or vim.loop
local core = require "fzf-lua.core"
local utils = require "fzf-lua.utils"
local shell = require "fzf-lua.shell"
local config = require "fzf-lua.config"
local make_entry = require "fzf-lua.make_entry"

local _has_dap, _dap = nil, nil

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

  core.fzf_exec(entries, opts)
end

M.configurations = function(opts)
  if not dap() then return end

  opts = config.normalize_opts(opts, "dap.configurations")
  if not opts then return end

  local entries = {}
  opts._cfgs = {}
  for lang, lang_cfgs in pairs(_dap.configurations) do
    for _, cfg in ipairs(lang_cfgs) do
      opts._cfgs[#entries + 1] = cfg
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
      if idx and opts._cfgs[idx] then
        _dap.run(opts._cfgs[idx])
      end
    end,
  }

  core.fzf_exec(entries, opts)
end

M.breakpoints = function(opts)
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

  opts.func_async_callback = false
  opts.__fn_reload = opts.__fn_reload or function(_)
    return function(cb)
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
  end

  -- build the "reload" cmd and remove '-- {+}' from the initial cmd
  local contents, id = shell.reload_action_cmd(opts, "")
  opts.__reload_cmd = contents

  opts._fn_pre_fzf = function()
    shell.set_protected(id)
  end

  opts = core.set_header(opts, opts.headers or { "actions", "cwd" })
  opts = core.set_fzf_field_index(opts, "{3}", opts._is_skim and "{}" or "{..-2}")

  core.fzf_exec(contents, opts)
end

M.variables = function(opts)
  if not dap() then return end

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

  core.fzf_exec(entries, opts)
end

M.frames = function(opts)
  if not dap() then return end

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

  opts._frames = session.threads[session.stopped_thread_id].frames

  opts.actions = {
    ["enter"] = function(selected, o)
      local sess = _dap.session()
      if not sess or not sess.stopped_thread_id then return end
      local idx = selected and tonumber(selected[1]:match("(%d+).")) or nil
      if idx and o._frames[idx] then
        session:_frame_set(o._frames[idx])
      end
    end,
  }

  local entries = {}
  for i, f in ipairs(opts._frames) do
    table.insert(entries, ("%s. [%s] %s%s"):format(
      utils.ansi_codes.magenta(tostring(i)),
      utils.ansi_codes.green(f.name),
      f.source and f.source.name or "",
      f.line and ((":%d"):format(f.line)) or ""
    ))
  end

  core.fzf_exec(entries, opts)
end

return M
