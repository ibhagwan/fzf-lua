---@diagnostic disable: need-check-nil, param-type-mismatch
local core = require "fzf-lua.core"
local utils = require "fzf-lua.utils"
local config = require "fzf-lua.config"
local make_entry = require "fzf-lua.make_entry"

local M = {}


local convert_diagnostic_type = function(severity)
  -- convert from string to int
  if type(severity) == "string" and not tonumber(severity) then
    -- make sure that e.g. error is uppercased to Error
    return vim.diagnostic.severity[severity:upper()]
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

---@param opts fzf-lua.config.Diagnostics|{}?
---@return (thread|table)?, string?, table?
M.diagnostics = function(opts)
  ---@type fzf-lua.config.Diagnostics
  opts = config.normalize_opts(opts, "diagnostics")
  if not opts then return end

  -- required for relative paths presentation
  if not opts.cwd or #opts.cwd == 0 then
    opts.cwd = utils.cwd()
  else
    opts.cwd_only = true
  end

  -- configure signs and highlights
  local signs = {
    ["Error"] = { severity = 1, default = "E", name = "DiagnosticSignError" },
    ["Warn"]  = { severity = 2, default = "W", name = "DiagnosticSignWarn" },
    ["Info"]  = { severity = 3, default = "I", name = "DiagnosticSignInfo" },
    ["Hint"]  = { severity = 4, default = "H", name = "DiagnosticSignHint" },
  }


  ---@class fzf-lua.DiagnosticSign
  ---@field text string
  ---@field texthl string|nil

  ---@type table<integer, fzf-lua.DiagnosticSign>
  local signs0 = {}
  for k, v in pairs(signs) do
    local text, texthl
    -- from vim.diagnostic
    if utils.__HAS_NVIM_010 then
      local sign_confs = type(opts.diag_icons) == "table" and { text = opts.diag_icons }
          or vim.diagnostic.config().signs
      local level = vim.diagnostic.severity[k:upper()]
      if type(sign_confs) ~= "table" or utils.tbl_isempty(sign_confs) then sign_confs = nil end
      text =
          (not opts.diag_icons or not sign_confs or not sign_confs.text or not sign_confs.text[level])
          and v.default or vim.trim(sign_confs.text[level])
      texthl = v.name
    else
      ---@type vim.fn.sign_getdefined.ret.item[]?
      local sign_def = vim.fn.sign_getdefined(v.name)
      -- can be empty when config set to (#480):
      -- vim.diagnostic.config({ signs = false })
      if utils.tbl_isempty(sign_def) then sign_def = nil end
      text =
          (not opts.diag_icons or not sign_def or not sign_def[1].text) ---@diagnostic disable-next-line: need-check-nil
          and v.default or vim.trim(sign_def[1].text)
      texthl = sign_def and sign_def[1].texthl or nil
    end
    signs0[v.severity] = { text = text, texthl = texthl }

    -- from user config
    if opts.signs and opts.signs[k] and opts.signs[k].text then
      signs0[v.severity].text = opts.signs[k].text
    end
    if opts.signs and opts.signs[k] and opts.signs[k].texthl then
      signs0[v.severity].texthl = opts.signs[k].texthl
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

  ---@type vim.diagnostic.GetOpts
  local diag_opts = { severity = {}, namespace = opts.namespace }
  if opts.severity_only ~= nil then
    if opts.severity_limit ~= nil or opts.severity_bound ~= nil then
      utils.warn("Invalid severity parameters." ..
        " Both a specific severity and a limit/bound is not allowed")
      return {}
    end
    diag_opts.severity = opts.severity_only
  else
    diag_opts.severity["min"] = opts.severity_limit or 4
    diag_opts.severity["max"] = opts.severity_bound or 1
  end

  local curbuf = vim.api.nvim_get_current_buf()
  local diag_results = vim.diagnostic.get(not opts.diag_all and curbuf or nil, diag_opts)

  if opts.sort then
    if opts.sort == 2 or opts.sort == "2" then
      -- ascending: hint, info, warn, error
      table.sort(diag_results, function(a, b) return a.severity > b.severity end)
    elseif type(opts.sort) == "function" then
      diag_results = opts.sort(diag_results, opts)
    else
      -- descending: error, warn, info, hint
      table.sort(diag_results, function(a, b) return a.severity < b.severity end)
    end
  end

  -- format: { <diag array> }
  local has_diags = not utils.tbl_isempty(diag_results)
  if not has_diags then
    utils.info("No %s found", "diagnostics")
    return
  end

  ---@class fzf-lua.BufferDiag
  ---@field bufnr integer
  ---@field filename string
  ---@field lnum integer
  ---@field col integer
  ---@field text string
  ---@field type integer

  ---@param diag vim.Diagnostic
  ---@return fzf-lua.BufferDiag?
  local preprocess_diag = function(diag)
    local bufnr = diag.bufnr
    if not vim.api.nvim_buf_is_valid(bufnr) then
      return nil
    end
    local filename = vim.api.nvim_buf_get_name(bufnr)
    local buffer_diag = {
      bufnr = bufnr,
      filename = filename,
      lnum = diag.lnum + 1,
      col = diag.col + 1,
      text = vim.trim(opts.multiline and diag.message or diag.message:match("^[^\n]+")),
      type = diag.severity or 1
    }
    return buffer_diag
  end

  local contents = function(fzf_cb)
    coroutine.wrap(function()
      local co = coroutine.running()

      ---@param diags vim.Diagnostic[]
      local function process_diagnostics(diags)
        for _, diag in ipairs(diags) do
          -- workspace diagnostics may include
          -- empty tables for unused buffers
          if not utils.tbl_isempty(diag) and filter_diag_severity(opts, diag.severity) then
            -- wrap with 'vim.schedule' or calls to vim.{fn|api} fail:
            -- E5560: vimL function must not be called in a lua loop callback
            vim.schedule(function()
              local diag_entry = preprocess_diag(diag)
              if diag_entry == nil then
                coroutine.resume(co)
                return
              end

              local sign_def = signs0[diag.severity]

              if opts.color_headings then
                diag_entry.filename = utils.ansi_from_hl(sign_def.texthl, diag_entry.filename)
              end

              local entry0 = make_entry.lcol(diag_entry, opts)
              local entry = make_entry.file(entry0, opts)
              if entry == nil then entry = "" end
              if not entry then
                -- entry to be skipped (e.g. 'cwd_only')
                coroutine.resume(co)
              else
                local icon = nil
                if sign_def then
                  icon = sign_def.text
                  if opts.color_icons then
                    icon = utils.ansi_from_hl(sign_def.texthl, icon)
                  end
                end

                if opts.diag_code and diag.code then
                  entry = entry
                      .. utils.ansi_from_hl("Comment", " [" .. tostring(diag.code) .. "]")
                end

                entry = string.format("%s%s%s",
                  icon and string.format("%s%s%s", icon, opts.icon_padding or "", utils.nbsp)
                  or "",
                  opts.diag_source and utils.ansi_from_hl(
                    opts.color_headings and sign_def.texthl, string.format(
                      "%s%s%s%s",
                      "[", --utils.ansi_codes.bold("["),
                      diag.source,
                      "]", --utils.ansi_codes.bold("]"),
                      utils.nbsp))
                  or "",
                  entry)
                fzf_cb(entry, function() coroutine.resume(co) end)
              end
            end)
            -- wait here for 'vim.schedule' to return
            coroutine.yield()
          end
        end
      end

      process_diagnostics(diag_results)
      -- close the pipe to fzf, this
      -- removes the loading indicator
      fzf_cb(nil)
    end)()
  end

  opts = core.set_fzf_field_index(opts)
  return core.fzf_exec(contents, opts)
end

---@param opts fzf-lua.config.Diagnostics|{}?
---@return (thread|table)?, string?, table?
M.all = function(opts)
  if not opts then opts = {} end
  opts.diag_all = true
  return M.diagnostics(opts)
end

return M
