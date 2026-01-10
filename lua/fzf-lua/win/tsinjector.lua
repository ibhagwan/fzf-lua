local api = vim.api
local ts = vim.treesitter
local tsh = ts.highlighter
local utils = require "fzf-lua.utils"
local path = require "fzf-lua.path"

---@class fzf-lua.TSInjector
---@field cache table<integer, table<string, fzf-lua.TSInjectorLangEntry>>
---@field _setup boolean?
---@field _ns integer?
---@field _has_on_range boolean?
local M = {}

---@class fzf-lua.TSInjectorLangEntry
---@field parser vim.treesitter.LanguageTree
---@field highlighter vim.treesitter.highlighter
---@field enabled? boolean

M.cache = {}

function M.setup()
  if M._setup then return true end

  M._setup = true
  M._ns = M._ns or api.nvim_create_namespace("fzf-lua.win.highlighter")
  M._has_on_range = M._has_on_range == nil
      and pcall(api.nvim_set_decoration_provider, M._ns, { on_range = function() end })
      or M._has_on_range

  local function wrap_ts_hl_callback(name, cb)
    return function(_, win, buf, ...)
      -- print(name, buf, win, TSInjector.cache[buf])
      if not M.cache[buf] then
        return false
      end
      for _, hl in pairs(M.cache[buf]) do
        if hl.enabled then
          local h = hl.highlighter
          tsh.active[buf] = h
          if tsh[name] then
            if cb then cb(h, buf, ...) end
            tsh[name](_, win, buf, ...)
          end
        end
      end
      tsh.active[buf] = nil
    end
  end

  local on_range = wrap_ts_hl_callback("_on_range")
  local on_line = M._has_on_range and function(_, win, buf, row)
    return on_range(_, win, buf, row, 0, row + 1, 0)
  end or wrap_ts_hl_callback("_on_line")

  -- https://github.com/neovim/neovim/issues/36503
  local on_win_pre = utils.__HAS_NVIM_012 and function(h, buf, topline, botline)
    if h.parsing then return end
    h.parsing = nil == h.tree:parse({ topline, botline + 1 }, function(_, trees)
      if trees and h.parsing then
        h.parsing = false
        api.nvim__redraw({ buf = buf, valid = false, flush = false })
      end
    end)
  end or nil

  api.nvim_set_decoration_provider(M._ns, {
    on_win = wrap_ts_hl_callback("_on_win", on_win_pre),
    -- on_start = wrap_ts_hl_callback("_on_start"),
    on_line = on_line,
  })

  return true
end

function M.deregister()
  if not M._ns then return end
  api.nvim_set_decoration_provider(M._ns, {})
  M._setup = nil
end

function M.clear_cache(buf)
  -- If called from fzf-tmux buf will be `nil` (#1556)
  if not buf then return end
  M.cache[buf] = nil
  -- If called from `FzfWin.hide` cache will not be empty
  assert(utils.tbl_isempty(M.cache))
end

---@alias TSRegion (Range4|Range6|TSNode)[][]

---@param buf integer
---@param regions table<string, TSRegion>
local function attach(buf, regions)
  if not M.setup() then return end

  for lang, _ in pairs(M.cache[buf]) do
    M.cache[buf][lang].enabled = regions[lang] ~= nil
  end

  for lang, region in pairs(regions) do
    M._attach_lang(buf, lang, region)
  end
end

---@param buf integer
---@param lang string
---@param regions TSRegion
function M._attach_lang(buf, lang, regions)
  if not M.cache[buf][lang] then
    local ok, parser = pcall(ts.languagetree.new, buf, lang)
    if not ok then return end ---@cast parser -string
    M.cache[buf][lang] = { parser = parser, highlighter = tsh.new(parser) }
  end

  local parser = M.cache[buf][lang].parser
  if not parser then return end

  M.cache[buf][lang].enabled = true
  ---@diagnostic disable-next-line: invisible, access-invisible
  parser:set_included_regions(regions)
end

---@param buf integer
function M.detach(buf)
  M.deregister()
  M.clear_cache(buf)
end

---@param self fzf-lua.Win
---@param buf integer
---@param line_parser (fun(line: string):string?,string?,string?,string?)|boolean?
function M.attach(self, buf, line_parser)
  -- local utf8 = require("fzf-lua.lib.utf8")
  local function trim(s) return (string.gsub(s, "^%s*(.-)%s*$", "%1")) end
  ---@type fun(line: string):string?,string?,string?,string?
  local default_line_parser = function(line) return line:match("(.-):?(%d+)[: ](.+)$") end
  line_parser = vim.is_callable(line_parser) and line_parser or default_line_parser
  M.cache[buf] = {}
  api.nvim_buf_attach(buf, false, {
    on_lines = function(_, bufnr)
      -- no nvim_buf_detach: https://github.com/neovim/neovim/issues/17874
      -- Called after `:close` triggers an attach after clear_cache (#2322)
      if self.closing or not M.cache[buf] then return true end
      local lines = api.nvim_buf_get_lines(bufnr, 0, -1, false)
      local regions = {}
      local empty_regions = {}
      -- Adjust treesitter region based on the available main window width
      -- otherwise the highlights may interfere with the fzf scrollbar or
      -- the native fzf preview window
      local min_col, max_col, trim_right = (function()
        local min, max, tr = 0, nil, 4
        if not self.preview_hidden
            and (not self.previewer_is_builtin or self.winopts.split)
            and api.nvim_win_is_valid(self.fzf_winid)
        then
          local win_width = api.nvim_win_get_width(self.fzf_winid)
          local layout = self:normalize_preview_layout()
          local prev_width = self:normalize_size(layout.size, win_width)
          if layout.pos == "left" then
            min = prev_width
          elseif layout.pos == "right" then
            max = win_width - prev_width
          end
        end
        return min, max, tr
      end)()
      for i, line in ipairs(lines) do
        (function()
          -- Lines with code can be of the following formats:
          -- file:line:col:text   (grep_xxx)
          -- file:line:text       (grep_project or missing "--column" flag)
          -- line:col:text        (grep_curbuf)
          -- line<U+00A0>text     (lines|blines)
          local filepath, _lnum, text, _ft = line_parser(line:sub(min_col))
          if not text or text == 0 then return end

          text = text:gsub("^%d+:", "") -- remove col nr if exists
          filepath = trim(filepath)     -- trim spaces

          local ft_bufnr = (function()
            -- blines|lines: U+00A0 (decimal: 160) follows the lnum
            -- grep_curbuf: formats as line:col:text` thus `#filepath == 0`
            if #filepath == 0 or string.byte(text, 1) == 160 then
              if string.byte(text, 1) == 160 then text = text:sub(2) end -- remove A0+SPACE
              if string.byte(text, 1) == 32 then text = text:sub(2) end  -- remove leading SPACE
              -- IMPORTANT: use the `__CTX` version that doesn't trigger a new context
              local __CTX = utils.__CTX()
              local b = utils.tointeger(filepath:match("^%d+") or __CTX and __CTX.bufnr)
              return b and api.nvim_buf_is_valid(b) and b or nil
            end
          end)()

          local ft = _ft or (ft_bufnr and vim.bo[ft_bufnr].ft
            or vim.filetype.match({ filename = path.tail(filepath) }))
          if not ft then return end

          local lang = ts.language.get_lang(ft)
          if not lang then return end
          local loaded = utils.has_ts_parser(lang, "highlights")
          if not loaded then return end

          -- NOTE: if the line contains unicode characters `#line > win_width`
          -- as both `#str` and `string.len` count bytes and not characters
          -- hence we trim 4 bytes from the right (for the scrollbar) except
          -- when using native fzf previewer / split with left preview where
          -- we use `max_col` instead (assuming our code isn't unicode)
          local line_idx = i - 1
          local line_len = #line
          local start_col = math.max(min_col, line_len - #text)
          local end_col = max_col and math.min(max_col, line_len) or (line_len - trim_right)
          regions[lang] = regions[lang] or {}
          empty_regions[lang] = empty_regions[lang] or {}
          table.insert(regions[lang], { { line_idx, start_col, line_idx, end_col } })
          -- print(lang, string.format("%d:%d  [%d] %d:%s",
          --   start_col, end_col, line_idx, _lnum, line:sub(start_col + 1, end_col)))
        end)()
      end
      attach(bufnr, empty_regions)
      attach(bufnr, regions)
    end
  })
end

return M
