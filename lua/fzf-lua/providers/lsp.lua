if not pcall(require, "fzf") then
  return
end

local raw_action = require("fzf.actions").raw_action
local core = require "fzf-lua.core"
local utils = require "fzf-lua.utils"
local config = require "fzf-lua.config"
local actions = require "fzf-lua.actions"

local M = {}

local jump_to_location = function(opts, result)

  local winid = vim.api.nvim_get_current_win()
  if opts.winid ~= winid then
    -- utils.send_ctrl_c()
    vim.api.nvim_win_close(0, false)
  end
  return vim.lsp.util.jump_to_location(result)
end

local function location_handler(opts, cb, _, result)
  result = vim.tbl_islist(result) and result or {result}
  -- Jump immediately if there is only one location
  if opts.jump_to_single_result and #result == 1 then
    jump_to_location(opts, result[1])
  end
  local items = vim.lsp.util.locations_to_items(result)
  for _, entry in ipairs(items) do
    entry = core.make_entry_lcol(opts, entry)
    entry = core.make_entry_file(opts, entry)
    if entry then
      cb(entry, function(err)
        if err then return end
      end)
    end
  end
end

local function symbol_handler(opts, cb, _, result)
  result = vim.tbl_islist(result) and result or {result}
  local items = vim.lsp.util.symbols_to_items(result)
  for _, entry in ipairs(items) do
    if opts.ignore_filename then
      entry.filename = opts.filename
    end
    entry = core.make_entry_lcol(opts, entry)
    entry = core.make_entry_file(opts, entry)
    if entry then
      cb(entry, function(err)
        if err then return end
      end)
    end
  end
end

local function code_action_handler(opts, cb, _, code_actions)
  if not opts.code_actions then opts.code_actions = {} end
  local i = utils.tbl_length(opts.code_actions) + 1
  for _, action in ipairs(code_actions) do
    local text = string.format("%s %s",
      utils.ansi_codes.magenta(string.format("%d:", i)),
      action.title)
    opts.code_actions[tostring(i)] = action
    cb(text, function(err)
      if err then return end
    end)
    i = i + 1
  end
end

local function diagnostics_handler(opts, cb, _, entry)
  local type = entry.type
  entry = core.make_entry_lcol(opts, entry)
  entry = core.make_entry_file(opts, entry)
  if not entry then return end
  if opts.lsp_icons and opts.cfg.icons[type] then
    local severity = opts.cfg.icons[type]
    local icon = severity.icon
    if opts.color_icons then
      icon = utils.ansi_codes[severity.color or "dark_grey"](icon)
    end
    entry = icon .. utils.nbsp .. utils.nbsp .. entry
  end
  cb(entry, function(err)
    if err then return end
  end)
end

local function wrap_handler(handler)
  return function(err, method, result, client_id, bufnr, lspcfg)
    local ret
    if err then
      ret = err.message
      utils.err(string.format("Error executing '%s': %s",
        handler.method, err.message or "nil"))
      utils.send_ctrl_c()
    elseif not result or vim.tbl_isempty(result) then
      ret = utils.info(string.format('No %s found', string.lower(handler.label)))
      utils.send_ctrl_c()
    else
      ret = handler.target(err, method, result, client_id, bufnr, lspcfg)
    end
    return ret
  end
end

local function wrap_request_all(handler)
  return function(result)
    local ret
    local flattened_results = {}
    for _, server_results in pairs(result) do
      if server_results.result then
        vim.list_extend(flattened_results, server_results.result)
      end
    end
    if #flattened_results == 0 then
      ret = utils.info(string.format('No %s found', string.lower(handler.label)))
      utils.send_ctrl_c()
    else
      ret = handler.target(nil, nil, flattened_results)
    end
    return ret
  end
end

local function set_lsp_fzf_fn(opts)

  -- we must make the params here while we're on
  -- our current buffer window, anything inside
  -- fzf_fn is run while fzf term is open
  opts.bufnr = opts.bufnr or vim.api.nvim_get_current_buf()
  opts.winid = opts.winid or vim.api.nvim_get_current_win()
  opts.filename = vim.api.nvim_buf_get_name(opts.bufnr)
  if not opts.lsp_params then
    opts.lsp_params = vim.lsp.util.make_position_params()
    opts.lsp_params.context = { includeDeclaration = true }
  end

  -- function async params override global config
  if opts.async == nil and opts.sync == nil
    and opts.async_or_timeout ~= true then
      opts.async = false
  end

  if opts.sync or opts.async == false then
    local timeout = 5000
    if type(opts.async_or_timeout) == "number" then
      timeout = opts.async_or_timeout
    end
    local lsp_results, err = vim.lsp.buf_request_sync(opts.bufnr,
        opts.lsp_handler.method, opts.lsp_params, timeout)
    if err then
      utils.err(string.format("Error executing '%s': %s",
        opts.lsp_handler.method, err.message or "nil"))
    else
      local results = {}
      local cb = function(text) table.insert(results, text) end
      for _, v in pairs(lsp_results) do
        if v.result then
          opts.lsp_handler.handler(opts, cb, opts.lsp_handler.method, v.result)
        end
      end
      if vim.tbl_isempty(results) then
        utils.info(string.format('No %s found', string.lower(opts.lsp_handler.label)))
      elseif not (opts.jump_to_single_result and #results == 1) then
        opts.fzf_fn = results
      end
    end
    return opts
  end

  opts.fzf_fn = function (cb)
    coroutine.wrap(function ()
      local co = coroutine.running()

      -- callback when a location is found
      -- we use this passthrough so we can send the
      -- coroutine variable (not used rn but who knows?)
      opts.lsp_handler.target = function(_, _, result)
        opts.lsp_handler.handler(opts, cb, co, result)
        -- close the pipe to fzf, this
        -- removes the loading indicator in fzf
        utils.delayed_cb(cb)
        return
      end

      -- local cancel_all = vim.lsp.buf_request_all(opts.bufnr,
        -- opts.lsp_handler.method, opts.lsp_params,
        -- wrap_request_all(opts.lsp_handler))

      local _, cancel_all = vim.lsp.buf_request(opts.bufnr,
        opts.lsp_handler.method, opts.lsp_params,
        wrap_handler(opts.lsp_handler))

      -- cancel all remaining LSP requests
      -- once the user made their selection
      -- or closed the fzf popup
      opts.post_select_cb = function()
        if cancel_all then cancel_all() end
      end

      -- coroutine.yield()

    end)()
  end

  return opts
end

local normalize_lsp_opts = function(opts, cfg)
  opts = config.normalize_opts(opts, cfg)

  if not opts.cwd then opts.cwd = vim.loop.cwd() end
  if not opts.prompt then
    opts.prompt = opts.lsp_handler.label .. cfg.prompt
  end

  opts.cfg = nil
  opts.bufnr = nil
  opts.winid = nil
  opts.filename = nil
  opts.lsp_params = nil
  opts.code_actions = nil

  return opts
end

local function fzf_lsp_locations(opts)
  opts = normalize_lsp_opts(opts, config.globals.lsp)
  opts = core.set_fzf_line_args(opts)
  opts = set_lsp_fzf_fn(opts)
  if not opts.fzf_fn then return end
  return core.fzf_files(opts)
end

-- define the functions for wrap_module_fncs
M.references = function(opts)
  return fzf_lsp_locations(opts)
end

M.definitions = function(opts)
  return fzf_lsp_locations(opts)
end

M.declarations = function(opts)
  return fzf_lsp_locations(opts)
end

M.typedefs = function(opts)
  return fzf_lsp_locations(opts)
end

M.implementations = function(opts)
  return fzf_lsp_locations(opts)
end

M.document_symbols = function(opts)
  if not opts then opts = {} end
  -- TODO: filename hiding
  -- since single document
  opts.ignore_filename = true
  return fzf_lsp_locations(opts)
end

M.workspace_symbols = function(opts)
  opts = normalize_lsp_opts(opts, config.globals.lsp)
  opts.lsp_params = {query = ''}
  opts = core.set_fzf_line_args(opts)
  opts = set_lsp_fzf_fn(opts)
  if not opts.fzf_fn then return end
  return core.fzf_files(opts)
end

M.code_actions = function(opts)
  opts = normalize_lsp_opts(opts, config.globals.lsp)
  opts.lsp_params = vim.lsp.util.make_range_params()
  opts.lsp_params.context = {
    diagnostics = vim.lsp.diagnostic.get_line_diagnostics()
  }

  -- "apply action" as default function
  if not opts.actions then opts.actions = {} end
  opts.actions.default = (function(selected)
    local idx = selected[2]:match("(%d+)")
    local action = opts.code_actions[idx]
    if not action then return end
    if action.edit or type(action.command) == 'table' then
      if action.edit then
        vim.lsp.util.apply_workspace_edit(action.edit)
      end
      if type(action.command) == 'table' then
        vim.lsp.buf.execute_command(action.command)
      end
    else
      vim.lsp.buf.execute_command(action)
    end
  end)

  opts.nomulti = true
  opts.preview_window = 'right:0'
  opts._fzf_cli_args = "--delimiter=':'"
  opts = set_lsp_fzf_fn(opts)

  -- error or no sync request no results
  if not opts.fzf_fn then return end

  coroutine.wrap(function ()

    local selected = core.fzf(opts, opts.fzf_fn,
      core.build_fzf_cli(opts),
      config.winopts(opts))

    if opts.post_select_cb then
      opts.post_select_cb()
    end

    if not selected then return end

    actions.act(opts.actions, selected)

  end)()

end

local convert_diagnostic_type = function(severity)
  -- convert from string to int
  if type(severity) == "string" then
    -- make sure that e.g. error is uppercased to Error
    return vim.lsp.protocol.DiagnosticSeverity[severity:gsub("^%l", string.upper)]
  end
  -- otherwise keep original value, incl. nil
  if type(severity) ~= "number" then return nil end
  return severity
end

local filter_diag_severity = function(opts, severity)
  if opts.severity_exact ~= nil then
    return opts.severity_exact == severity
  elseif opts.severity ~= nil then
    return severity <= opts.severity
  elseif opts.severity_bound ~= nil then
    return severity >= opts.severity_bound
  else
    return true
  end
end

M.diagnostics = function(opts)
  opts = normalize_lsp_opts(opts, config.globals.lsp)

  local lsp_clients = vim.lsp.buf_get_clients(0)
  if #lsp_clients == 0 then
    utils.info("LSP: no client attached")
    return
  end

  opts.winid = vim.api.nvim_get_current_win()
  local lsp_type_diagnostic = vim.lsp.protocol.DiagnosticSeverity
  local current_buf = vim.api.nvim_get_current_buf()

  -- save this so handler can get the lsp icon
  opts.cfg = config.globals.lsp

  -- hint         = 4
  -- information  = 3
  -- warning      = 2
  -- error        = 1
  -- severity:        keep any equal or more severe (lower)
  -- severity_exact:  keep any matching exact severity
  -- severity_bound:  keep any equal or less severe (higher)
  opts.severity = convert_diagnostic_type(opts.severity)
  opts.severity_exact = convert_diagnostic_type(opts.severity_exact)
  opts.severity_bound = convert_diagnostic_type(opts.severity_bound)

  local validate_severity = 0
  for _, v in ipairs({opts.severity_exact, opts.severity, opts.severity_bound}) do
    if v ~= nil then
      validate_severity = validate_severity + 1
    end
    if validate_severity > 1 then
      utils.warn("Invalid severity params, ignoring severity filters")
      opts.severity, opts.severity_exact, opts.severity_bound = nil, nil, nil
    end
  end

  local preprocess_diag = function(diag, bufnr)
    local filename = vim.api.nvim_buf_get_name(bufnr)
    local start = diag.range['start']
    local finish = diag.range['end']
    local row = start.line
    local col = start.character

    local buffer_diag = {
      bufnr = bufnr,
      filename = filename,
      lnum = row + 1,
      col = col + 1,
      start = start,
      finish = finish,
      -- remove line break to avoid display issues
      text = vim.trim(diag.message:gsub("[\n]", "")),
      type = lsp_type_diagnostic[diag.severity] or lsp_type_diagnostic[1]
    }
    return buffer_diag
  end

  opts.fzf_fn = function (cb)
    coroutine.wrap(function ()
      local co = coroutine.running()

      local buffer_diags = opts.diag_all and vim.lsp.diagnostic.get_all() or
        {[current_buf] = vim.lsp.diagnostic.get(current_buf, opts.client_id)}
      local has_diags = false
      for _, diags in pairs(buffer_diags) do
        if #diags > 0 then has_diags = true end
      end
      if not has_diags then
        utils.info(string.format('No %s found', string.lower(opts.lsp_handler.label)))
        local winid = vim.api.nvim_get_current_win()
        if opts.winid ~= winid then
          -- TODO: why does it go into insert mode after
          -- 'nvim_win_close()?
          -- vim.api.nvim_win_close(0, {force=true})
          -- utils.feed_key("<C-c>")
          -- utils.feed_key("<Esc>")
          utils.send_ctrl_c()
        end
      end
      for bufnr, diags in pairs(buffer_diags) do
        for _, diag in ipairs(diags) do
          -- workspace diagnostics may include empty tables for unused bufnr
          if not vim.tbl_isempty(diag) then
            if filter_diag_severity(opts, diag.severity) then
              diagnostics_handler(opts, cb, co,
                preprocess_diag(diag, bufnr))
            end
          end
        end
      end
      -- coroutine.yield()
      -- close the pipe to fzf, this
      -- removes the loading indicator in fzf
      -- TODO: why is this causing a bug with
      -- 'glepnir/dashboard-nvim'??? (issue #23)
      -- vim.defer_fn(function()
        -- cb(nil, function() coroutine.resume(co) end)
      -- end, 20)
      utils.delayed_cb(cb, function() coroutine.resume(co) end)
      coroutine.yield()
    end)()
  end

  opts = core.set_fzf_line_args(opts)
  return core.fzf_files(opts)
end

M.workspace_diagnostics = function(opts)
  if not opts then opts = {} end
  opts.diag_all = true
  return M.diagnostics(opts)
end

local live_workspace_symbols_sk = function(opts)

  -- "'{}'" opens sk with an empty search_query showing all files
  --  "{}"  opens sk without executing an empty string query
  --  the problem is the latter doesn't support escaped chars
  -- TODO: how to open without a query with special char support
  local sk_args = string.format("%s '{}'", opts._action)

  opts._fzf_cli_args = string.format("--cmd-prompt='%s' -i -c %s",
      opts.prompt,
      vim.fn.shellescape(sk_args))

  opts.git_icons = false
  opts.file_icons = false
  opts.fzf_fn = nil --function(_) end
  opts = core.set_fzf_line_args(opts)
  core.fzf_files(opts)
  opts.search = nil
end

M.live_workspace_symbols = function(opts)

  opts = normalize_lsp_opts(opts, config.globals.lsp)
  opts.lsp_params = {query = ''}

  -- must get those here, otherwise we get the
  -- fzf terminal buffer and window IDs
  opts.bufnr = vim.api.nvim_get_current_buf()
  opts.winid = vim.api.nvim_get_current_win()

  local act_lsp = raw_action(function(args)
    --[[ local results = {}
    local cb = function(item)
      table.insert(results, item)
    end ]]
    -- TODO: how to support the async version?
    -- probably needs nvim-fzf code change
    opts.async = false
    opts.lsp_params = {query = args[2] or ''}
    opts = set_lsp_fzf_fn(opts)
    return opts.fzf_fn
  end)

  -- HACK: support skim (rust version of fzf)
  opts.fzf_bin = opts.fzf_bin or config.globals.fzf_bin
  if opts.fzf_bin and opts.fzf_bin:find('sk')~=nil then
    opts._action = act_lsp
    return live_workspace_symbols_sk(opts)
  end

  -- use {q} as a placeholder for fzf
  local reload_command = act_lsp .. " {q}"

  opts._fzf_cli_args = string.format('--phony --query="" --bind=%s',
    vim.fn.shellescape(string.format("change:reload:%s", reload_command)))

  -- TODO:
  -- this is not getting called past the initial command
  -- until we fix that we cannot use icons as they interfere
  -- with the extension parsing
  opts.git_icons = false
  opts.file_icons = false

  opts.fzf_fn = {}
  opts = core.set_fzf_line_args(opts)
  core.fzf_files(opts)
  opts.search = nil
end

local function check_capabilities(feature)
  local clients = vim.lsp.buf_get_clients(0)

  local supported_client = false
  for _, client in pairs(clients) do
    supported_client = client.resolved_capabilities[feature]
    if supported_client then break end
  end

  if supported_client then
    return true
  else
    if #clients == 0 then
      utils.info("LSP: no client attached")
    else
      utils.info("LSP: server does not support " .. feature)
    end
    return false
  end
end

local handlers = {
  ["code_actions"] = {
    label = "Code Actions",
    capability = "code_action",
    method = "textDocument/codeAction",
    handler = code_action_handler },
  ["references"] = {
    label = "References",
    capability = "find_references",
    method = "textDocument/references",
    handler = location_handler },
  ["definitions"] = {
    label = "Definitions",
    capability = "goto_definition",
    method = "textDocument/definition",
    handler = location_handler },
  ["declarations"] = {
    label = "Declarations",
    capability = "goto_declaration",
    method = "textDocument/declaration",
    handler = location_handler },
  ["typedefs"] = {
    label = "Type Definitions",
    capability = "type_definition",
    method = "textDocument/typeDefinition",
    handler = location_handler },
  ["implementations"] = {
    label = "Implementations",
    capability =  "implementation",
    method = "textDocument/implementation",
    handler = location_handler },
  ["document_symbols"] = {
    label = "Document Symbols",
    capability = "document_symbol",
    method = "textDocument/documentSymbol",
    handler = symbol_handler },
  ["workspace_symbols"] = {
    label = "Workspace Symbols",
    capability = "workspace_symbol",
    method = "workspace/symbol",
    handler = symbol_handler },
  ["live_workspace_symbols"] = {
    label = "Workspace Symbols",
    capability = "workspace_symbol",
    method = "workspace/symbol",
    handler = symbol_handler },
  ["diagnostics"] = {
    label = "Diagnostics",
    capability = nil,
    method = nil,
    handler = diagnostics_handler },
  ["workspace_diagnostics"] = {
    label = "Workspace Diagnostics",
    capability = nil,
    method = nil,
    handler = diagnostics_handler },
}

local function wrap_module_fncs(mod)
  for k, v in pairs(mod) do
    mod[k] = function(opts)
      opts = opts or {}

      if not opts.lsp_handler then opts.lsp_handler = handlers[k] end
      if not opts.lsp_handler then
        utils.err(string.format("No LSP handler defined for %s", k))
        return
      end
      if opts.lsp_handler and opts.lsp_handler.capability
        and not check_capabilities(opts.lsp_handler.capability) then
        return
      end
      v(opts)
    end
  end

  return mod
end

return wrap_module_fncs(M)
