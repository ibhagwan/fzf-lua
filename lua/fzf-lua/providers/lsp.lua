if not pcall(require, "fzf") then
  return
end

local fzf = require "fzf"
-- local fzf_helpers = require("fzf.helpers")
-- local path = require "fzf-lua.path"
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
    cb(entry, function(err)
      if err then return end
    end)
  end
end

local function symbol_handler(opts, cb, _, result)
  result = vim.tbl_islist(result) and result or {result}
  local items = vim.lsp.util.symbols_to_items(result)
  for _, entry in ipairs(items) do
    entry.filename = opts.filename
    entry = core.make_entry_lcol(opts, entry)
    entry = core.make_entry_file(opts, entry)
    cb(entry, function(err)
      if err then return end
    end)
  end
end

local function code_action_handler(opts, cb, _, code_actions)
  opts.code_actions = {}
  for i, action in ipairs(code_actions) do
    local text = string.format("%s %s",
      utils.ansi_codes.magenta(string.format("%d:", i)),
      action.title)
    opts.code_actions[tostring(i)] = action
    cb(text, function(err)
      if err then return end
    end)
  end
end

local function diagnostics_handler(opts, cb, _, entry)
  local type = entry.type
  entry = core.make_entry_lcol(opts, entry)
  entry = core.make_entry_file(opts, entry)
  if opts.lsp_icons and opts.cfg.icons[type] then
    local severity = opts.cfg.icons[type]
    local icon = severity.icon
    if opts.color_icons then
      icon = utils.ansi_codes[severity.color or "dark_grey"](icon)
    end
    if opts.file_icons or opts.git_icons then
      entry = icon .. utils.nbsp .. utils.nbsp .. entry
    else
      entry = icon .. utils.nbsp .. " " .. entry
    end
  end
  cb(entry, function(err)
    if err then return end
  end)
end

local function wrap_handler(handler)
  return function(err, method, result, client_id, bufnr, lspcfg)
    local ret
    if err then
      ret = utils.err(err.message)
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

local function set_lsp_fzf_fn(opts)

  -- we must make the params here while we're on
  -- our current buffer window, anything inside
  -- fzf_fn is run while fzf term is open
  opts.bufnr = vim.api.nvim_get_current_buf()
  opts.winid = vim.api.nvim_get_current_win()
  opts.filename = vim.api.nvim_buf_get_name(opts.bufnr)
  if not opts.lsp_params then
    opts.lsp_params = vim.lsp.util.make_position_params()
    opts.lsp_params.context = { includeDeclaration = true }
  end

  opts.fzf_fn = function (cb)
    coroutine.wrap(function ()
      local co = coroutine.running()

      -- callback when a location is found
      -- we use this passthrough so we can send the
      -- coroutine variable (not used rn but who knows?)
      opts.lsp_handler.target = function(_, _, result)
        return opts.lsp_handler.handler(opts, cb, co, result)
      end

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

local set_fzf_files_args = function(opts)
  local line_placeholder = 2
  if opts.file_icons or opts.git_icons or opts.lsp_icons then
    line_placeholder = line_placeholder+1
  end

  opts.cli_args = opts.cli_args or "--delimiter='[: \\t]'"
  opts.filespec = string.format("{%d}", line_placeholder-1)
  opts.preview_args = string.format("--highlight-line={%d}", line_placeholder)
  opts.preview_offset = string.format("+{%d}-/2", line_placeholder)
  return opts
end

local normalize_lsp_opts = function(opts, cfg)
  opts = config.getopts(opts, cfg, {
    "cwd", "actions", "winopts",
    "file_icons", "color_icons",
    "git_icons", "lsp_icons", "severity",
    "severity_exact", "severity_bound",
  })

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
  opts = normalize_lsp_opts(opts, config.lsp)
  opts = set_fzf_files_args(opts)
  opts = set_lsp_fzf_fn(opts)
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
  opts = normalize_lsp_opts(opts, config.lsp)
  opts.lsp_params = {query = ''}
  opts = set_fzf_files_args(opts)
  opts = set_lsp_fzf_fn(opts)
  return core.fzf_files(opts)
end

M.code_actions = function(opts)
  opts = normalize_lsp_opts(opts, config.lsp)
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
  opts.cli_args = "--delimiter=':'"
  opts = set_lsp_fzf_fn(opts)

  coroutine.wrap(function ()

    local selected = fzf.fzf(opts.fzf_fn,
      core.build_fzf_cli(opts),
      config.winopts(opts.winopts))

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
  opts = normalize_lsp_opts(opts, config.lsp)

  local lsp_clients = vim.lsp.buf_get_clients(0)
  if #lsp_clients == 0 then
    utils.info("LSP: no client attached")
    return
  end

  local lsp_type_diagnostic = vim.lsp.protocol.DiagnosticSeverity
  local current_buf = vim.api.nvim_get_current_buf()

  -- save this so handler can get the lsp icon
  opts.cfg = config.lsp

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
      if #buffer_diags == 0 then
        utils.info(string.format('No %s found', string.lower(opts.lsp_handler.label)))
        utils.send_ctrl_c()
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
    end)()
  end

  opts = set_fzf_files_args(opts)
  return core.fzf_files(opts)
end

M.workspace_diagnostics = function(opts)
  if not opts then opts = {} end
  opts.diag_all = true
  return M.diagnostics(opts)
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
