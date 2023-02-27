local core = require "fzf-lua.core"
local utils = require "fzf-lua.utils"
local config = require "fzf-lua.config"
local make_entry = require "fzf-lua.make_entry"

local M = {}

local function CTX_UPDATE()
  -- save current win/buf context, ignore when fzf
  -- window is already open (actions.sym_lsym)
  if not __CTX or not utils.fzf_winobj() then
    __CTX = {
      winid = vim.api.nvim_get_current_win(),
      bufnr = vim.api.nvim_get_current_buf(),
      bufname = vim.api.nvim_buf_get_name(0),
      cursor = vim.api.nvim_win_get_cursor(0),
    }
  end
end

local function check_capabilities(feature)
  -- update CTX since this gets called before normalize_lsp_opts (#490)
  CTX_UPDATE()

  local clients = vim.lsp.get_active_clients({ bufnr = __CTX and __CTX.bufnr or 0 })

  -- return the number of clients supporting the feature
  -- so the async version knows how many callbacks to wait for
  local num_clients = 0
  local features = {}

  if type(feature) == "string" then
    table.insert(features, feature)
  elseif type(feature) == "table" then
    features = feature
  end

  for _, client in pairs(clients) do
    for _, ft in pairs(features) do
      if vim.fn.has("nvim-0.8") == 1 then
        if client.server_capabilities[ft] then
          num_clients = num_clients + 1
        end
      else
        if client.resolved_capabilities[ft] then
          num_clients = num_clients + 1
        end
      end
    end
  end

  if num_clients > 0 then
    return num_clients
  end

  if utils.tbl_isempty(clients) then
    utils.info("LSP: no client attached")
  else
    utils.info("LSP: server does not support " .. feature)
  end
  return false
end

local function location_to_entry(location, enc)
  local item = vim.lsp.util.locations_to_items({ location }, enc)[1]

  return ("%s:%d:%d:"):format(item.filename, item.lnum, item.col)
end

local jump_to_location = function(opts, result, enc)
  -- exits the fzf window when use with async
  -- safe to call even if the interface is closed
  utils.fzf_exit()

  local action = opts.jump_to_single_result_action
  if action then
    local entry = location_to_entry(result, enc)
    return opts.jump_to_single_result_action({ entry }, opts)
  end

  return vim.lsp.util.jump_to_location(result, enc)
end

local function location_handler(opts, cb, _, result, ctx, _)
  local encoding = vim.lsp.get_client_by_id(ctx.client_id).offset_encoding
  result = vim.tbl_islist(result) and result or { result }
  if opts.ignore_current_line then
    local cursor_line = __CTX.cursor[1] - 1
    result = vim.tbl_filter(function(l)
      if l.range and l.range.start and l.range.start.line == cursor_line then
        return false
      end
      return true
    end, result)
  end
  -- Jump immediately if there is only one location
  if opts.jump_to_single_result and #result == 1 then
    jump_to_location(opts, result[1], encoding)
  end
  local items = vim.lsp.util.locations_to_items(result, encoding)
  for _, entry in ipairs(items) do
    if not opts.current_buffer_only or __CTX.bufname == entry.filename then
      entry = make_entry.lcol(entry, opts)
      entry = make_entry.file(entry, opts)
      if entry then cb(entry) end
    end
  end
end

local function call_hierarchy_handler(opts, cb, _, result, _, _)
  for _, call_hierarchy_call in pairs(result) do
    --- "from" for incoming calls and "to" for outgoing calls
    local call_hierarchy_item = call_hierarchy_call.from or call_hierarchy_call.to
    for _, range in pairs(call_hierarchy_call.fromRanges) do
      local location = {
        filename = assert(vim.uri_to_fname(call_hierarchy_item.uri)),
        text = call_hierarchy_item.name,
        lnum = range.start.line + 1,
        col = range.start.character + 1,
      }
      local entry = make_entry.lcol(location, opts)
      entry = make_entry.file(entry, opts)
      if entry then cb(entry) end
    end
  end
end

local function symbol_handler(opts, cb, _, result, _, _)
  result = vim.tbl_islist(result) and result or { result }
  local items = vim.lsp.util.symbols_to_items(result, __CTX.bufnr)
  for _, entry in ipairs(items) do
    if (not opts.current_buffer_only or __CTX.bufname == entry.filename) and
        (not opts.regex_filter or entry.text:match(opts.regex_filter)) then
      if M._sym2style then
        local kind = entry.text:match("%[(.-)%]")
        if kind and M._sym2style[kind] then
          entry.text = entry.text:gsub("%[.-%]", M._sym2style[kind])
        end
      end
      entry = make_entry.lcol(entry, opts)
      entry = make_entry.file(entry, opts)
      if entry then cb(entry) end
    end
  end
end

local function code_action_handler(opts, cb, _, code_actions, context, _)
  if not opts.code_actions then opts.code_actions = {} end
  local i = vim.tbl_count(opts.code_actions) + 1
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
    cb(text)
    i = i + 1
  end
end

-- see neovim #15504
-- https://github.com/neovim/neovim/pull/15504#discussion_r698424017
local mk_handler = function(fn)
  return function(...)
    local is_new = not select(4, ...) or type(select(4, ...)) ~= "number"
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
      fn(err, result,
        { method = method, client_id = client_id, bufnr = bufnr }, lspcfg)
    end
  end
end

local function async_lsp_handler(co, handler, opts)
  return mk_handler(function(err, result, context, lspcfg)
    -- increment callback & result counters
    opts.num_callbacks = opts.num_callbacks + 1
    opts.num_results = (opts.num_results or 0) +
        (result and vim.tbl_count(result) or 0)
    if err then
      utils.err(string.format("Error executing '%s': %s", handler.method, err))
      utils.fzf_exit()
      coroutine.resume(co, true, err)
    else
      -- did all clients send back their responses?
      local done = opts.num_callbacks == opts.num_clients
      -- only close the window if we still have zero results
      -- after all clients have sent their results
      if done and opts.num_results == 0 then
        -- Do not close the window in 'live_workspace_symbols'
        if not opts.fn_reload then
          utils.info(string.format("No %s found", string.lower(handler.label)))
          utils.fzf_exit()
        end
      end
      -- resume the coroutine
      coroutine.resume(co, done, err, result, context, lspcfg)
    end
  end)
end

local function set_lsp_finder_fzf_fn(opts)
  -- consider 'async_or_timeout' only if 'async' wasn't manually set
  if opts.async == nil then
    if type(opts.async_or_timeout) == "number" then
      opts.async = false
    elseif type(opts.async_or_timeout) == "boolean" then
      opts.async = opts.async_or_timeout
    end
  end

  -- build positional params for the LSP query
  -- from the context buffer and cursor position
  if not opts.lsp_params then
    opts.lsp_params = vim.lsp.util.make_position_params(__CTX.winid)
    opts.lsp_params.context = { includeDeclaration = true }
  end

  -- SYNC
  local timeout = 5000
  if type(opts.async_or_timeout) == "number" then
    timeout = opts.async_or_timeout
  end

  local lsp_declaration_results, _ = vim.lsp.buf_request_sync(__CTX.bufnr,
    "textDocument/declaration", opts.lsp_params, timeout)
  local lsp_implementation_results, _ = vim.lsp.buf_request_sync(__CTX.bufnr,
    "textDocument/implementation", opts.lsp_params, timeout)
  local lsp_definition_results, _ = vim.lsp.buf_request_sync(__CTX.bufnr,
    "textDocument/definition", opts.lsp_params, timeout)
  local lsp_references_results, _ = vim.lsp.buf_request_sync(__CTX.bufnr,
    "textDocument/references", opts.lsp_params, timeout)
  local lsp_type_definition_results, _ = vim.lsp.buf_request_sync(__CTX.bufnr,
    "textDocument/typeDefinition", opts.lsp_params, timeout)

  local results = {}
  local cb = function(text) table.insert(results, text) end
  for _, lsp_results in pairs({ lsp_definition_results, lsp_references_results, lsp_declaration_results, lsp_type_definition_results, lsp_implementation_results }) do
    for client_id, response in pairs(lsp_results) do
      if response.result then
        local context = { client_id = client_id }
        opts.lsp_handler.handler(opts, cb, opts.lsp_handler.method, response.result, context)
      end
    end
  end
  if vim.tbl_isempty(results) then
    if not opts.fn_reload then
      utils.info(string.format("No %s found", string.lower(opts.lsp_handler.label)))
    else
      -- return an empty set or the results wouldn't be
      -- cleared on live_workspace_symbols (#468)
      opts.fzf_fn = {}
    end
  elseif not (opts.jump_to_single_result and #results == 1) then
    -- LSP request was synchronous but
    -- we still async the fzf feeding
    opts.fzf_fn = function(fzf_cb)
      coroutine.wrap(function()
        local co = coroutine.running()
        for _, e in ipairs(results) do
          fzf_cb(e, function() coroutine.resume(co) end)
          coroutine.yield()
        end
        fzf_cb(nil)
      end)()
    end
  end
  return opts
end

local function set_lsp_fzf_fn(opts)
  -- consider 'async_or_timeout' only if 'async' wasn't manually set
  if opts.async == nil then
    if type(opts.async_or_timeout) == "number" then
      opts.async = false
    elseif type(opts.async_or_timeout) == "boolean" then
      opts.async = opts.async_or_timeout
    end
  end

  -- build positional params for the LSP query
  -- from the context buffer and cursor position
  if not opts.lsp_params then
    opts.lsp_params = vim.lsp.util.make_position_params(__CTX.winid)
    opts.lsp_params.context = { includeDeclaration = true }
  end

  if not opts.async then
    -- SYNC
    local timeout = 5000
    if type(opts.async_or_timeout) == "number" then
      timeout = opts.async_or_timeout
    end
    local lsp_results, err = vim.lsp.buf_request_sync(__CTX.bufnr,
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
        if not opts.fn_reload then
          utils.info(string.format("No %s found", string.lower(opts.lsp_handler.label)))
        else
          -- return an empty set or the results wouldn't be
          -- cleared on live_workspace_symbols (#468)
          opts.fzf_fn = {}
        end
      elseif not (opts.jump_to_single_result and #results == 1) then
        -- LSP request was synchronous but
        -- we still async the fzf feeding
        opts.fzf_fn = function(fzf_cb)
          coroutine.wrap(function()
            local co = coroutine.running()
            for _, e in ipairs(results) do
              fzf_cb(e, function() coroutine.resume(co) end)
              coroutine.yield()
            end
            fzf_cb(nil)
          end)()
        end
      end
    end
  else
    -- ASYNC
    -- cancel all remaining LSP requests once the user
    -- made their selection or closed the fzf popup
    local fn_cancel_all = function(o)
      if o and o._cancel_all then
        o._cancel_all()
        o._cancel_all = nil
      end
    end
    opts._fn_post_fzf = fn_cancel_all

    -- ASYNC
    opts.fzf_fn = function(fzf_cb)
      coroutine.wrap(function()
        local co = coroutine.running()

        -- Save no. of attached clients **supporting the capability**
        -- so we can determine if all callbacks were completed (#468)
        opts.num_results = 0
        opts.num_callbacks = 0
        opts.num_clients = check_capabilities(opts.lsp_handler.capability)

        -- when used with 'live_workspace_symbols'
        -- cancel all lingering LSP queries
        fn_cancel_all(opts)

        local _, cancel_all = vim.lsp.buf_request(__CTX.bufnr,
          opts.lsp_handler.method, opts.lsp_params,
          async_lsp_handler(co, opts.lsp_handler, opts))

        -- save this so we can cancel all requests
        -- when using `live_ws_symbols`
        opts._cancel_all = cancel_all

        -- process results from all LSP client
        local err, result, context, lspcfg, done
        repeat
          done, err, result, context, lspcfg = coroutine.yield()
          if not err and type(result) == "table" then
            local cb = function(e)
              fzf_cb(e, function() coroutine.resume(co) end)
              coroutine.yield()
            end
            opts.lsp_handler.handler(opts, cb,
              opts.lsp_handler.method, result, context, lspcfg)
          end
          -- some clients may not always return results (null-ls?)
          -- so don't terminate the loop when 'result == nil`
        until done or err

        -- no more results
        fzf_cb(nil)

        -- we only get here once all requests are done
        -- so we can clear '_cancel_all'
        opts._cancel_all = nil
      end)()
    end
  end

  return opts
end

local normalize_lsp_opts = function(opts, cfg)
  opts = config.normalize_opts(opts, cfg)
  if not opts then return end

  if not opts.prompt and opts.prompt_postfix then
    opts.prompt = opts.lsp_handler.label .. (opts.prompt_postfix or "")
  end

  -- required for relative paths presentation
  if not opts.cwd or #opts.cwd == 0 then
    opts.cwd = vim.loop.cwd()
  else
    opts.cwd_only = true
  end

  -- save current win/buf context
  -- moved to 'check_capabilities' (#490)
  -- CTX_UPDATE()

  opts.code_actions = nil

  return opts
end

local function fzf_lsp_locations(opts)
  opts = normalize_lsp_opts(opts, config.globals.lsp)
  if not opts then return end
  if opts.force_uri == nil then opts.force_uri = true end
  opts = core.set_fzf_field_index(opts)
  if type(opts.lsp_handler.method) == "table" then
    opts = set_lsp_finder_fzf_fn(opts)
  else
    opts = set_lsp_fzf_fn(opts)
  end
  if not opts.fzf_fn then return end
  return core.fzf_exec(opts.fzf_fn, opts)
end

-- define the functions for wrap_module_fncs
M.finder = function(opts)
  return fzf_lsp_locations(opts)
end

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

-- see $VIMRUNTIME/lua/vim/buf.lua:pick_call_hierarchy_item()
M.call_hierarchy = function(opts)
  opts.lsp_params = vim.lsp.util.make_position_params(__CTX and __CTX.winid or 0)
  local method = "textDocument/prepareCallHierarchy"
  local res, err = vim.lsp.buf_request_sync(
    0, method, opts.lsp_params, 2000)
  if err then
    utils.err(("Error executing '%s': %s"):format(method, err))
  else
    local _, response = next(res)
    if vim.tbl_isempty(response) then
      utils.info(("No %s found"):format(opts.lsp_handler.label:lower()))
      return
    end
    assert(response.result and response.result[1])
    local call_hierarchy_item = response.result[1]
    opts.lsp_params = { item = call_hierarchy_item }
    return fzf_lsp_locations(opts)
  end
end

M.incoming_calls = function(opts)
  return M.call_hierarchy(opts)
end

M.outgoing_calls = function(opts)
  return M.call_hierarchy(opts)
end

local function gen_sym2style_map(opts)
  assert(M._sym2style == nil)
  assert(opts.symbol_style ~= nil)
  M._sym2style = {}
  local colormap = vim.api.nvim_get_color_map()
  for k, v in pairs(vim.lsp.protocol.CompletionItemKind) do
    if type(k) == "string" then
      local icon = vim.lsp.protocol.CompletionItemKind[v]
      -- style==1: "<icon> <kind>"
      -- style==2: "<icon>"
      -- style==3: "<kind>"
      local s = nil
      if opts.symbol_style == 1 then
        -- if icons weren't set by the user
        -- icon will match the kind
        if icon ~= k then
          s = ("%s %s"):format(icon, k)
        else
          s = k
        end
      elseif opts.symbol_style == 2 then
        s = icon
      elseif opts.symbol_style == 3 then
        s = k
      end
      if s and opts.symbol_hl_prefix then
        M._sym2style[k] = utils.ansi_from_hl(opts.symbol_hl_prefix .. k, s, colormap)
      elseif s then
        M._sym2style[k] = s
      else
        -- can get here when only 'opts.symbol_fmt' was set
        M._sym2style[k] = k
      end
    end
  end
  if type(opts.symbol_fmt) == "function" then
    for k, v in pairs(M._sym2style) do
      M._sym2style[k] = opts.symbol_fmt(v) or v
    end
  end
end

M.document_symbols = function(opts)
  opts = normalize_lsp_opts(opts, config.globals.lsp.symbols)
  if not opts then return end
  opts.__MODULE__ = opts.__MODULE__ or M
  opts = core.set_header(opts, opts.headers or { "regex_filter" })
  opts = core.set_fzf_field_index(opts)
  if opts.force_uri == nil then opts.force_uri = true end
  if not opts.fzf_opts or opts.fzf_opts["--with-nth"] == nil then
    opts.fzf_opts               = opts.fzf_opts or {}
    opts.fzf_opts["--with-nth"] = "2.."
    opts.fzf_opts["--tiebreak"] = "index"
  end
  opts = set_lsp_fzf_fn(opts)
  if not opts.fzf_fn then return end
  if opts.symbol_style or opts.symbol_fmt then
    opts.fn_pre_fzf = function() gen_sym2style_map(opts) end
    opts.fn_post_fzf = function() M._sym2style = nil end
  end
  return core.fzf_exec(opts.fzf_fn, opts)
end

local function get_last_lspquery(_)
  return M.__last_ws_lsp_query
end

local function set_last_lspquery(_, query)
  M.__last_ws_lsp_query = query
  if config.__resume_data then
    config.__resume_data.last_query = query
  end
end

M.workspace_symbols = function(opts)
  opts = normalize_lsp_opts(opts, config.globals.lsp.symbols)
  if not opts then return end
  opts.__MODULE__ = opts.__MODULE__ or M
  if not opts.lsp_query and opts.resume then
    opts.lsp_query = get_last_lspquery(opts)
  end
  set_last_lspquery(opts, opts.lsp_query)
  opts.lsp_params = { query = opts.lsp_query or "" }
  opts = core.set_header(opts, opts.headers or
  { "actions", "cwd", "lsp_query", "regex_filter" })
  opts = core.set_fzf_field_index(opts)
  if opts.force_uri == nil then opts.force_uri = true end
  opts = set_lsp_fzf_fn(opts)
  if not opts.fzf_fn then return end
  if opts.symbol_style or opts.symbol_fmt then
    opts.fn_pre_fzf = function() gen_sym2style_map(opts) end
    -- when using an empty string grep (as in 'grep_project') or
    -- when switching from grep to live_grep using 'ctrl-g', users
    -- may find it confusing why the last typed query is not
    -- considered the last search. So we find out if that's the
    -- case and use the last typed prompt as the grep string
    opts.fn_post_fzf = function(o, _)
      M._sym2style = nil
      local last_lspquery = get_last_lspquery(o)
      local last_query = config.__resume_data and config.__resume_data.last_query
      if not last_lspquery or #last_lspquery == 0
          and (last_query and #last_query > 0) then
        set_last_lspquery(opts, last_query)
      end
    end
  end
  return core.fzf_exec(opts.fzf_fn, opts)
end

M.live_workspace_symbols = function(opts)
  opts = normalize_lsp_opts(opts, config.globals.lsp.symbols)
  if not opts then return end

  -- needed by 'actions.sym_lsym'
  -- prepend the prompt with asterisk
  opts.__MODULE__ = opts.__MODULE__ or M
  opts.prompt = opts.prompt and opts.prompt:match("^%*") or "*" .. opts.prompt

  -- exec empty query is the default here
  if opts.exec_empty_query == nil then
    opts.exec_empty_query = true
  end

  if not opts.lsp_query and opts.resume then
    opts.lsp_query = get_last_lspquery(opts)
  end

  -- sent to the LSP server
  opts.lsp_params = { query = opts.lsp_query or opts.query or "" }
  opts.query = opts.lsp_query or opts.query

  -- don't use the automatic coroutine since we
  -- use our own
  opts.func_async_callback = false
  opts.fn_reload = function(query)
    if query and not (opts.save_last_search == false) then
      set_last_lspquery(opts, query)
    end
    opts.lsp_params = { query = query or "" }
    opts = set_lsp_fzf_fn(opts)
    return opts.fzf_fn
  end

  opts = core.set_header(opts, opts.headers or { "actions", "cwd", "regex_filter" })
  opts = core.set_fzf_field_index(opts)
  if opts.force_uri == nil then opts.force_uri = true end
  if opts.symbol_style or opts.symbol_fmt then
    opts.fn_pre_fzf = function() gen_sym2style_map(opts) end
    opts.fn_post_fzf = function() M._sym2style = nil end
  end
  core.fzf_exec(nil, opts)
end

-- Converts 'vim.diagnostic.get' to legacy style 'get_line_diagnostics()'
local function get_line_diagnostics(_)
  if not vim.diagnostic then
    return vim.lsp.diagnostic.get_line_diagnostics()
  end
  local diag = vim.diagnostic.get(__CTX.bufnr, { lnum = vim.api.nvim_win_get_cursor(0)[1] - 1 })
  return diag and diag[1] and { {
        source = diag[1].source,
        message = diag[1].message,
        severity = diag[1].severity,
        code = diag[1].user_data and diag[1].user_data.lsp and
        diag[1].user_data.lsp.code,
        codeDescription = diag[1].user_data and diag[1].user_data.lsp and
        diag[1].user_data.lsp.codeDescription,
        range = {
          ["start"] = {
            line = diag[1].lnum,
            character = diag[1].col,
          },
          ["end"] = {
            line = diag[1].end_lnum,
            character = diag[1].end_col,
          }
        },
        data = diag[1].user_data and diag[1].user_data.lsp and
        diag[1].user_data.lsp.data
      } } or nil
end

---Returns true if the client has code_action capability and its
-- resolveProvider is true.
-- @param client vim.lsp.buf.client
-- @return boolean
local function code_action_resolves(client)
  local code_action
  if vim.fn.has("nvim-0.8") == 1 then
    code_action = client.server_capabilities.codeActionProvider
  else
    code_action = client.resolved_capabilities.code_action
  end

  return type(code_action) == "table" and code_action.resolveProvider
end

M.code_actions = function(opts)
  opts = normalize_lsp_opts(opts, config.globals.lsp.code_actions)
  if not opts then return end

  -- irrelevant for code actions and can cause
  -- single results to be skipped with 'async = false'
  opts.jump_to_single_result = false
  opts.lsp_params = vim.lsp.util.make_range_params(0)
  opts.lsp_params.context = {
    diagnostics = get_line_diagnostics(opts)
  }

  -- we use `vim.ui.select` for neovim > 0.6
  -- so make sure 'set_lsp_fzf_fn' is run synchronously
  if vim.fn.has("nvim-0.6") == 1 then
    opts.async = false
  end

  -- when 'opts.async == false' calls 'vim.lsp.buf_request_sync'
  -- so we can avoid calling 'ui_select.register' when no code
  -- actions are available
  opts = set_lsp_fzf_fn(opts)

  -- error or no sync request no results
  if not opts.fzf_fn then return end

  -- use `vim.ui.select` for neovim > 0.6
  -- the original method is now deprecated
  if opts.ui_select and vim.fn.has("nvim-0.6") == 1 then
    local ui_select = require "fzf-lua.providers.ui_select"
    local registered = ui_select.is_registered()
    opts.previewer = false
    opts.actions = opts.actions or {}
    opts.actions.default = nil
    -- only dereg if we aren't registered
    if not registered then
      opts.post_action_cb = function()
        ui_select.deregister({}, true, true)
      end
    end
    -- 3rd arg are "once" options to override
    -- existing "registered" ui_select options
    ui_select.register(opts, true, opts)
    vim.lsp.buf.code_action()
    -- vim.defer_fn(function()
    --   ui_select.deregister({}, true, true)
    -- end, 100)
    return
  end

  -- see discussion in:
  -- https://github.com/nvim-telescope/telescope.nvim/pull/738
  -- If the text document version is 0, set it to nil so that Neovim
  -- won't refuse to update a buffer that it believes is newer than edits.
  -- See: https://github.com/eclipse/eclipse.jdt.ls/issues/1695
  -- Source:
  -- https://github.com/neovim/nvim-lspconfig/blob/\
  --    486f72a25ea2ee7f81648fdfd8999a155049e466/lua/lspconfig/jdtls.lua#L62
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
        -- Remove 0-version from LSP codeaction request payload.
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

        if not action.edit and client and code_action_resolves(client) then
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
  opts.fzf_opts["--no-multi"] = ""
  opts.fzf_opts["--preview-window"] = "right:0"

  core.fzf_exec(opts.fzf_fn, opts)
end

local handlers = {
  ["code_actions"] = {
    label = "Code Actions",
    resolved_capability = "code_action",
    server_capability = "codeActionProvider",
    method = "textDocument/codeAction",
    handler = code_action_handler
  },
  ["finder"] = {
    label = "Finder",
    resolved_capability = { "find_references", "goto_definition", "goto_declaration", "type_definition", "implementation" },
    server_capability = { "referencesProvider", "definitionProvider", "declarationProvider", "typeDefinitionProvider", "implementationProvider" },
    method = { "textDocument/references", "textDocument/definition", "textDocument/declaration", "textDocument/typeDefinition", "textDocument/implementation" },
    handler = location_handler
  },
  ["references"] = {
    label = "References",
    resolved_capability = "find_references",
    server_capability = "referencesProvider",
    method = "textDocument/references",
    handler = location_handler
  },
  ["definitions"] = {
    label = "Definitions",
    resolved_capability = "goto_definition",
    server_capability = "definitionProvider",
    method = "textDocument/definition",
    handler = location_handler
  },
  ["declarations"] = {
    label = "Declarations",
    resolved_capability = "goto_declaration",
    server_capability = "declarationProvider",
    method = "textDocument/declaration",
    handler = location_handler
  },
  ["typedefs"] = {
    label = "Type Definitions",
    resolved_capability = "type_definition",
    server_capability = "typeDefinitionProvider",
    method = "textDocument/typeDefinition",
    handler = location_handler
  },
  ["implementations"] = {
    label = "Implementations",
    resolved_capability = "implementation",
    server_capability = "implementationProvider",
    method = "textDocument/implementation",
    handler = location_handler
  },
  ["document_symbols"] = {
    label = "Document Symbols",
    resolved_capability = "document_symbol",
    server_capability = "documentSymbolProvider",
    method = "textDocument/documentSymbol",
    handler = symbol_handler
  },
  ["workspace_symbols"] = {
    label = "Workspace Symbols",
    resolved_capability = "workspace_symbol",
    server_capability = "workspaceSymbolProvider",
    method = "workspace/symbol",
    handler = symbol_handler
  },
  ["live_workspace_symbols"] = {
    label = "Workspace Symbols",
    resolved_capability = "workspace_symbol",
    server_capability = "workspaceSymbolProvider",
    method = "workspace/symbol",
    handler = symbol_handler
  },
  ["incoming_calls"] = {
    label = "Incoming Calls",
    resolved_capability = "call_hierarchy",
    server_capability = "callHierarchyProvider",
    method = "callHierarchy/incomingCalls",
    handler = call_hierarchy_handler
  },
  ["outgoing_calls"] = {
    label = "Outgoing Calls",
    resolved_capability = "call_hierarchy",
    server_capability = "callHierarchyProvider",
    method = "callHierarchy/outgoingCalls",
    handler = call_hierarchy_handler
  },
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

      -- We only need to set this once.
      if opts.lsp_handler and not opts.lsp_handler.capability then
        if vim.fn.has("nvim-0.8") == 1 then
          opts.lsp_handler.capability = opts.lsp_handler.server_capability
        else
          opts.lsp_handler.capability = opts.lsp_handler.resolved_capability
        end
      end

      if opts.lsp_handler.capability
          and not check_capabilities(opts.lsp_handler.capability) then
        return
      end
      v(opts)
    end
  end

  return mod
end

return wrap_module_fncs(M)
