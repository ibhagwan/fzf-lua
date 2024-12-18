local uv = vim.uv or vim.loop
local core = require "fzf-lua.core"
local path = require "fzf-lua.path"
local utils = require "fzf-lua.utils"
local config = require "fzf-lua.config"
local actions = require "fzf-lua.actions"
local make_entry = require "fzf-lua.make_entry"

local M = {}

local function handler_capability(handler)
  if utils.__HAS_NVIM_08 then
    return handler.server_capability
  else
    return handler.resolved_capability
  end
end

local function check_capabilities(handler, silent)
  local clients = utils.__HAS_NVIM_011
      and vim.lsp.get_clients({ bufnr = core.CTX().bufnr })
      ---@diagnostic disable-next-line: deprecated
      or vim.lsp.buf_get_clients(core.CTX().bufnr)

  -- return the number of clients supporting the feature
  -- so the async version knows how many callbacks to wait for
  local num_clients = 0

  for _, client in pairs(clients) do
    if utils.__HAS_NVIM_09 then
      -- https://github.com/neovim/neovim/blob/65738202f8be3ca63b75197d48f2c7a9324c035b/runtime/doc/news.txt#L118-L122
      -- Dynamic registration of LSP capabilities. An implication of this change is
      -- that checking a client's `server_capabilities` is no longer a sufficient
      -- indicator to see if a server supports a feature. Instead use
      -- `client.supports_method(<method>)`. It considers both the dynamic
      -- capabilities and static `server_capabilities`.
      if client.supports_method(handler.method) then
        num_clients = num_clients + 1
      end
    elseif utils.__HAS_NVIM_08 then
      if client.server_capabilities[handler.server_capability] then
        num_clients = num_clients + 1
      end
    else
      ---@diagnostic disable-next-line: undefined-field
      if client.resolved_capabilities[handler.resolved_capability] then
        num_clients = num_clients + 1
      end
    end
  end

  if num_clients > 0 then
    return num_clients
  end

  -- UI won't open, reset the CTX
  core.__CTX = nil

  if utils.tbl_isempty(clients) then
    if not silent then
      utils.info("LSP: no client attached")
    end
    return nil
  else
    if not silent then
      utils.info("LSP: server does not support " .. handler.method)
    end
    return false
  end
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

  return utils.jump_to_location(result, enc)
end

local regex_filter_fn = function(regex_filter)
  if type(regex_filter) == "string" then
    regex_filter = { regex_filter }
  end
  if type(regex_filter) == "function" then
    return regex_filter
  end
  if type(regex_filter) == "table" and type(regex_filter[1]) == "string" then
    return function(item, _)
      if not item.text then return true end
      local is_match = item.text:match(regex_filter[1]) ~= nil
      if regex_filter.exclude then
        return not is_match
      else
        return is_match
      end
    end
  end
  return false
end

local function location_handler(opts, cb, _, result, ctx, _)
  local encoding = vim.lsp.get_client_by_id(ctx.client_id).offset_encoding
  result = utils.tbl_islist(result) and result or { result }
  -- HACK: make sure target URI is valid for buggy LSPs (#1317)
  for i, x in ipairs(result) do
    for _, k in ipairs({ "uri", "targetUri" }) do
      if type(x[k]) == "string" and not x[k]:match("://") then
        result[i][k] = "file://" .. result[i][k]
      end
    end
  end
  if opts.unique_line_items then
    local lines = {}
    local _result = {}
    for _, loc in ipairs(result) do
      local uri = loc.uri or loc.targetUri
      local range = loc.range or loc.targetSelectionRange
      if not lines[uri .. range.start.line] then
        _result[#_result + 1] = loc
        lines[uri .. range.start.line] = true
      end
    end
    result = _result
  end
  if opts.ignore_current_line then
    local uri = vim.uri_from_bufnr(core.CTX().bufnr)
    local cursor_line = core.CTX().cursor[1] - 1
    result = vim.tbl_filter(function(l)
      if (l.uri
            and l.uri == uri
            and utils.map_get(l, "range.start.line") == cursor_line)
          or
          (l.targetUri
            and l.targetUri == uri
            and utils.map_get(l, "targetRange.start.line") == cursor_line)
      then
        return false
      end
      return true
    end, result)
  end
  local items = {}
  if opts.regex_filter and opts._regex_filter_fn == nil then
    opts._regex_filter_fn = regex_filter_fn(opts.regex_filter)
  end
  -- Although `make_entry.file` filters for `cwd_only` we filter
  -- here to accurately determine `jump_to_single_result` (#980)
  result = vim.tbl_filter(function(x)
    local item = vim.lsp.util.locations_to_items({ x }, encoding)[1]
    if (opts.cwd_only and not path.is_relative_to(item.filename, opts.cwd)) or
        (opts._regex_filter_fn and not opts._regex_filter_fn(item, core.CTX())) then
      return false
    end
    table.insert(items, item)
    return true
  end, result)
  -- Jump immediately if there is only one location
  if opts.jump_to_single_result and #result == 1 then
    jump_to_location(opts, result[1], encoding)
  end
  for _, entry in ipairs(items) do
    if not opts.current_buffer_only or core.CTX().bname == entry.filename then
      entry = make_entry.lcol(entry, opts)
      entry = make_entry.file(entry, opts)
      if entry then cb(entry) end
    end
  end
end

local function call_hierarchy_handler(opts, cb, _, result, ctx, _)
  local encoding = vim.lsp.get_client_by_id(ctx.client_id).offset_encoding
  for _, call_hierarchy_call in pairs(result) do
    --- "from" for incoming calls and "to" for outgoing calls
    local call_hierarchy_item = call_hierarchy_call.from or call_hierarchy_call.to
    for _, range in pairs(call_hierarchy_call.fromRanges) do
      local location = {
        uri = call_hierarchy_item.uri,
        range = range,
        filename = assert(vim.uri_to_fname(call_hierarchy_item.uri)),
        text = call_hierarchy_item.name,
        lnum = range.start.line + 1,
        col = range.start.character + 1,
      }
      if opts.jump_to_single_result and #call_hierarchy_call.fromRanges == 1 then
        jump_to_location(opts, location, encoding)
      end
      local entry = make_entry.lcol(location, opts)
      entry = make_entry.file(entry, opts)
      if entry then cb(entry) end
    end
  end
end

-- Copied from vim.lsp.util.symbols_to_items, then added space prefix to child symbols.
local function symbols_to_items(symbols, bufnr, child_prefix)
  ---@private
  local function _symbols_to_items(_symbols, _items, _bufnr, prefix)
    for _, symbol in ipairs(_symbols) do
      local kind = vim.lsp.protocol.SymbolKind[symbol.kind] or "Unknown"
      if symbol.location then -- SymbolInformation type
        local range = symbol.location.range
        table.insert(_items, {
          filename = vim.uri_to_fname(symbol.location.uri),
          lnum = range.start.line + 1,
          col = range.start.character + 1,
          kind = kind,
          text = prefix .. "[" .. kind .. "] " .. symbol.name,
        })
      elseif symbol.selectionRange then -- DocumentSymbole type
        table.insert(_items, {
          -- bufnr = _bufnr,
          filename = vim.api.nvim_buf_get_name(_bufnr),
          lnum = symbol.selectionRange.start.line + 1,
          col = symbol.selectionRange.start.character + 1,
          kind = kind,
          text = prefix .. "[" .. kind .. "] " .. symbol.name,
        })
        if symbol.children then
          for _, v in ipairs(_symbols_to_items(symbol.children, _items, _bufnr, prefix .. child_prefix)) do
            for _, s in ipairs(v) do
              table.insert(_items, s)
            end
          end
        end
      end
    end
    return _items
  end
  return _symbols_to_items(symbols, {}, bufnr or 0, "")
end

local function symbol_handler(opts, cb, _, result, _, _)
  result = utils.tbl_islist(result) and result or { result }
  local items
  if opts.child_prefix then
    items = symbols_to_items(result, core.CTX().bufnr,
      opts.child_prefix == true and string.rep(" ", 2) or opts.child_prefix)
  else
    items = vim.lsp.util.symbols_to_items(result, core.CTX().bufnr)
  end
  if opts.regex_filter and opts._regex_filter_fn == nil then
    opts._regex_filter_fn = regex_filter_fn(opts.regex_filter)
  end
  for _, entry in ipairs(items) do
    if (not opts.current_buffer_only or core.CTX().bname == entry.filename) and
        (not opts._regex_filter_fn or opts._regex_filter_fn(entry, core.CTX())) then
      local mbicon_align = 0
      if opts.fn_reload and type(opts.query) == "string" and #opts.query > 0 then
        -- highlight exact matches with `live_workspace_symbols` (#1028)
        local sym, text = entry.text:match("^(.+%])(.*)$")
        local pattern = "[" .. utils.lua_regex_escape(
          opts.query:gsub("%a", function(x)
            return string.upper(x) .. string.lower(x)
          end)
        ) .. "]+"
        entry.text = sym .. text:gsub(pattern, function(x)
          return utils.ansi_codes[opts.hls.live_sym](x)
        end)
      end
      if M._sym2style then
        local kind = entry.text:match("%[(.-)%]")
        local styled = kind and M._sym2style[kind]
        if styled then
          entry.text = entry.text:gsub("%[.-%]", styled, 1)
        end
        -- align formatting to single byte and multi-byte icons
        -- only styles 1,2 contain an icon
        if tonumber(opts.symbol_style) == 1 or tonumber(opts.symbol_style) == 2 then
          local icon = opts.symbol_icons and opts.symbol_icons[kind]
          mbicon_align = icon and #icon or mbicon_align
        end
      end
      -- move symbol `entry.text` to the start of the line
      -- will be restored in preview/actions by `opts._fmt.from`
      local symbol = entry.text
      entry.text = nil
      entry = make_entry.lcol(entry, opts)
      entry = make_entry.file(entry, opts)
      if entry then
        local align = 48 + mbicon_align + utils.ansi_escseq_len(symbol)
        -- TODO: string.format %-{n}s fails with align > ~100?
        -- entry = string.format("%-" .. align .. "s%s%s", symbol, utils.nbsp, entry)
        if align > #symbol then
          symbol = symbol .. string.rep(" ", align - #symbol)
        end
        entry = symbol .. utils.nbsp .. entry
        cb(entry)
      end
    end
  end
end

local function code_action_handler(opts, cb, _, code_actions, context, _)
  if not opts.code_actions then opts.code_actions = {} end
  local i = utils.tbl_count(opts.code_actions) + 1
  for _, action in ipairs(code_actions) do
    local text = string.format("%s %s",
      utils.ansi_codes.magenta(string.format("%d:", i)), action.title)
    local entry = {
      client_id = context.client_id,
      command = action,
    }
    opts.code_actions[tostring(i)] = entry
    cb(text)
    i = i + 1
  end
end

local handlers = {
  ["code_actions"] = {
    label = "Code Actions",
    resolved_capability = "code_action",
    server_capability = "codeActionProvider",
    method = "textDocument/codeAction",
    handler = code_action_handler
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
    opts.num_results = (opts.num_results or 0) + (result and utils.tbl_count(result) or 0)
    if err then
      if not opts.silent then
        utils.err(string.format("Error executing '%s': %s", handler.method, err))
      end
      if not opts.no_autoclose then
        utils.fzf_exit()
      end
      coroutine.resume(co, true, err)
    else
      -- did all clients send back their responses?
      local done = opts.num_callbacks == opts.num_clients
      -- only close the window if we still have zero results
      -- after all clients have sent their results
      if done and opts.num_results == 0 then
        if not opts.silent then
          utils.info(string.format("No %s found", string.lower(handler.label)))
        end
        -- Do not close the window in 'live_workspace_symbols'
        if not opts.no_autoclose then
          utils.fzf_exit()
        end
      end
      -- resume the coroutine
      coroutine.resume(co, done, err, result, context, lspcfg)
    end
  end)
end

local function gen_lsp_contents(opts)
  assert(opts.lsp_handler)

  -- consider 'async_or_timeout' only if 'async' wasn't manually set
  if opts.async == nil then
    if type(opts.async_or_timeout) == "number" then
      opts.async = false
    elseif type(opts.async_or_timeout) == "boolean" then
      opts.async = opts.async_or_timeout
    end
  end

  -- Save a function local copy of the lsp parameters and handler
  -- otherwise these will get overwritten when calling the generator
  -- more than once as we do in the `finder` provider
  local lsp_params, lsp_handler = opts.lsp_params, opts.lsp_handler

  -- build positional params for the LSP query
  -- from the context buffer and cursor position
  if not lsp_params then
    lsp_params = function(client)
      local params = vim.lsp.util.make_position_params(core.CTX().winid,
        -- nvim 0.11 requires offset_encoding param, `client` is first arg of called func
        -- https://github.com/neovim/neovim/commit/629483e24eed3f2c07e55e0540c553361e0345a2
        client and client.offset_encoding or nil)
      params.context = {
        includeDeclaration = opts.includeDeclaration == nil and true or opts.includeDeclaration
      }
      return params
    end
    if not utils.__HAS_NVIM_011 and type(lsp_params) == "function" then
      lsp_params = lsp_params()
    end
  end

  if not opts.async then
    -- SYNC
    local timeout = 5000
    if type(opts.async_or_timeout) == "number" then
      timeout = opts.async_or_timeout
    end
    local lsp_results, err = vim.lsp.buf_request_sync(core.CTX().bufnr,
      lsp_handler.method, lsp_params, timeout)
    if err then
      utils.err(string.format("Error executing '%s': %s", lsp_handler.method, err))
    else
      local results = {}
      local cb = function(text) table.insert(results, text) end
      for client_id, response in pairs(lsp_results) do
        if response.result then
          local context = { client_id = client_id }
          lsp_handler.handler(opts, cb, lsp_handler.method, response.result, context)
        end
      end
      if utils.tbl_isempty(results) then
        if not opts.fn_reload and not opts.silent then
          utils.info(string.format("No %s found", string.lower(lsp_handler.label)))
        else
          -- return an empty set or the results wouldn't be
          -- cleared on live_workspace_symbols (#468)
          opts.__contents = {}
        end
      elseif not (opts.jump_to_single_result and #results == 1) then
        -- LSP request was synchronous but we still asyncify the fzf feeding
        opts.__contents = function(fzf_cb)
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

    opts.__contents = function(fzf_cb)
      coroutine.wrap(function()
        local co = coroutine.running()

        -- Save no. of attached clients **supporting the capability**
        -- so we can determine if all callbacks were completed (#468)
        local async_opts = {
          num_results   = 0,
          num_callbacks = 0,
          num_clients   = check_capabilities(lsp_handler, opts.silent),
          -- signals the handler to not print a warning when empty result set
          -- is returned, important for `live_workspace_symbols` when the user
          -- inputs a query that returns no results
          -- also used with `finder` to prevent the window from being closed
          no_autoclose  = opts.no_autoclose or opts.fn_reload,
          silent        = opts.silent or opts.fn_reload,
        }

        -- when used with 'live_workspace_symbols'
        -- cancel all lingering LSP queries
        fn_cancel_all(opts)

        local async_buf_request = function()
          -- save cancel all fnref so we can cancel all requests
          -- when using `live_ws_symbols`
          _, opts._cancel_all = vim.lsp.buf_request(core.CTX().bufnr,
            lsp_handler.method, lsp_params,
            async_lsp_handler(co, lsp_handler, async_opts))
        end

        -- When called from another coroutine callback (when using 'finder') will err:
        -- E5560: nvim_exec_autocmds must not be called in a lua loop callback nil
        if vim.in_fast_event() then
          vim.schedule(function()
            async_buf_request()
          end)
        else
          async_buf_request()
        end

        -- process results from all LSP client
        local err, result, context, lspcfg, done
        repeat
          done, err, result, context, lspcfg = coroutine.yield()
          if not err and type(result) == "table" then
            local cb = function(e)
              fzf_cb(e, function() coroutine.resume(co) end)
              coroutine.yield()
            end
            lsp_handler.handler(opts, cb, lsp_handler.method, result, context, lspcfg)
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

  return opts, opts.__contents
end

-- see $VIMRUNTIME/lua/vim/buf.lua:pick_call_hierarchy_item()
local function gen_lsp_contents_call_hierarchy(opts)
  local lsp_params = opts.lsp_params
      or not utils.__HAS_NVIM_011 and vim.lsp.util.make_position_params(core.CTX().winid)
      or function(client)
        return vim.lsp.util.make_position_params(core.CTX().winid, client.offset_encoding)
      end
  local method = "textDocument/prepareCallHierarchy"
  local res, err = vim.lsp.buf_request_sync(0, method, lsp_params, 2000)
  if err then
    utils.err(("Error executing '%s': %s"):format(method, err))
  else
    local _, response = next(res)
    if not response or not response.result or not response.result[1] then
      if not opts.silent then
        utils.info(("No %s found"):format(opts.lsp_handler.label:lower()))
      end
      return
    end
    assert(response.result and response.result[1])
    opts.lsp_params = { item = response.result[1] }
    return gen_lsp_contents(opts)
  end
end

local normalize_lsp_opts = function(opts, cfg, __resume_key)
  opts = config.normalize_opts(opts, cfg, __resume_key)
  if not opts then return end

  -- `title_prefix` is priortized over both `prompt` and `prompt_prefix`
  if (not opts.winopts or opts.winopts.title == nil) and opts.title_prefix then
    utils.map_set(opts,
      "winopts.title", string.format(" %s %s ", opts.title_prefix, opts.lsp_handler.label))
  elseif opts.prompt == nil and opts.prompt_postfix then
    opts.prompt = opts.lsp_handler.label .. (opts.prompt_postfix or "")
  end

  -- required for relative paths presentation
  if not opts.cwd or #opts.cwd == 0 then
    opts.cwd = uv.cwd()
  elseif opts.cwd_only == nil then
    opts.cwd_only = true
  end

  return opts
end

local function fzf_lsp_locations(opts, fn_contents)
  opts = normalize_lsp_opts(opts, "lsp")
  if not opts then return end
  opts = core.set_fzf_field_index(opts)
  opts = fn_contents(opts)
  if not opts.__contents then
    core.__CTX = nil
    return
  end
  opts = core.set_header(opts, opts.headers or { "cwd", "regex_filter" })
  return core.fzf_exec(opts.__contents, opts)
end

-- define the functions for wrap_module_fncs
M.references = function(opts)
  return fzf_lsp_locations(opts, gen_lsp_contents)
end

M.definitions = function(opts)
  return fzf_lsp_locations(opts, gen_lsp_contents)
end

M.declarations = function(opts)
  return fzf_lsp_locations(opts, gen_lsp_contents)
end

M.typedefs = function(opts)
  return fzf_lsp_locations(opts, gen_lsp_contents)
end

M.implementations = function(opts)
  return fzf_lsp_locations(opts, gen_lsp_contents)
end

M.incoming_calls = function(opts)
  return fzf_lsp_locations(opts, gen_lsp_contents_call_hierarchy)
end

M.outgoing_calls = function(opts)
  return fzf_lsp_locations(opts, gen_lsp_contents_call_hierarchy)
end

M.finder = function(opts)
  opts = normalize_lsp_opts(opts, "lsp.finder")
  if not opts then return end
  local contents = {}
  local lsp_params = opts.lsp_params
  for _, p in ipairs(opts.providers) do
    local method = p[1]
    if not opts._providers[method] then
      utils.warn(string.format("Unsupported provider: %s", method))
    else
      opts.silent = opts.silent == nil and true or opts.silent
      opts.no_autoclose = true
      opts.lsp_handler = handlers[method]
      opts.lsp_handler.capability = handler_capability(opts.lsp_handler)
      opts.lsp_params = lsp_params -- reset previous calls params if existed

      -- returns nil for no client attached, false for unsupported capability
      -- we only abort if no client is attached
      local check = check_capabilities(opts.lsp_handler, true)
      if check == nil then
        utils.info("LSP: no client attached")
        return
      elseif check then
        local _, c = (function()
          if method == "incoming_calls" or method == "outgoing_calls" then
            return gen_lsp_contents_call_hierarchy(opts)
          else
            return gen_lsp_contents(opts)
          end
        end)()
        -- make sure we add only valid contents
        -- sync returns empty table when no results are found
        if type(c) == "function" then
          table.insert(contents,
            { prefix = (p.prefix or "") .. (opts.separator or ""), contents = c })
        end
      end
    end
  end
  if #contents == 0 then
    utils.info("LSP: no locations found")
    core.__CTX = nil
    return
  end
  opts = core.set_header(opts, opts.headers or { "cwd", "regex_filter" })
  opts = core.set_fzf_field_index(opts)
  return core.fzf_exec(contents, opts)
end

local function gen_sym2style_map(opts)
  assert(opts.symbol_style ~= nil)
  if M._sym2style then return end
  M._sym2style = {}
  for kind, icon in pairs(opts.symbol_icons) do
    -- style==1: "<icon> <kind>"
    -- style==2: "<icon>"
    -- style==3: "<kind>"
    local s = nil
    if tonumber(opts.symbol_style) == 1 then
      s = ("%s %s"):format(icon, kind)
    elseif tonumber(opts.symbol_style) == 2 then
      s = icon
    elseif tonumber(opts.symbol_style) == 3 then
      s = kind
    end
    if s and opts.symbol_hl then
      M._sym2style[kind] = utils.ansi_from_hl(opts.symbol_hl(kind), s)
    elseif s then
      M._sym2style[kind] = s
    else
      -- can get here when only 'opts.symbol_fmt' was set
      M._sym2style[kind] = kind
    end
  end
  if type(opts.symbol_fmt) == "function" then
    for k, v in pairs(M._sym2style) do
      M._sym2style[k] = opts.symbol_fmt(v, opts) or v
    end
  end
end

M.document_symbols = function(opts)
  opts = normalize_lsp_opts(opts, "lsp.symbols", "lsp_document_symbols")
  if not opts then return end
  -- no support for sym_lsym
  for k, fn in pairs(opts.actions or {}) do
    if type(fn) == "table" and
        (fn[1] == actions.sym_lsym or fn.fn == actions.sym_lsym) then
      opts.actions[k] = nil
    end
  end
  opts = core.set_header(opts, opts.headers or { "regex_filter" })
  opts = core.set_fzf_field_index(opts)
  if not opts.fzf_opts or opts.fzf_opts["--with-nth"] == nil then
    -- our delims are {nbsp,:} make sure entry has no icons
    -- "{nbsp}file:line:col:" and hide the last 4 fields
    opts.git_icons = false
    opts.file_icons = false
    opts.fzf_opts = opts.fzf_opts or {}
    opts.fzf_opts["--with-nth"] = "..-4"
  end
  if opts.symbol_style or opts.symbol_fmt then
    opts.fn_pre_fzf = function() gen_sym2style_map(opts) end
    opts.fn_post_fzf = function() M._sym2style = nil end
    -- run once in case we're not running async
    opts.fn_pre_fzf()
  end
  opts = gen_lsp_contents(opts)
  if not opts.__contents then
    core.__CTX = nil
    return
  end
  return core.fzf_exec(opts.__contents, opts)
end

M.workspace_symbols = function(opts)
  opts = normalize_lsp_opts(opts, "lsp.symbols", "lsp_workspace_symbols")
  if not opts then return end
  opts.__ACT_TO = opts.__ACT_TO or M.live_workspace_symbols
  opts.lsp_params = { query = opts.lsp_query or "" }
  opts = core.set_header(opts, opts.headers or
    { "actions", "cwd", "lsp_query", "regex_filter" })
  opts = core.set_fzf_field_index(opts)
  opts = gen_lsp_contents(opts)
  if not opts.__contents then
    core.__CTX = nil
    return
  end
  if opts.symbol_style or opts.symbol_fmt then
    opts.fn_pre_fzf = function() gen_sym2style_map(opts) end
    opts.fn_post_fzf = function() M._sym2style = nil end
  end
  return core.fzf_exec(opts.__contents, opts)
end


M.live_workspace_symbols = function(opts)
  opts = normalize_lsp_opts(opts, "lsp.symbols", "lsp_workspace_symbols")
  if not opts then return end

  -- needed by 'actions.sym_lsym'
  opts.__ACT_TO = opts.__ACT_TO or M.workspace_symbols

  -- prepend prompt with "*" to indicate "live" query
  opts.prompt = type(opts.prompt) == "string" and opts.prompt or ""
  if opts.live_ast_prefix ~= false then
    opts.prompt = opts.prompt:match("^%*") and opts.prompt or ("*" .. opts.prompt)
  end

  -- when using live_workspace_symbols there is no "query"
  -- the prompt input is the LSP query, store as "lsp_query"
  opts.__resume_set = function(what, val, o)
    config.resume_set(
      what == "query" and "lsp_query" or what, val,
      { __resume_key = o.__resume_key })
    utils.map_set(config, "__resume_data.last_query", val)
    -- also store query for `fzf_resume` (#963)
    utils.map_set(config, "__resume_data.opts.query", val)
    -- store in opts for convenience in action callbacks
    o.last_query = val
  end
  opts.__resume_get = function(what, o)
    return config.resume_get(
      what == "query" and "lsp_query" or what,
      { __resume_key = o.__resume_key })
  end

  -- if no lsp_query was set, use previous prompt query (from the non-live version)
  if not opts.lsp_query or #opts.lsp_query == 0 and (opts.query and #opts.query > 0) then
    opts.lsp_query = opts.query
    -- also replace in `__call_opts` for `resume=true`
    opts.__call_opts.query = nil
    opts.__call_opts.lsp_query = opts.query
  end

  -- sent to the LSP server
  opts.lsp_params = { query = opts.lsp_query or opts.query or "" }
  opts.query = opts.lsp_query or opts.query

  -- don't use the automatic coroutine since we
  -- use our own
  opts.func_async_callback = false
  opts.fn_reload = function(query)
    opts.query = query
    opts.lsp_params = { query = query or "" }
    opts = gen_lsp_contents(opts)
    return opts.__contents
  end

  opts = core.set_header(opts, opts.headers or { "actions", "cwd", "regex_filter" })
  opts = core.set_fzf_field_index(opts)
  if opts.symbol_style or opts.symbol_fmt then
    opts.fn_pre_fzf = function() gen_sym2style_map(opts) end
    opts.fn_post_fzf = function() M._sym2style = nil end
  end
  return core.fzf_exec(nil, opts)
end

-- Converts 'vim.diagnostic.get' to legacy style 'get_line_diagnostics()'
-- TODO: not needed anymore, it seems that `vim.lsp.buf.code_action` still
-- uses the old `vim.lsp.diagnostic` API, we will do the same until neovim
-- stops using this API
--[[ local function get_line_diagnostics(_)
  if not vim.diagnostic then
    return vim.lsp.diagnostic.get_line_diagnostics()
  end
  local diag = vim.diagnostic.get(core.CTX().bufnr, { lnum = vim.api.nvim_win_get_cursor(0)[1] - 1 })
  return diag and diag[1]
      and { {
        source = diag[1].source,
        message = diag[1].message,
        severity = diag[1].severity,
        code = diag[1].user_data and diag[1].user_data.lsp and diag[1].user_data.lsp.code,
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
        data = diag[1].user_data and diag[1].user_data.lsp and diag[1].user_data.lsp.data
      } }
      -- Must return an empty table or some LSP servers fail (#707)
      or {}
end ]]

M.code_actions = function(opts)
  opts = normalize_lsp_opts(opts, "lsp.code_actions")
  if not opts then return end

  -- code actions uses `vim.ui.select`, requires neovim >= 0.6
  if vim.fn.has("nvim-0.6") ~= 1 then
    utils.info("LSP code actions requires neovim >= 0.6")
    return
  end

  local ui_select = require "fzf-lua.providers.ui_select"
  local registered = ui_select.is_registered()

  -- when fzf-lua isn't registered for ui.select we need to test if
  -- code actions exist before calling `vim.lsp.buf.code_action()`
  -- if code actions don't exist the deregister callback is never
  -- called and we remain registered
  if not registered then
    -- irrelevant for code actions and can cause
    -- single results to be skipped with 'async = false'
    opts.jump_to_single_result = false
    opts.lsp_params = function(client)
      local params = vim.lsp.util.make_range_params(core.CTX().winid,
        -- nvim 0.11 requires offset_encoding param, `client` is first arg of called func
        -- https://github.com/neovim/neovim/commit/629483e24eed3f2c07e55e0540c553361e0345a2
        client and client.offset_encoding or nil)
      params.context = opts.context or {
        -- Neovim still uses `vim.lsp.diagnostic` API in "nvim/runtime/lua/vim/lsp/buf.lua"
        -- continue to use it until proven otherwise, this also fixes #707 as diagnostics
        -- must not be nil or some LSP servers will fail (e.g. ruff_lsp, rust_analyzer)
        diagnostics = vim.lsp.diagnostic.get_line_diagnostics(core.CTX().bufnr) or {}
      }
      return params
    end
    if not utils.__HAS_NVIM_011 and type(opts.lsp_params) == "function" then
      opts.lsp_params = opts.lsp_params()
    end

    -- make sure 'gen_lsp_contents' is run synchronously
    opts.async = false

    -- when 'opts.async == false' calls 'vim.lsp.buf_request_sync'
    -- so we can avoid calling 'ui_select.register' when no code
    -- actions are available
    local _, has_code_actions = gen_lsp_contents(opts)

    -- error or no sync request no results
    if not has_code_actions then
      core.__CTX = nil
      return
    end
  end

  opts.actions = opts.actions or {}
  opts.actions.enter = nil
  -- only dereg if we aren't registered
  if not registered then
    opts.post_action_cb = function()
      ui_select.deregister({}, true, true)
    end
  end
  -- 3rd arg are "once" options to override
  -- existing "registered" ui_select options
  ui_select.register(opts, true, opts)
  vim.lsp.buf.code_action({ context = opts.context, filter = opts.filter })
  -- vim.defer_fn(function()
  --   ui_select.deregister({}, true, true)
  -- end, 100)
end

local function wrap_fn(key, fn)
  return function(opts)
    opts = opts or {}
    opts.lsp_handler = handlers[key]
    opts.lsp_handler.capability = handler_capability(opts.lsp_handler)

    -- check_capabilities will print the appropriate warning
    if not check_capabilities(opts.lsp_handler) then
      return
    end

    -- Call the original method
    return fn(opts)
  end
end

return setmetatable({}, {
  __index = function(_, key)
    if handlers[key] then
      return wrap_fn(key, M[key])
    else
      return M[key]
    end
  end
})
