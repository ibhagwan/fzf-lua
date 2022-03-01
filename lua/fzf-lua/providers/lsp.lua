local core = require "fzf-lua.core"
local utils = require "fzf-lua.utils"
local config = require "fzf-lua.config"
local actions = require "fzf-lua.actions"

local M = {}

local function location_to_entry(location, enc)
  local item = vim.lsp.util.locations_to_items({ location }, enc)[1]

  return ('%s:%d:%d'):format(item.filename, item.lnum, item.col)
end

local jump_to_location = function(opts, result, enc)

  local winid = vim.api.nvim_get_current_win()
  if opts.winid ~= winid then
    -- utils.send_ctrl_c()
    vim.api.nvim_win_close(0, false)
  end

  local action = opts.jump_to_single_result_action
  if action then
    local entry = location_to_entry(result, enc)
    return opts.jump_to_single_result_action({ entry }, opts)
  end

  return vim.lsp.util.jump_to_location(result, enc)
end

local function location_handler(opts, cb, _, result, ctx, _)
  local encoding = vim.lsp.get_client_by_id(ctx.client_id).offset_encoding
  result = vim.tbl_islist(result) and result or {result}
  -- Jump immediately if there is only one location
  if opts.jump_to_single_result and #result == 1 then
    jump_to_location(opts, result[1], encoding)
  end
  local items = vim.lsp.util.locations_to_items(result, encoding)
  for _, entry in ipairs(items) do
    if not opts.current_buffer_only or
      vim.api.nvim_buf_get_name(opts.bufnr) == entry.filename then
      entry = core.make_entry_lcol(opts, entry)
      entry = core.make_entry_file(opts, entry)
      if entry then
        cb(entry, function(err)
          if err then return end
        end)
      end
    end
  end
end

local function symbol_handler(opts, cb, _, result, _, _)
  result = vim.tbl_islist(result) and result or {result}
  local items = vim.lsp.util.symbols_to_items(result, 0)
  for _, entry in ipairs(items) do
    if opts.ignore_filename then
      entry.filename = opts.filename
    end
    if not opts.current_buffer_only or
      vim.api.nvim_buf_get_name(opts.bufnr) == entry.filename then
      entry = core.make_entry_lcol(opts, entry)
      entry = core.make_entry_file(opts, entry)
      if entry then
        cb(entry, function(err)
          if err then return end
        end)
      end
    end
  end
end

local function code_action_handler(opts, cb, _, code_actions, context, _)
  if not opts.code_actions then opts.code_actions = {} end
  local i = utils.tbl_length(opts.code_actions) + 1
  for _, action in ipairs(code_actions) do
    local text = string.format("%s %s",
      utils.ansi_codes.magenta(string.format("%d:", i)),
      action.title)
    -- local client = vim.lsp.get_client_by_id(context.client_id)
    local entry = {
      client_id = context.client_id,
      -- client - client,
      -- client_name = client and client.name or "",
      command = action,
    }
    opts.code_actions[tostring(i)] = entry
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
  if opts.lsp_icons and opts._severity_icons[type] then
    local severity = opts._severity_icons[type]
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

-- see neovim #15504
-- https://github.com/neovim/neovim/pull/15504#discussion_r698424017
local mk_handler = function(fn)
  return function(...)
    local is_new = not select(4, ...) or type(select(4, ...)) ~= 'number'
    if is_new then
      -- function(err, result, context, config)
      fn(...)
    else
      -- function(err, method, params, client_id, bufnr, config)
      local err = select(1, ...)
      local method = select(2, ...)
      local result = select(3, ...)
      local client_id = select(4, ...)
      local bufnr = select(5, ...)
      local lspcfg = select(6, ...)
      fn(err, result, { method = method, client_id = client_id, bufnr = bufnr }, lspcfg)
    end
  end
end

local function wrap_handler(handler, opts, cb, co)
  return mk_handler(function(err, result, context, lspcfg)
    -- increment callback & result counters
    opts.num_callbacks = opts.num_callbacks+1
    opts.num_results = opts.num_results or 0 + result and utils.tbl_length(result) or 0
    local ret
    if err then
      ret = err
      utils.err(string.format("Error executing '%s': %s", handler.method, err))
      utils.send_ctrl_c()
    elseif not result or vim.tbl_isempty(result) then
      -- Only close the window if all clients sent their results
      if opts.num_callbacks == opts.num_clients and opts.num_results == 0 then
        ret = utils.info(string.format('No %s found', string.lower(handler.label)))
        utils.send_ctrl_c()
      end
    else
      ret = opts.lsp_handler.handler(opts, cb, co, result, context, lspcfg)
      if opts.num_callbacks == opts.num_clients then
        -- close the pipe to fzf, this
        -- removes the loading indicator in fzf
        utils.delayed_cb(cb)
      end
    end
    return ret
  end)
end

local function set_lsp_fzf_fn(opts)

  -- we must make the params here while we're on
  -- our current buffer window, anything inside
  -- fzf_fn is run while fzf term is open
  opts.bufnr = opts.bufnr or vim.api.nvim_get_current_buf()
  opts.winid = opts.winid or vim.api.nvim_get_current_win()
  opts.filename = vim.api.nvim_buf_get_name(opts.bufnr)
  if not opts.lsp_params then
    opts.lsp_params = vim.lsp.util.make_position_params(0)
    opts.lsp_params.context = { includeDeclaration = true }
  end

  -- Save no of attached clients so we can determine
  -- if all callbacks were completed
  opts.num_results = 0
  opts.num_callbacks = 0
  opts.num_clients = utils.tbl_length(vim.lsp.buf_get_clients(0))

  -- consider 'async_or_timeout' only if
  -- 'sync|async' wasn't manually set
  if opts.sync == nil and opts.async == nil then
    if type(opts.async_or_timeout) == 'number' then
      opts.async = false
    elseif type(opts.async_or_timeout) == 'boolean' then
      opts.async = opts.async_or_timeout
    end
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
        opts.lsp_handler.method, err))
    else
      local results = {}
      local cb = function(text) table.insert(results, text) end
      for client_id, response in pairs(lsp_results) do
        if response.result then
          local context = { client_id = client_id }
          opts.lsp_handler.handler(opts, cb, opts.lsp_handler.method, response.result, context)
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

      -- reset number of callbacks incase
      -- we're being called from 'resume'
      opts.num_callbacks = 0

      -- cancel all currently running requests
      -- can happen when using `live_ws_symbols`
      if opts._cancel_all then
        opts._cancel_all()
        opts._cancel_all = nil
      end

      -- local cancel_all = vim.lsp.buf_request_all(opts.bufnr,
        -- opts.lsp_handler.method, opts.lsp_params,
        -- wrap_request_all(opts.lsp_handler))

      local _, cancel_all = vim.lsp.buf_request(opts.bufnr,
        opts.lsp_handler.method, opts.lsp_params,
        wrap_handler(opts.lsp_handler, opts, cb, co))

      -- save this so we can cancel all requests
      -- when using `live_ws_symbols`
      opts._cancel_all = cancel_all

      -- cancel all remaining LSP requests
      -- once the user made their selection
      -- or closed the fzf popup
      opts.post_select_cb = function()
        if opts._cancel_all then
          opts._cancel_all()
          opts._cancel_all = nil
        end
      end

      -- coroutine.yield()

    end)()
  end

  return opts
end

local set_async_default = function(opts, bool)
  if not opts then opts = {} end
  if opts.sync == nil and
     opts.async == nil then
     opts.async = bool
  end
  return opts
end

local normalize_lsp_opts = function(opts, cfg)
  opts = config.normalize_opts(opts, cfg)
  if not opts then return end

  if not opts.cwd then opts.cwd = vim.loop.cwd() end
  if not opts.prompt and opts.prompt_postfix then
    opts.prompt = opts.lsp_handler.label .. (opts.prompt_postfix or '')
  end

  opts.bufnr = nil
  opts.winid = nil
  opts.filename = nil
  opts.lsp_params = nil
  opts.code_actions = nil
  opts.num_results = nil
  opts.num_callbacks = nil
  opts.num_clients = nil

  return opts
end

local function fzf_lsp_locations(opts)
  opts = normalize_lsp_opts(opts, config.globals.lsp)
  if not opts then return end
  opts = core.set_fzf_field_index(opts)
  if opts.force_uri == nil then opts.force_uri = true end
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
  opts = set_async_default(opts, true)
  -- TODO: filename hiding
  -- since single document
  opts.ignore_filename = true
  return fzf_lsp_locations(opts)
end

M.workspace_symbols = function(opts)
  opts = set_async_default(opts, true)
  opts = normalize_lsp_opts(opts, config.globals.lsp)
  if not opts then return end
  opts.lsp_params = {query = opts.query or ''}
  opts = core.set_fzf_field_index(opts)
  if opts.force_uri == nil then opts.force_uri = true end
  opts = set_lsp_fzf_fn(opts)
  if not opts.fzf_fn then return end
  return core.fzf_files(opts)
end

M.code_actions = function(opts)
  opts = normalize_lsp_opts(opts, config.globals.lsp)
  if not opts then return end

  -- irrelevant for code actions and can cause
  -- single results to be skipped with 'async = false'
  opts.jump_to_single_result = false
  opts.lsp_params = vim.lsp.util.make_range_params(0)
  opts.lsp_params.context = {
    diagnostics = vim.lsp.diagnostic.get_line_diagnostics()
  }

  -- we use `vim.ui.select` for neovim > 0.6
  -- so make sure 'set_lsp_fzf_fn' is run synchronously
  if vim.fn.has('nvim-0.6') == 1 then
    opts.sync, opts.async = true, false
  end

  -- when 'opts.sync == true' calls 'vim.lsp.buf_request_sync'
  -- so we can avoid calling  'ui_select.register' when no code
  -- actions are available
  opts = set_lsp_fzf_fn(opts)

  -- error or no sync request no results
  if not opts.fzf_fn then return end

  -- use `vim.ui.select` for neovim > 0.6
  -- the original method is now deprecated
  if opts.ui_select and vim.fn.has('nvim-0.6') == 1 then
    local ui_select = require'fzf-lua.providers.ui_select'
    opts.previewer = false
    opts.actions = opts.actions or {}
    opts.actions.default = nil
    opts.post_action_cb = function()
      ui_select.deregister({}, true, true)
    end
    ui_select.register(opts, true)
    vim.lsp.buf.code_action()
    -- vim.defer_fn(function()
    --   ui_select.deregister({}, true, true)
    -- end, 100)
    return
  end

  -- see discussion in:
  -- https://github.com/nvim-telescope/telescope.nvim/pull/738
  -- If the text document version is 0, set it to nil instead so that Neovim
  -- won't refuse to update a buffer that it believes is newer than edits.
  -- See: https://github.com/eclipse/eclipse.jdt.ls/issues/1695
  -- Source:
  -- https://github.com/neovim/nvim-lspconfig/blob/486f72a25ea2ee7f81648fdfd8999a155049e466/lua/lspconfig/jdtls.lua#L62
  local function fix_zero_version(workspace_edit)
    if workspace_edit and workspace_edit.documentChanges then
      for _, change in pairs(workspace_edit.documentChanges) do
        local text_document = change.textDocument
        if text_document and text_document.version and text_document.version == 0 then
          text_document.version = nil
        end
      end
    end
    return workspace_edit
  end

  local transform_action = opts.transform_action
    or function(action)
      -- Remove 0 -version from LSP codeaction request payload.
      -- Is only run on the "java.apply.workspaceEdit" codeaction.
      -- Fixed Java/jdtls compatibility with Telescope
      -- See fix_zero_version commentary for more information
      local command = (action.command and action.command.command) or action.command
      if not (command == "java.apply.workspaceEdit") then
        return action
      end
      local arguments = (action.command and action.command.arguments) or action.arguments
      action.edit = fix_zero_version(arguments[1])
      return action
    end

  local execute_action = opts.execute_action
    or function(action, enc)
      if action.edit or type(action.command) == "table" then
        if action.edit then
          vim.lsp.util.apply_workspace_edit(action.edit, enc)
        end
        if type(action.command) == "table" then
          vim.lsp.buf.execute_command(action.command)
        end
      else
        vim.lsp.buf.execute_command(action)
      end
    end

  -- "apply action" as default function
  if not opts.actions then opts.actions = {} end
  opts.actions.default = (function(selected)
    local idx = selected[1]:match("(%d+)")
    local entry = opts.code_actions[idx]
    local action = entry.command
    local client = entry.client or vim.lsp.get_client_by_id(entry.client_id)
    local offset_encoding = client and client.offset_encoding
    if
      not action.edit
      and client
      and type(client.resolved_capabilities.code_action) == "table"
      and client.resolved_capabilities.code_action.resolveProvider
    then
      local request = "codeAction/resolve"
      client.request(request, action, function(resolved_err, resolved_action)
        if resolved_err then
          utils.err(("Error %d executing '%s': %s")
            :format(resolved_err.code, request, resolved_err.message))
          return
        end
        if resolved_action then
          execute_action(transform_action(resolved_action), offset_encoding)
        else
          execute_action(transform_action(action), offset_encoding)
        end
      end)
    else
      execute_action(transform_action(action), offset_encoding)
    end
  end)

  opts.previewer = false
  opts.fzf_opts["--no-multi"] = ''
  opts.fzf_opts["--preview-window"] = 'right:0'

  core.fzf_wrap(opts, opts.fzf_fn, function(selected)

    if opts.post_select_cb then
      opts.post_select_cb()
    end

    if not selected then return end

    actions.act(opts.actions, selected, opts)

  end)()

end

local convert_diagnostic_type = function(severity)
  -- convert from string to int
  if type(severity) == "string" and not tonumber(severity) then
    -- make sure that e.g. error is uppercased to Error
    return vim.diagnostic and vim.diagnostic.severity[severity:upper()] or
      vim.lsp.protocol.DiagnosticSeverity[severity:gsub("^%l", string.upper)]
  else
    -- otherwise keep original value, incl. nil
    return tonumber(severity)
  end
end

local filter_diag_severity = function(opts, severity)
  if opts.severity_only ~= nil then
    return tonumber(opts.severity_only) == severity
  elseif opts.severity_limit ~= nil then
    return severity <= tonumber(opts.severity_limit)
  elseif opts.severity_bound ~= nil then
    return severity >= tonumber(opts.severity_bound)
  else
    return true
  end
end

M.diagnostics = function(opts)
  opts = normalize_lsp_opts(opts, config.globals.lsp)
  if not opts then return end

  local lsp_clients = vim.lsp.buf_get_clients(0)
  if utils.tbl_isempty(lsp_clients) then
    utils.info("LSP: no client attached")
    return
  end

  opts.winid = vim.api.nvim_get_current_win()
  local current_buf = vim.api.nvim_get_current_buf()

  -- normalize the LSP icons table
  opts._severity_icons = {}
  for k, v in pairs({
    ["Error"]       = 1,
    ["Warning"]     = 2,
    ["Information"] = 3,
    ["Hint"]        = 4
  }) do
    if opts.icons and opts.icons[k] then
      opts._severity_icons[v] = opts.icons[k]
    end
  end

  -- hint         = 4
  -- information  = 3
  -- warning      = 2
  -- error        = 1
  -- severity_only:   keep any matching exact severity
  -- severity_limit:  keep any equal or more severe (lower)
  -- severity_bound:  keep any equal or less severe (higher)
  opts.severity_only = convert_diagnostic_type(opts.severity_only)
  opts.severity_limit = convert_diagnostic_type(opts.severity_limit)
  opts.severity_bound = convert_diagnostic_type(opts.severity_bound)

  local diag_opts = { severity = {}, namespace = opts.namespace }
  if opts.severity_only ~= nil then
    if opts.severity_limit ~= nil or opts.severity_bound ~= nil then
      utils.warn("Invalid severity parameters. Both a specific severity and a limit/bound is not allowed")
      return {}
    end
    diag_opts.severity = opts.severity_only
  else
    if opts.severity_limit ~= nil then
      diag_opts.severity["min"] = opts.severity_limit
    end
    if opts.severity_bound ~= nil then
      diag_opts.severity["max"] = opts.severity_bound
    end
  end

  local diag_results = vim.diagnostic and
    vim.diagnostic.get(not opts.diag_all and current_buf or nil, diag_opts) or
    opts.diag_all and vim.lsp.diagnostic.get_all() or
    {[current_buf] = vim.lsp.diagnostic.get(current_buf, opts.client_id)}

  local has_diags = false
  if vim.diagnostic then
    -- format: { <diag array> }
    has_diags = not vim.tbl_isempty(diag_results)
  else
    -- format: { [bufnr] = <diag array>, ... }
    for _, diags in pairs(diag_results) do
      if #diags > 0 then has_diags = true end
    end
  end
  if not has_diags then
    utils.info(string.format('No %s found', string.lower(opts.lsp_handler.label)))
    return
  end

  local preprocess_diag = function(diag, bufnr)
    bufnr = bufnr or diag.bufnr
    local filename = vim.api.nvim_buf_get_name(bufnr)
    -- pre vim.diagnostic (vim.lsp.diagnostic)
    -- has 'start|finish' instead of 'end_col|end_lnum'
    local start = diag.range and diag.range['start']
    -- local finish = diag.range and diag.range['end']
    local row = diag.lnum or start.line
    local col = diag.col or start.character

    local buffer_diag = {
      bufnr = bufnr,
      filename = filename,
      lnum = row + 1,
      col = col + 1,
      text = vim.trim(diag.message:gsub("[\n]", "")),
      type = diag.severity or 1
    }
    return buffer_diag
  end

  opts.fzf_fn = function (cb)
    coroutine.wrap(function ()
      local co = coroutine.running()

      local function process_diagnostics(diags, bufnr)
        for _, diag in ipairs(diags) do
          -- workspace diagnostics may include
          -- empty tables for unused buffers
          if not vim.tbl_isempty(diag) then
            if filter_diag_severity(opts, diag.severity) then
              diagnostics_handler(opts, cb, co,
                preprocess_diag(diag, bufnr))
            end
          end
        end
      end

      if vim.diagnostic then
        process_diagnostics(diag_results)
      else
        for bufnr, diags in pairs(diag_results) do
          process_diagnostics(diags, bufnr)
        end
      end
      -- close the pipe to fzf, this
      -- removes the loading indicator
      cb(nil)
    end)()
  end

  opts = core.set_fzf_field_index(opts)
  if opts.force_uri == nil then opts.force_uri = true end
  return core.fzf_files(opts)
end

M.workspace_diagnostics = function(opts)
  if not opts then opts = {} end
  opts.diag_all = true
  return M.diagnostics(opts)
end

local last_search = {}

M.live_workspace_symbols = function(opts)
  opts = normalize_lsp_opts(opts, config.globals.lsp)
  if not opts then return end

  -- exec empty query is the default here
  if opts.exec_empty_query == nil then
    opts.exec_empty_query = true
  end

  if not opts.query
    and opts.continue_last_search ~= false
    and opts.repeat_last_search ~= false then
    opts.query = last_search.query
  end

  if opts.query and #opts.query>0 then
    -- save the search query so the use can
    -- call the same search again
    last_search = {}
    last_search.query = opts.search
  end

  -- sent to the LSP server
  opts.lsp_params = {query = opts.query or ''}

  -- must get those here, otherwise we get the
  -- fzf terminal buffer and window IDs
  opts.bufnr = vim.api.nvim_get_current_buf()
  opts.winid = vim.api.nvim_get_current_win()

  opts._reload_action = function(query)
    if query and not (opts.save_last_search == false) then
      last_search = {}
      last_search.query = query
      config.__resume_data.last_query = query
    end
    opts.sync = true
    opts.async = false
    opts.lsp_params = {query = query or ''}
    opts = set_lsp_fzf_fn(opts)
    return opts.fzf_fn
  end

  -- disable global resume
  -- conflicts with 'change:reload' event
  opts.global_resume_query = false
  opts.__FNCREF__ = M.live_workspace_symbols
  opts = core.set_fzf_interactive_cb(opts)
  opts = core.set_fzf_field_index(opts)
  if opts.force_uri == nil then opts.force_uri = true end
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
    if utils.tbl_isempty(clients) then
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
