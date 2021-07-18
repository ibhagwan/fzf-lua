if not pcall(require, "fzf") then
  return
end

-- local fzf = require "fzf"
-- local fzf_helpers = require("fzf.helpers")
-- local path = require "fzf-lua.path"
local core = require "fzf-lua.core"
local utils = require "fzf-lua.utils"
local config = require "fzf-lua.config"

local M = {}

local getopts_lsp = function(opts, cfg)
  opts = config.getopts(opts, cfg, {
    "cwd", "prompt", "actions", "winopts",
    "file_icons", "color_icons", "git_icons",
    "separator"
  })

  if not opts.timeout then
    opts.timeout = config.lsp.timeout or 10000
  end
  return opts
end

local set_fzf_args = function(opts)
  local line_placeholder = 2
  if opts.file_icons == true or opts.git_icons == true then
    line_placeholder = 3
  end

  opts.cli_args = "--nth=3 --delimiter='[: \\t]'"
  opts.preview_args = string.format("--highlight-line={%d}", line_placeholder)
  opts.preview_offset = string.format("+{%d}-/2", line_placeholder)
  return opts
end

M.refs_async = function(opts)

  opts = getopts_lsp(opts, config.lsp)

  -- hangs/returns empty if inside the coroutine
  local params = vim.lsp.util.make_position_params()
  params.context = { includeDeclaration = true }
  local results_lsp, lsp_err = vim.lsp.buf_request_sync(0, "textDocument/references", params, opts.timeout)
  if lsp_err then
    utils.err("Error finding LSP references: " .. lsp_err)
    return
  end

  opts.fzf_fn = function (cb)
    coroutine.wrap(function ()
      local co = coroutine.running()
      local locations = {}
      for _, server_results in pairs(results_lsp) do
        if server_results.result then
          vim.list_extend(locations, vim.lsp.util.locations_to_items(server_results.result) or {})
        end
      end

      if vim.tbl_isempty(locations) then
        utils.info("LSP references is empty.")
        vim.api.nvim_feedkeys(
          vim.api.nvim_replace_termcodes("<C-c>", true, false, true),
          'n', true)
        return
      end
      for _, entry in ipairs(locations) do
        entry = core.make_entry_lcol(opts, entry)
        entry = core.make_entry_file(opts, entry)
        cb(entry, function(err)
          if err then return end
          coroutine.resume(co)
          -- cb(nil) -- to close the pipe to fzf, this removes the loading
                     -- indicator in fzf
        end)
        coroutine.yield()
      end
    end)()
  end

  opts = set_fzf_args(opts)
  return core.fzf_files(opts)
end

local convert_diagnostic_type = function(severity)
  -- convert from string to int
  if type(severity) == 'string' then
    -- make sure that e.g. error is uppercased to Error
    return vim.lsp.protocol.DiagnosticSeverity[severity:gsub("^%l", string.upper)]
  end
  -- otherwise keep original value, incl. nil
  return severity
end

local filter_diag_severity = function(opts, severity)
  if opts.severity ~= nil then
    return opts.severity == severity
  elseif opts.severity_limit ~= nil then
    return severity <= opts.severity_limit
  elseif opts.severity_bound ~= nil then
    return severity >= opts.severity_bound
  else
    return true
  end
end

local diagnostics_to_tbl = function(opts)
  opts = opts or {}
  local items = {}
  local lsp_type_diagnostic = vim.lsp.protocol.DiagnosticSeverity
  local current_buf = vim.api.nvim_get_current_buf()

  opts.severity = convert_diagnostic_type(opts.severity)
  opts.severity_limit = convert_diagnostic_type(opts.severity_limit)
  opts.severity_bound = convert_diagnostic_type(opts.severity_bound)

  local validate_severity = 0
  for _, v in ipairs({opts.severity, opts.severity_limit, opts.severity_bound}) do
    if v ~= nil then
      validate_severity = validate_severity + 1
    end
    if validate_severity > 1 then
      utils.info('LSP: invalid severity parameters')
      return {}
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

  local buffer_diags = opts.get_all and vim.lsp.diagnostic.get_all() or
    {[current_buf] = vim.lsp.diagnostic.get(current_buf, opts.client_id)}
  for bufnr, diags in pairs(buffer_diags) do
    for _, diag in ipairs(diags) do
      -- workspace diagnostics may include empty tables for unused bufnr
      if not vim.tbl_isempty(diag) then
        if filter_diag_severity(opts, diag.severity) then
          table.insert(items, preprocess_diag(diag, bufnr))
        end
      end
    end
  end

  -- sort results by bufnr (prioritize cur buf), severity, lnum
  table.sort(items, function(a, b)
    if a.bufnr == b.bufnr then
      if a.type == b.type then
        return a.lnum < b.lnum
      else
        return a.type < b.type
      end
    else
      -- prioritize for current bufnr
      if a.bufnr == current_buf then
        return true
      end
      if b.bufnr == current_buf then
        return false
      end
      return a.bufnr < b.bufnr
    end
  end)

  return items
end


M.lsp_diag = function(opts)
  local locations = diagnostics_to_tbl(opts)

  if vim.tbl_isempty(locations) then
    utils.info("LSP diagnostics is empty.")
    return
  end

  return lsp_run(opts, config.lsp, locations)
end

return M
