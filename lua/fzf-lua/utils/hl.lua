local ts = vim.treesitter
local utils = require("fzf-lua.utils")

local M = {}

-- credits to https://github.com/folke/snacks.nvim/blob/06e9ca95f81f528c4314afb80a59ce317f12ac5d/lua/snacks/picker/util/highlight.lua#L26
M._scratch = {} ---@type table<string, integer>

---@param lines string[]
---@param lang string
function M.scratch_buf(lines, lang)
  local buf = M._scratch[lang]
  if not (buf and vim.api.nvim_buf_is_valid(buf)) then
    buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(buf, "fzf-lua://hl/" .. lang)
    M._scratch[lang] = buf
  end
  vim.bo[buf].fixeol = false
  vim.bo[buf].eol = false
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  return buf
end

---@class fzf-lua.Extmarks
---@field col integer
---@field end_col integer
---@field priority? integer
---@field hl_group? string

---@class fzf-lua.hl.Opts
---@field buf? integer
---@field code? string[]
---@field ft? string
---@field lang? string
---@field file? string
---@field extmarks? boolean

---@param opts fzf-lua.hl.Opts
---@return table<integer, fzf-lua.Extmarks[]>
function M.get_hl(opts)
  opts = opts or {}
  assert(opts.buf or opts.code, "buf or code is required")
  assert(not (opts.buf and opts.code), "only one of buf or code is allowed")

  local ret = {}

  local ft = opts.ft
      or (opts.buf and vim.bo[opts.buf].filetype)
      or (opts.file and vim.filetype.match({ filename = opts.file, buf = 0 }))
      or vim.bo.filetype
  local lang = ts.language.get_lang(opts.lang or ft)

  lang = lang and lang:lower() or nil
  local parser, buf ---@type vim.treesitter.LanguageTree?, integer?

  if lang then
    local ok = false
    buf = opts.buf or M.scratch_buf(opts.code, lang)
    ---@diagnostic disable-next-line: assign-type-mismatch
    ok, parser = pcall(ts.get_parser, buf, lang)
    parser = ok and parser or nil
  end

  if parser and buf then
    parser:parse(true)
    parser:for_each_tree(function(tstree, tree)
      if not tstree then
        return
      end
      local query = ts.query.get(tree:lang(), "highlights")
      -- Some injected languages may not have highlight queries.
      if not query then
        return
      end

      for capture, node, metadata in query:iter_captures(tstree:root(), buf) do
        local name = query.captures[capture]
        if name and name ~= "spell" and name ~= "nospell" then
          local range = { node:range() } ---@type [integer, integer, integer, integer]
          local multi = range[1] ~= range[3]
          local text = multi
              and vim.split(ts.get_node_text(node, buf, metadata[capture]), "\n", { plain = true }) or
              {}
          for row = range[1] + 1, range[3] + 1 do
            local first, last = row == range[1] + 1, row == range[3] + 1
            local end_col = last and range[4] or #(text[row - range[1]] or "")
            end_col = multi and first and end_col + range[2] or end_col
            ret[row] = ret[row] or {}

            if not metadata.conceal then
              table.insert(ret[row], {
                col = first and range[2] or 0,
                end_col = end_col,
                priority = (tonumber(metadata.priority or metadata[capture] and metadata[capture].priority) or 100),
                conceal = metadata.conceal or metadata[capture] and metadata[capture].conceal,
                hl_group = "@" .. name .. "." .. lang,
              })
            end
          end
        end
      end
    end)
  end

  --- Add buffer extmarks
  if opts.buf and opts.extmarks then
    local extmarks = vim.api.nvim_buf_get_extmarks(opts.buf, -1, 0, -1, { details = true })
    for _, extmark in pairs(extmarks) do
      local row = extmark[2] + 1
      ret[row] = ret[row] or {}
      local e = extmark[4]
      if e and e.hl_group and e.end_row and e.end_row then
        e.sign_name = nil
        e.sign_text = nil
        e.ns_id = nil
        table.insert(ret[row], e)
      end
    end
  end

  -- TODO: better handle "priority"/"extmark" in ansi highlights...
  for _, extmarks in pairs(ret) do
    table.sort(extmarks, function(a, b)
      return a.col < b.col or (a.col == b.col and a.end_col < b.end_col)
    end)
  end

  return ret
end

---modify lines inplace
---@param lines string[]
---@param marks table<integer, fzf-lua.Extmarks[]> each line is sorted extmarks
---@return string[]
M.ansi_from_marks = function(lines, marks)
  for lnum, extmarks in pairs(marks) do
    local line = assert(lines[lnum])
    local parts = {}
    local col = 1
    for _, mark in ipairs(extmarks) do
      -- "interval" between marks (ensure extmarks is sorted)
      if col < mark.col then
        local part = line:sub(col, mark.col)
        -- dd(part, col, mark.col)
        parts[#parts + 1] = part
      end
      -- color the actual mark
      local part = line:sub(mark.col + 1, mark.end_col)
      local colored = utils.ansi_from_hl(mark.hl_group, part)
      parts[#parts + 1] = colored
      col = mark.end_col
    end
    local remain = line:sub(col)
    if #remain > 0 then parts[#parts + 1] = remain end
    lines[lnum] = table.concat(parts)
  end
  return lines
end

---modify lines inplace
---@param opts fzf-lua.hl.Opts
---@return string[]
M.ansi = function(opts)
  local marks = M.get_hl(opts)
  local lines = assert(opts.code or
    (opts.buf and vim.api.nvim_buf_get_lines(opts.buf, 0, -1, false)))
  return M.ansi_from_marks(lines, marks)
end

return M
