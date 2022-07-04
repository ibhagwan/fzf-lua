local core = require "fzf-lua.core"
local utils = require "fzf-lua.utils"
local config = require "fzf-lua.config"
local make_entry = require "fzf-lua.make_entry"

local M = {}


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
  opts = config.normalize_opts(opts, config.globals.diagnostics)
  if not opts then return end

  -- required for relative paths presentation
  if not opts.cwd or #opts.cwd == 0 then
    opts.cwd = vim.loop.cwd()
  end

  if not vim.diagnostic then
    local lsp_clients = vim.lsp.buf_get_clients(0)
    if utils.tbl_isempty(lsp_clients) then
      utils.info("LSP: no client attached")
      return
    end
  end

  -- normalize the LSP icons table
  opts._severity_icons = {}
  for k, v in pairs({
    ["Error"]       = 1,
    ["Warning"]     = 2,
    ["Information"] = 3,
    ["Hint"]        = 4
  }) do
    if opts.severity_icons and opts.severity_icons[k] then
      opts._severity_icons[v] = opts.severity_icons[k]
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

  local curbuf = vim.api.nvim_get_current_buf()
  local diag_results = vim.diagnostic and
    vim.diagnostic.get(not opts.diag_all and curbuf or nil, diag_opts) or
    opts.diag_all and vim.lsp.diagnostic.get_all() or
    {[curbuf] = vim.lsp.diagnostic.get(curbuf, opts.client_id)}

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
    utils.info(string.format('No %s found', 'diagnostics'))
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

  local contents = function (fzf_cb)
    coroutine.wrap(function ()
      local co = coroutine.running()

      local function process_diagnostics(diags, bufnr)
        for _, diag in ipairs(diags) do
          -- workspace diagnostics may include
          -- empty tables for unused buffers
          if not vim.tbl_isempty(diag) and filter_diag_severity(opts, diag.severity) then
            -- wrap with 'vim.scheudle' or calls to vim.{fn|api} fail:
            -- E5560: vimL function must not be called in a lua loop callback
            vim.schedule(function()
              local diag_entry = preprocess_diag(diag, bufnr)
              local entry = make_entry.lcol(diag_entry, opts)
              entry = make_entry.file(entry, opts)
              if not entry then
                -- entry to be skipped (e.g. 'cwd_only')
                coroutine.resume(co)
              else
                local type = diag_entry.type
                if opts.diag_icons and opts._severity_icons[type] then
                  local severity = opts._severity_icons[type]
                  local icon = severity.icon
                  if opts.color_icons then
                    icon = utils.ansi_codes[severity.color or "dark_grey"](icon)
                  end
                  entry = icon .. utils.nbsp .. utils.nbsp .. entry
                end
                fzf_cb(entry, function() coroutine.resume(co) end)
              end
            end)
            -- wait here for 'vim.schedule' to return
            coroutine.yield()
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
      fzf_cb(nil)
    end)()
  end

  opts = core.set_header(opts, opts.headers or {"cwd"})
  opts = core.set_fzf_field_index(opts)
  return core.fzf_exec(contents, opts)
end

M.all = function(opts)
  if not opts then opts = {} end
  opts.diag_all = true
  return M.diagnostics(opts)
end

return M
