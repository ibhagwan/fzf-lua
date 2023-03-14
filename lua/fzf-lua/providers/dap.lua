local core = require "fzf-lua.core"
local path = require "fzf-lua.path"
local utils = require "fzf-lua.utils"
local config = require "fzf-lua.config"
local actions = require "fzf-lua.actions"
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

  opts = config.normalize_opts(opts, config.globals.dap.commands)
  if not opts then return end

  local entries = {}
  for k, v in pairs(_dap) do
    if type(v) == "function" then
      table.insert(entries, k)
    end
  end

  opts.actions = {
    ["default"] = opts.actions and opts.actions.default or
        function(selected, _)
          _dap[selected[1]]()
        end,
  }

  opts.fzf_opts["--no-multi"] = ""

  core.fzf_exec(entries, opts)
end

M.configurations = function(opts)
  if not dap() then return end

  opts = config.normalize_opts(opts, config.globals.dap.configurations)
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
    ["default"] = opts.actions and opts.actions.default or
        function(selected, _)
          -- cannot run while in session
          if _dap.session() then return end
          local idx = selected and tonumber(selected[1]:match("(%d+).")) or nil
          if idx and opts._cfgs[idx] then
            _dap.run(opts._cfgs[idx])
          end
        end,
  }

  opts.fzf_opts["--no-multi"] = ""

  core.fzf_exec(entries, opts)
end

M.breakpoints = function(opts)
  if not dap() then return end
  local dap_bps = require "dap.breakpoints"

  opts = config.normalize_opts(opts, config.globals.dap.breakpoints)
  if not opts then return end

  -- so we can have accurate info on resume
  opts.fn_pre_fzf = function()
    opts._locations = dap_bps.to_qf_list(dap_bps.get())
  end

  -- run once to prevent opening an empty dialog
  opts.fn_pre_fzf()

  if vim.tbl_isempty(opts._locations) then
    utils.info("Breakpoint list is empty.")
    return
  end

  if not opts.cwd then opts.cwd = vim.loop.cwd() end

  opts.actions = vim.tbl_deep_extend("keep", opts.actions or {},
    {
      ["ctrl-x"] = opts.actions and opts.actions["ctrl-x"] or
          {
            function(selected, o)
              for _, e in ipairs(selected) do
                local entry = path.entry_to_file(e, o)
                if entry.bufnr > 0 and entry.line then
                  dap_bps.remove(entry.bufnr, entry.line)
                end
              end
            end,
            -- resume after bp deletion
            actions.resume
          }
    })

  local contents = function(cb)
    local entries = {}
    for _, entry in ipairs(opts._locations) do
      table.insert(entries, make_entry.lcol(entry, opts))
    end

    for i, x in ipairs(entries) do
      x = ("[%s] %s"):format(
      -- tostring(opts._locations[i].bufnr),
        utils.ansi_codes.yellow(tostring(opts._locations[i].bufnr)),
        make_entry.file(x, opts))
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

  if opts.fzf_opts["--header"] == nil then
    opts.fzf_opts["--header"] = vim.fn.shellescape((":: %s to delete a Breakpoint")
      :format(utils.ansi_codes.yellow("<Ctrl-x>")))
  end

  opts = core.set_fzf_field_index(opts, 3, opts._is_skim and "{}" or "{..-2}")

  core.fzf_exec(contents, opts)
end

M.variables = function(opts)
  if not dap() then return end

  opts = config.normalize_opts(opts, config.globals.dap.variables)
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

  opts = config.normalize_opts(opts, config.globals.dap.frames)
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
    ["default"] = opts.actions and opts.actions.default or
        function(selected, o)
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

  opts.fzf_opts["--no-multi"] = ""

  core.fzf_exec(entries, opts)
end

return M
