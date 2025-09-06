local uv = vim.uv or vim.loop
local core = require "fzf-lua.core"
local path = require "fzf-lua.path"
local utils = require "fzf-lua.utils"
local config = require "fzf-lua.config"
local actions = require "fzf-lua.actions"
local make_entry = require "fzf-lua.make_entry"

local M = {}

local function check_capabilities(handler, silent)
  local clients = utils.lsp_get_clients({ bufnr = utils.CTX().bufnr })

  -- return the number of clients supporting the feature
  -- so the async version knows how many callbacks to wait for
  local num_clients = 0

  for _, client in pairs(clients) do
    -- https://github.com/neovim/neovim/blob/65738202f8be3ca63b75197d48f2c7a9324c035b/runtime/doc/news.txt#L118-L122
    -- Dynamic registration of LSP capabilities. An implication of this change is
    -- that checking a client's `server_capabilities` is no longer a sufficient
    -- indicator to see if a server supports a feature. Instead use
    -- `client.supports_method(<method>)`. It considers both the dynamic
    -- capabilities and static `server_capabilities`.
    if client:supports_method(handler.prep or handler.method) then
      num_clients = num_clients + 1
    end
  end

  if num_clients > 0 then
    return num_clients
  end

  -- UI won't open, reset the CTX
  utils.clear_CTX()

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

  local action = opts.jump1_action
  if action then
    local entry = location_to_entry(result, enc)
    return opts.jump1_action({ entry }, opts)
  end

  return utils.jump_to_location(result, enc, opts.reuse_win)
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
      if type(x[k]) == "string" and not x[k]:match("^([a-zA-Z]+[a-zA-Z0-9.+-]*):.*") then
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
    local uri = vim.uri_from_bufnr(utils.CTX().bufnr)
    local cursor_line = utils.CTX().cursor[1] - 1
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
  local entries = {}
  if opts.regex_filter and opts._regex_filter_fn == nil then
    opts._regex_filter_fn = regex_filter_fn(opts.regex_filter)
  end
  -- Although `make_entry.file` filters for `cwd_only` we filter
  -- here to accurately determine `jump1` (#980)
  result = vim.tbl_filter(function(x)
    local item = vim.lsp.util.locations_to_items({ x }, encoding)[1]
    if (opts.cwd_only and not path.is_relative_to(item.filename, opts.cwd)) or
        (opts._regex_filter_fn and not opts._regex_filter_fn(item, utils.CTX())) then
      return false
    end
    if opts.current_buffer_only and not path.equals(utils.CTX().bname, item.filename) then
      return false
    end
    local entry = make_entry.lcol(item, opts)
    entry = make_entry.file(entry, opts)
    if not entry then
      -- Filtered by cwd / file_ignore_patterns, etc
      return false
    else
      table.insert(entries, { entry = entry, result = x, encoding = encoding })
      return true
    end
  end, result)
  -- Populate post-filter entries
  vim.tbl_map(function(x) cb(x.entry, x) end, entries)
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
      local entry = make_entry.lcol(location, opts)
      entry = make_entry.file(entry, opts)
      if entry then cb(entry, { result = location, encoding = encoding }) end
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

local function symbol_handler(opts, cb, _, result, ctx, _)
  result = utils.tbl_islist(result) and result or { result }
  local items
  if opts.child_prefix then
    items = symbols_to_items(result, utils.CTX().bufnr,
      opts.child_prefix == true and string.rep(" ", 2) or opts.child_prefix)
  else
    local encoding = vim.lsp.get_client_by_id(ctx.client_id).offset_encoding
    items = vim.lsp.util.symbols_to_items(result, utils.CTX().bufnr, encoding)
  end
  if opts.regex_filter and opts._regex_filter_fn == nil then
    opts._regex_filter_fn = regex_filter_fn(opts.regex_filter)
  end
  for _, entry in ipairs(items) do
    if (not opts.current_buffer_only or utils.CTX().bname == entry.filename) and
        (not opts._regex_filter_fn or opts._regex_filter_fn(entry, utils.CTX())) then
      local mbicon_align = 0
      if opts.is_live and type(opts.query) == "string" and #opts.query > 0 then
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
      local entry0 = make_entry.lcol(entry, opts)
      local entry1 = make_entry.file(entry0, opts)
      if entry1 then
        if opts.locate and not opts.__locate_pos then
          opts.__locate_count = opts.__locate_count or 0
          opts.__locate_count = opts.__locate_count + 1
          if entry.lnum == utils.CTX().cursor[1] then
            opts.__locate_pos = opts.__locate_count
          end
        end
        if opts.__sym_bufnr and not opts.pickers then -- use old format on "global" picker
          -- document_symbols
          entry1 = string.format("[%s]%s%s:%s:%s\t\t%s",
            utils.ansi_codes[opts.hls.buf_nr](tostring(opts.__sym_bufnr)),
            utils.nbsp,
            utils.ansi_codes[opts.hls.buf_name](opts.__sym_bufname),
            utils.ansi_codes[opts.hls.buf_linenr](tostring(entry.lnum)),
            utils.ansi_codes[opts.hls.path_colnr](tostring(entry.col)),
            symbol)
        else
          -- workspace_symbols
          local align = 48 + mbicon_align + utils.ansi_escseq_len(symbol)
          -- TODO: string.format %-{n}s fails with align > ~100?
          -- entry1 = string.format("%-" .. align .. "s%s%s", symbol, utils.nbsp, entry1)
          if align > #symbol then
            symbol = symbol .. string.rep(" ", align - #symbol)
          end
          entry1 = symbol .. utils.nbsp .. entry1
        end
        cb(entry1)
      end
    end
  end
end

local handlers = {
  ["code_actions"] = {
    label = "Code Actions",
    server_capability = "codeActionProvider",
    method = "textDocument/codeAction",
  },
  ["references"] = {
    label = "References",
    server_capability = "referencesProvider",
    method = "textDocument/references",
    handler = location_handler
  },
  ["definitions"] = {
    label = "Definitions",
    server_capability = "definitionProvider",
    method = "textDocument/definition",
    handler = location_handler
  },
  ["declarations"] = {
    label = "Declarations",
    server_capability = "declarationProvider",
    method = "textDocument/declaration",
    handler = location_handler
  },
  ["typedefs"] = {
    label = "Type Definitions",
    server_capability = "typeDefinitionProvider",
    method = "textDocument/typeDefinition",
    handler = location_handler
  },
  ["implementations"] = {
    label = "Implementations",
    server_capability = "implementationProvider",
    method = "textDocument/implementation",
    handler = location_handler
  },
  ["document_symbols"] = {
    label = "Document Symbols",
    server_capability = "documentSymbolProvider",
    method = "textDocument/documentSymbol",
    handler = symbol_handler
  },
  ["workspace_symbols"] = {
    label = "Workspace Symbols",
    server_capability = "workspaceSymbolProvider",
    method = "workspace/symbol",
    handler = symbol_handler
  },
  ["live_workspace_symbols"] = {
    label = "Workspace Symbols",
    server_capability = "workspaceSymbolProvider",
    method = "workspace/symbol",
    handler = symbol_handler
  },
  ["incoming_calls"] = {
    label = "Incoming Calls",
    server_capability = "callHierarchyProvider",
    method = "callHierarchy/incomingCalls",
    prep = "textDocument/prepareCallHierarchy",
    handler = call_hierarchy_handler
  },
  ["outgoing_calls"] = {
    label = "Outgoing Calls",
    server_capability = "callHierarchyProvider",
    method = "callHierarchy/outgoingCalls",
    prep = "textDocument/prepareCallHierarchy",
    handler = call_hierarchy_handler
  },
}

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
    ---@param client vim.lsp.Client
    ---@return table?
    lsp_params = function(client)
      local params = vim.lsp.util.make_position_params(utils.CTX().winid,
        -- nvim 0.11 requires offset_encoding param, `client` is first arg of called func
        -- https://github.com/neovim/neovim/commit/629483e24eed3f2c07e55e0540c553361e0345a2
        client and client.offset_encoding or nil)
      ---@diagnostic disable-next-line: inject-field
      params.context = {
        includeDeclaration = opts.includeDeclaration == nil and true or opts.includeDeclaration
      }
      return params
    end
    if not utils.__HAS_NVIM_011 and type(lsp_params) == "function" then
      ---@diagnostic disable-next-line: missing-parameter
      lsp_params = lsp_params()
    end
  end

  if not opts.async then
    -- SYNC
    local timeout = 5000
    if type(opts.async_or_timeout) == "number" then
      timeout = opts.async_or_timeout
    end
    local lsp_results, err = vim.lsp.buf_request_sync(utils.CTX().bufnr,
      lsp_handler.method, lsp_params, timeout)
    if err then
      utils.error("Error executing '%s': %s", lsp_handler.method, err)
    else
      local results = {}
      local jump1
      local cb = function(text, x)
        -- Only populate jump1 with the first entry
        if jump1 then jump1 = false end
        if x and jump1 == nil then jump1 = { result = x.result, encoding = x.encoding } end
        table.insert(results, text)
      end
      for client_id, response in pairs(lsp_results) do
        if response.result then
          local context = { client_id = client_id }
          lsp_handler.handler(opts, cb, lsp_handler.method, response.result, context, nil)
        elseif response.error then
          utils.error("Error executing '%s': %s", lsp_handler.method, response.error.message)
        end
      end
      if utils.tbl_isempty(results) then
        if opts.is_live then
          -- return an empty set or the results wouldn't be
          -- cleared on live_workspace_symbols (#468)
          opts.__contents = {}
        elseif not opts.silent then
          utils.info("No %s found", string.lower(lsp_handler.label))
        end
      elseif opts.jump1 and jump1 then
        jump_to_location(opts, jump1.result, jump1.encoding)
      else
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
    opts.fn_selected = function(...)
      fn_cancel_all(opts)
      actions.act(...)
    end

    opts.__contents = function(fzf_cb)
      coroutine.wrap(function()
        local co = coroutine.running()

        -- Save no. of attached clients **supporting the capability**
        -- so we can determine if all callbacks were completed (#468)
        local async_opts = {
          num_callbacks = 0,
          num_clients   = check_capabilities(lsp_handler, opts.silent),
          -- signals the handler to not print a warning when empty result set
          -- is returned, important for `live_workspace_symbols` when the user
          -- inputs a query that returns no results
          -- also used with `finder` to prevent the window from being closed
          no_autoclose  = opts.no_autoclose or opts.is_live,
          silent        = opts.silent or opts.is_live,
        }

        -- when used with 'live_workspace_symbols'
        -- cancel all lingering LSP queries
        fn_cancel_all(opts)

        local async_buf_request = function()
          -- save cancel all fnref so we can cancel all requests
          -- when using `live_ws_symbols`
          _, opts._cancel_all = vim.lsp.buf_request(utils.CTX().bufnr,
            lsp_handler.method, lsp_params,
            function(err, result, context, lspcfg)
              -- Increment client callback counter
              async_opts.num_callbacks = async_opts.num_callbacks + 1
              -- did all clients send back their responses?
              local done = async_opts.num_callbacks == async_opts.num_clients
              if err and not async_opts.silent then
                utils.error("Error executing '%s': %s", lsp_handler.method, err)
              end
              coroutine.resume(co, done, err, result, context, lspcfg)
            end)
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
        local num_results, jump1 = 0, nil
        repeat
          done, err, result, context, lspcfg = coroutine.yield()
          if not err and type(result) == "table" then
            local cb = function(e, x)
              -- Increment result callback counter
              num_results = num_results + 1
              -- Only populate jump1 with the first entry
              if jump1 then jump1 = false end
              if x and jump1 == nil then jump1 = { result = x.result, encoding = x.encoding } end
              fzf_cb(e, function() coroutine.resume(co) end)
              coroutine.yield()
            end
            lsp_handler.handler(opts, cb, lsp_handler.method, result, context, lspcfg)
          end
          -- some clients may not always return results (null-ls?)
          -- so don't terminate the loop when 'result == nil`
        until done

        -- no more results
        fzf_cb(nil)

        vim.schedule(function()
          if num_results == 0 then
            if not async_opts.silent then
              utils.info("No %s found", string.lower(lsp_handler.label))
            end
            if not async_opts.no_autoclose then
              utils.fzf_exit()
            end
          elseif opts.jump1 and jump1 then
            utils.fzf_exit()
            jump_to_location(opts, jump1.result, jump1.encoding)
          end
        end)

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
  local timeout = 5000
  if type(opts.async_or_timeout) == "number" then
    timeout = opts.async_or_timeout
  end
  local lsp_params = opts.lsp_params
      ---@diagnostic disable-next-line: missing-parameter
      or not utils.__HAS_NVIM_011 and vim.lsp.util.make_position_params(utils.CTX().winid)
      or function(client)
        return vim.lsp.util.make_position_params(utils.CTX().winid, client.offset_encoding)
      end
  local res, err = vim.lsp.buf_request_sync(
    utils.CTX().bufnr, opts.lsp_handler.prep, lsp_params, timeout)
  if err then
    utils.error(("Error executing '%s': %s"):format(opts.lsp_handler.prep, err))
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
  ---@type fzf-lua.config.Lsp
  opts = normalize_lsp_opts(opts, "lsp")
  if not opts then return end
  opts = core.set_fzf_field_index(opts)
  opts = fn_contents(opts)
  if not opts or not opts.__contents then
    utils.clear_CTX()
    return
  end
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
  ---@type fzf-lua.config.LspFinder
  opts = normalize_lsp_opts(opts, "lsp.finder")
  if not opts then return end
  local contents = {}
  local lsp_params = opts.lsp_params
  for _, p in ipairs(opts.providers) do
    local method = p[1]
    if not opts._providers[method] then
      utils.warn("Unsupported provider: %s", method)
    else
      opts.silent = opts.silent == nil and true or opts.silent
      opts.no_autoclose = true
      opts.lsp_handler = handlers[method]
      opts.lsp_handler.capability = opts.lsp_handler.server_capability
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
    utils.clear_CTX()
    return
  end
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
  ---@type fzf-lua.config.LspDocumentSymbols
  opts = normalize_lsp_opts(opts, "lsp.document_symbols")
  if not opts then return end
  opts.__sym_bufnr = utils.CTX().bufnr
  opts.__sym_bufname = utils.nvim_buf_get_name(opts.__sym_bufnr)
  opts = core.set_fzf_field_index(opts)
  if opts.symbol_style or opts.symbol_fmt then
    M._sym2style = nil
    gen_sym2style_map(opts)
  end
  opts = gen_lsp_contents(opts)
  if not opts.__contents then
    utils.clear_CTX()
    return
  end
  return core.fzf_exec(opts.__contents, opts)
end

M.workspace_symbols = function(opts)
  ---@type fzf-lua.config.LspWorkspaceSymbols
  opts = normalize_lsp_opts(opts, "lsp.workspace_symbols")
  if not opts then return end
  opts.locate = false -- Makes no sense for workspace symbols
  opts.__ACT_TO = opts.__ACT_TO or M.live_workspace_symbols
  opts.__call_fn = utils.__FNCREF__()
  opts.lsp_params = { query = opts.lsp_query or "" }
  if type(opts._headers) == "table" then table.insert(opts._headers, "lsp_query") end
  opts = core.set_fzf_field_index(opts)
  opts = gen_lsp_contents(opts)
  if not opts.__contents then
    utils.clear_CTX()
    return
  end
  if utils.has(opts, "fzf") and not opts.prompt and opts.lsp_query and #opts.lsp_query > 0 then
    opts.prompt = utils.ansi_from_hl(opts.hls.live_prompt, opts.lsp_query) .. " > "
  end
  if opts.symbol_style or opts.symbol_fmt then
    M._sym2style = nil
    gen_sym2style_map(opts)
  end
  return core.fzf_exec(opts.__contents, opts)
end


M.live_workspace_symbols = function(opts)
  ---@type fzf-lua.config.LspLiveWorkspaceSymbols
  opts = normalize_lsp_opts(opts, "lsp.workspace_symbols")
  if not opts then return end

  -- needed by 'actions.sym_lsym'
  opts.__ACT_TO = opts.__ACT_TO or M.workspace_symbols
  opts.__call_fn = utils.__FNCREF__()

  -- NOTE: no longer used since we hl the query with `FzfLuaLivePrompt`
  -- prepend prompt with "*" to indicate "live" query
  -- opts.prompt = type(opts.prompt) == "string" and opts.prompt or "> "
  -- if opts.live_ast_prefix ~= false then
  --   opts.prompt = opts.prompt:match("^%*") and opts.prompt or ("*" .. opts.prompt)
  -- end

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

  opts = core.set_fzf_field_index(opts)
  if opts.symbol_style or opts.symbol_fmt then
    M._sym2style = nil
    gen_sym2style_map(opts)
  end
  return core.fzf_live(function(args)
    opts.query = args[1]
    opts.lsp_params = { query = args[1] or "" }
    opts = gen_lsp_contents(opts)
    return opts.__contents
  end, opts)
end

M.code_actions = function(opts)
  ---@type fzf-lua.config.LspCodeActions
  opts = normalize_lsp_opts(opts, "lsp.code_actions")
  if not opts then return end

  -- code actions uses `vim.ui.select`, requires neovim >= 0.6
  if vim.fn.has("nvim-0.6") ~= 1 then
    utils.info("LSP code actions requires neovim >= 0.6")
    return
  end

  local ui_select = require "fzf-lua.providers.ui_select"
  local registered = ui_select.is_registered()

  if not registered and not opts.silent then
    utils.warn("FzfLua is not currently registered as 'vim.ui.select' backend, use 'silent=true'" ..
      " to hide this message or register globally using ':FzfLua register_ui_select'.")
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
  vim.lsp.buf.code_action({
    apply = opts.jump1 or opts.fzf_opts["-1"] or opts.fzf_opts["--select-1"],
    context = opts.context,
    filter = opts.filter,
  })
  -- vim.defer_fn(function()
  --   ui_select.deregister({}, true, true)
  -- end, 100)
end

local function wrap_fn(key, fn)
  return function(opts)
    opts = opts or {}
    opts.lsp_handler = handlers[key]
    opts.lsp_handler.capability = opts.lsp_handler.server_capability

    -- check_capabilities will print the appropriate warning
    if not check_capabilities(opts.lsp_handler, opts.silent) then
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
