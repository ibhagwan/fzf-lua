local uv = vim.uv or vim.loop
local core = require "fzf-lua.core"
local path = require "fzf-lua.path"
local utils = require "fzf-lua.utils"
local libuv = require "fzf-lua.libuv"
local config = require "fzf-lua.config"
local base64 = require "fzf-lua.lib.base64"
local devicons = require "fzf-lua.devicons"
local make_entry = require "fzf-lua.make_entry"

local M = {}

---@param opts fzf-lua.Config
---@param unfiltered integer[]|fun():integer[]
---@return integer[], table, integer
local filter_buffers = function(opts, unfiltered)
  if type(unfiltered) == "function" then
    unfiltered = unfiltered()
  end

  local curtab_bufnrs = {}
  if opts.current_tab_only then
    for _, w in ipairs(vim.api.nvim_tabpage_list_wins(core.CTX().tabh)) do
      local b = vim.api.nvim_win_get_buf(w)
      curtab_bufnrs[b] = true
    end
  end

  local excluded, max_bufnr = {}, 0
  local bufnrs = type(opts.buffers) == "table"
      and vim.tbl_map(function(b)
        max_bufnr = math.max(max_bufnr, b)
        return b
      end, opts.buffers)
      or vim.tbl_filter(function(b)
        local buf_valid = vim.api.nvim_buf_is_valid(b)
        if not buf_valid then
          excluded[b] = true
        elseif not opts.show_unlisted and b ~= core.CTX().bufnr and vim.fn.buflisted(b) ~= 1 then
          excluded[b] = true
        elseif not opts.show_unloaded and not vim.api.nvim_buf_is_loaded(b) then
          excluded[b] = true
        elseif opts.ignore_current_buffer and b == core.CTX().bufnr then
          excluded[b] = true
        elseif opts.current_tab_only and not curtab_bufnrs[b] then
          excluded[b] = true
        elseif opts.no_term_buffers and utils.is_term_buffer(b) then
          excluded[b] = true
        elseif opts.cwd_only and not path.is_relative_to(vim.api.nvim_buf_get_name(b), uv.cwd()) then
          excluded[b] = true
        elseif opts.cwd and not path.is_relative_to(vim.api.nvim_buf_get_name(b), opts.cwd) then
          excluded[b] = true
        elseif type(opts.filter) == "function" then
          -- Custom buffer filter #2162
          excluded[b] = not opts.filter(b)
        end
        if buf_valid and vim.api.nvim_get_option_value("ft", { buf = b }) == "qf" then
          excluded[b] = not opts.show_quickfix and true or nil
        end
        if not excluded[b] and b > max_bufnr then
          max_bufnr = b
        end
        return not excluded[b]
      end, unfiltered)

  return bufnrs, excluded, max_bufnr
end

---@param buf integer
---@return { bufnr: integer, flag: string, info: table, readonly: boolean }
local getbuf = function(buf)
  return {
    bufnr = buf,
    flag = (buf == core.CTX().bufnr and "%")
        or (buf == core.CTX().alt_bufnr and "#") or " ",
    info = utils.getbufinfo(buf),
    readonly = vim.bo[buf].readonly
  }
end

-- switching buffers and opening 'buffers' in quick succession
-- can lead to incorrect sort as 'lastused' isn't updated fast
-- enough (neovim bug?), this makes sure the current buffer is
-- always on top (#646)
-- Hopefully this gets solved before the year 2100
-- DON'T FORCE ME TO UPDATE THIS HACK NEOVIM LOL
-- NOTE: reduced to 2038 due to 32bit sys limit (#1636)
local _FUTURE = os.time({ year = 2038, month = 1, day = 1, hour = 0, minute = 00 })
---@param buf table
---@return integer
local get_unixtime = function(buf)
  if buf.flag == "%" then
    return _FUTURE
  elseif buf.flag == "#" then
    return _FUTURE - 1
  else
    return buf.info.lastused
  end
end

---@param opts fzf-lua.Config
---@param bufnrs integer[]
---@param winid integer?
---@return table[]
local populate_buffer_entries = function(opts, bufnrs, winid)
  ---@type table[]
  local buffers = {}
  for _, bufnr in ipairs(bufnrs) do
    local buf = getbuf(bufnr)

    -- Get the name for missing/quickfix/location list buffers
    -- NOTE: we get it here due to `gen_buffer_entry` called within a fast event
    if not buf.info.name or #buf.info.name == 0 then
      buf.info.name = utils.nvim_buf_get_name(buf.bufnr, buf.info)
    end

    -- get the correct lnum for tabbed buffers
    if winid then
      buf.info.lnum = vim.api.nvim_win_get_cursor(winid)[1]
    end

    table.insert(buffers, buf)
  end

  if opts.sort_lastused then
    table.sort(buffers, function(a, b)
      return get_unixtime(a) > get_unixtime(b)
    end)
  end
  return buffers
end


local function gen_buffer_entry(opts, buf, max_bufnr, cwd, prefix)
  -- local hidden = buf.info.hidden == 1 and 'h' or 'a'
  local hidden = ""
  local readonly = buf.readonly and "=" or " "
  local changed = buf.info.changed == 1 and "+" or " "
  local flags = hidden .. readonly .. changed
  local leftbr = "["
  local rightbr = "]"
  local bufname = (function()
    local bname = buf.info.name
    if bname:match("^%[.*%]$") or bname:match("^%a+://") then
      return bname
    elseif opts.filename_only then
      return path.tail(bname)
    else
      bname = make_entry.lcol({ filename = bname, lnum = buf.info.lnum }, opts):gsub(":$", "")
      return make_entry.file(bname, vim.tbl_extend("force", opts,
        -- No support for git_icons, file_icons are added later
        { cwd = cwd or opts.cwd or uv.cwd(), file_icons = false, git_icons = false }))
    end
  end)()
  if buf.flag == "%" then
    flags = utils.ansi_codes[opts.hls.buf_flag_cur](buf.flag) .. flags
  elseif buf.flag == "#" then
    flags = utils.ansi_codes[opts.hls.buf_flag_alt](buf.flag) .. flags
  else
    flags = utils.nbsp .. flags
  end
  local bufnrstr = string.format("%s%s%s", leftbr,
    utils.ansi_codes[opts.hls.buf_nr](tostring(buf.bufnr)), rightbr)
  local buficon = ""
  local hl = ""
  if opts.file_icons then
    buficon, hl = devicons.get_devicon(buf.info.name,
      -- shell-like icon for terminal buffers
      utils.is_term_bufname(buf.info.name) and "sh" or nil)
    if hl and opts.color_icons then
      buficon = utils.ansi_from_rgb(hl, buficon)
    end
  end
  local max_bufnr_w = 3 + #tostring(max_bufnr) + utils.ansi_escseq_len(bufnrstr)
  local item_str = string.format("%s%s%s%s%s%s%s%s",
    prefix or "",
    string.format("%-" .. tostring(max_bufnr_w) .. "s", bufnrstr),
    utils.nbsp,
    flags,
    utils.nbsp,
    buficon,
    utils.nbsp,
    bufname)
  return item_str
end

M.buffers = function(opts)
  opts = config.normalize_opts(opts, "buffers")
  if not opts then return end

  local contents = function(cb)
    local filtered, _, max_bufnr = filter_buffers(opts, core.CTX().buflist)

    if next(filtered) then
      local buffers = populate_buffer_entries(opts, filtered)
      for _, bufinfo in pairs(buffers) do
        local ok, entry = pcall(gen_buffer_entry, opts, bufinfo, max_bufnr)
        assert(ok and entry)
        cb(entry)
      end
    end
    cb(nil)
  end

  opts.fzf_opts["--header-lines"] = opts.fzf_opts["--header-lines"] == nil
      and (not opts.ignore_current_buffer and opts.sort_lastused) and "1" or nil

  opts = core.set_header(opts, opts.headers or { "actions", "cwd" })
  opts = opts.filename_only and opts or core.set_fzf_field_index(opts)

  return core.fzf_exec(contents, opts)
end

M.lines = function(opts)
  opts = config.normalize_opts(opts, "lines")
  return M.buffer_lines(opts)
end

M.blines = function(opts)
  opts = config.normalize_opts(opts, "blines")
  opts.current_buffer_only = true
  if utils.mode_is_visual() then
    local _, sel = utils.get_visual_selection()
    opts.start_line = opts.start_line or sel.start.line
    opts.end_line = opts.end_line or sel["end"].line
  end
  return M.buffer_lines(opts)
end


M.buffer_lines = function(opts)
  if not opts then return end

  local contents = function(cb)
    local function add_entry(x, co)
      cb(x, function(err)
        coroutine.resume(co)
        if err then cb(nil) end
      end)
      coroutine.yield()
    end

    coroutine.wrap(function()
      local co = coroutine.running()

      local buffers = filter_buffers(opts,
        opts.current_buffer_only and { core.CTX().bufnr } or core.CTX().buflist)

      if opts.sort_lastused and utils.tbl_count(buffers) > 1 then
        table.sort(buffers, function(a, b)
          return get_unixtime(getbuf(a)) > get_unixtime(getbuf(b))
        end)
      end

      local bnames = {}
      local longest_bname = 0
      for _, b in ipairs(buffers) do
        local bname = utils.nvim_buf_get_name(b)
        if not bname:match("^%[") then
          bname = path.shorten(vim.fn.fnamemodify(bname, ":~:."))
        end
        longest_bname = math.max(longest_bname, #bname)
        bnames[tostring(b)] = bname
      end
      local len_bufnames = math.min(15, longest_bname)

      for _, bufnr in ipairs(buffers) do
        local data = {}

        -- Use vim.schedule to avoid
        -- E5560: vimL function must not be called in a lua loop callback
        vim.schedule(function()
          local filepath = vim.api.nvim_buf_get_name(bufnr)
          if vim.api.nvim_buf_is_loaded(bufnr) then
            data = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
          elseif vim.fn.filereadable(filepath) ~= 0 then
            data = vim.fn.readfile(filepath, "")
          end
          coroutine.resume(co)
        end)

        -- wait for vim.schedule
        coroutine.yield()

        local bname, bicon = (function()
          if not opts.show_bufname
              or tonumber(opts.show_bufname) and tonumber(opts.show_bufname) > vim.o.columns
          then
            return
          end
          local bicon, hl = "", nil
          local bname = bnames[tostring(bufnr)]
          assert(bname)

          if #bname > len_bufnames + 1 then
            bname = "…" .. bname:sub(#bname - len_bufnames + 2)
          end

          if opts.file_icons then
            bicon, hl = devicons.get_devicon(bname)
            if hl and opts.color_icons then
              bicon = utils.ansi_from_rgb(hl, bicon)
            end
          end
          return bname, bicon and bicon .. utils.nbsp or nil
        end)()

        local offset, start_line, end_line, lines = 0, 1, #data, #data
        if opts.current_buffer_only then
          start_line = opts.start_line or 1
          end_line = opts.end_line or end_line
          lines = end_line - start_line + 1
          if opts.start == "cursor" then
            -- start display from current line and wrap from bottom (#822)
            offset = core.CTX().cursor[1] - start_line
          end
        end

        for i = 1, lines do
          local lnum = i + offset
          if lnum > lines then
            lnum = lnum % lines
          end
          lnum = lnum + start_line - 1

          -- NOTE: Space after `lnum` is U+00A0 (decimal: 160)
          add_entry(string.format("[%s]\t%s\t%s%s\t%s \t%s",
            tostring(bufnr),
            utils.ansi_codes[opts.hls.buf_id](string.format("%3d", bufnr)),
            bicon or "",
            not bname and "" or utils.ansi_codes[opts.hls.buf_name](string.format(
              "%"
              .. (opts.file_icons and "-" or "")
              .. tostring(len_bufnames) .. "s",
              bname)),
            utils.ansi_codes[opts.hls.buf_linenr](string.format("%5d", lnum)),
            data[lnum]
          ), co)
        end
      end
      cb(nil)
    end)()
  end

  opts = core.set_fzf_field_index(opts, "{3}", opts._is_skim and "{}" or "{..-2}")
  return core.fzf_exec(contents, opts)
end

M.tabs = function(opts)
  opts = config.normalize_opts(opts, "tabs")
  if not opts then return end

  local opt_hl = function(t, k, default_msg, default_hl)
    local hl = default_hl
    local msg = default_msg and default_msg(opts[k]) or opts[k]
    if type(opts[k]) == "table" then
      if type(opts[k][1]) == "function" then
        msg = opts[k][1](t, t == core.CTX().tabnr)
      elseif type(opts[k][1]) == "string" then
        msg = default_msg(opts[k][1])
      else
        msg = default_msg("Tab")
      end
      if type(opts[k][2]) == "string" then
        hl = function(s)
          return utils.ansi_from_hl(opts[k][2], s);
        end
      end
    elseif type(opts[k]) == "function" then
      msg = opts[k](t, t == core.CTX().tabnr)
    end
    return msg, hl
  end

  if opts.locate and utils.has(opts, "fzf", { 0, 36 }) then
    -- Set cursor to current buffer
    table.insert(opts._fzf_cli_args, "--bind=" .. libuv.shellescape("load:+transform:"
      .. FzfLua.shell.stringify_data(function(_, _, _)
        local pos = 0
        for tabnr, tabh in ipairs(vim.api.nvim_list_tabpages()) do
          pos = pos + 1
          for _, w in ipairs(vim.api.nvim_tabpage_list_wins(tabh)) do
            local b = filter_buffers(opts, { vim.api.nvim_win_get_buf(w) })[1]
            if b then
              pos = pos + 1
              if tabnr == core.CTX().tabnr and w == core.CTX().winid then
                return string.format("pos(%d)", pos)
              end
            end
          end
        end
      end, opts)))
  end

  local contents = function(cb)
    local max_bufnr = (function()
      local ret = 0
      for _, t in ipairs(vim.api.nvim_list_tabpages()) do
        for _, w in ipairs(vim.api.nvim_tabpage_list_wins(t)) do
          local b = vim.api.nvim_win_get_buf(w)
          if b > ret then ret = b end
        end
      end
      return ret
    end)()

    for tabnr, tabh in ipairs(vim.api.nvim_list_tabpages()) do
      (function()
        if opts.current_tab_only and tabh ~= core.CTX().tabh then return end

        local tab_cwd = vim.fn.getcwd(-1, tabnr)
        local tab_cwd_tilde = path.HOME_to_tilde(tab_cwd)
        local title, fn_title_hl = opt_hl(tabnr, "tab_title",
          function(s)
            return string.format("%s%s#%d%s", s, utils.nbsp, tabnr,
              (uv.cwd() == tab_cwd and "" or string.format(": %s", tab_cwd_tilde)))
          end,
          utils.ansi_codes[opts.hls.tab_title])

        local marker, fn_marker_hl = opt_hl(tabnr, "tab_marker",
          function(s) return s end,
          utils.ansi_codes[opts.hls.tab_marker])

        local tab_cwd_tilde_base64 = base64.encode(tab_cwd_tilde)
        if not opts.current_tab_only then
          cb(string.format("%s:%d:%d:0)%s%s  %s",
            tab_cwd_tilde_base64,
            tabnr,
            tabh,
            utils.nbsp,
            fn_title_hl(title),
            (tabh == core.CTX().tabh) and fn_marker_hl(marker) or ""))
        end

        for _, w in ipairs(vim.api.nvim_tabpage_list_wins(tabh)) do
          if tabh ~= core.CTX().tabh or core.CTX().curtab_wins[tostring(w)] then
            local b = filter_buffers(opts, { vim.api.nvim_win_get_buf(w) })[1]
            if b then
              local prefix = string.format("%s:%d:%d:%d)%s%s%s",
                tab_cwd_tilde_base64, tabnr, tabh, w, utils.nbsp, utils.nbsp, utils.nbsp)
              local bufinfo = populate_buffer_entries({}, { b }, w)[1]
              cb(gen_buffer_entry(opts, bufinfo, max_bufnr, tab_cwd, prefix))
            end
          end
        end
      end)()
    end
    cb(nil)
  end

  opts = core.set_header(opts, opts.headers or { "actions", "cwd" })
  opts = opts.filename_only and opts or core.set_fzf_field_index(opts, "{4}", "{}")

  return core.fzf_exec(contents, opts)
end


M.treesitter = function(opts)
  opts = config.normalize_opts(opts, "treesitter")
  if not opts then return end

  local __has_ts, _ = pcall(require, "nvim-treesitter")
  if not __has_ts then
    utils.info("Treesitter requires 'nvim-treesitter'.")
    return
  end

  -- Default to current buffer
  opts.bufnr = tonumber(opts.bufnr) or vim.api.nvim_get_current_buf()
  opts._bufname = path.basename(vim.api.nvim_buf_get_name(opts.bufnr))
  if not opts._bufname or #opts._bufname == 0 then
    opts._bufname = utils.nvim_buf_get_name(opts.bufnr)
  end

  local ts = vim.treesitter
  local ft = vim.bo[opts.bufnr].ft
  local lang = ts.language.get_lang(ft) or ft
  if not utils.has_ts_parser(lang) then
    utils.info(string.format("No treesitter parser found for '%s' (bufnr=%d).",
      opts._bufname, opts.bufnr))
    return
  end

  local kind2hl = function(kind)
    local map = { var = "variable.builtin" }
    return "@" .. (map[kind] or kind)
  end

  local parser = ts.get_parser(opts.bufnr)
  if not parser then return end
  parser:parse()
  local root = parser:trees()[1]:root()
  if not root then return end

  local query = (ts.query.get(lang, "locals"))
  if not query then return end

  local get = function(bufnr)
    local definitions = {}
    local scopes = {}
    local references = {}
    for id, node, metadata in query:iter_captures(root, bufnr) do
      local kind = query.captures[id]

      local scope = "local" ---@type string
      for k, v in pairs(metadata) do
        if type(k) == "string" and vim.endswith(k, "local.scope") then
          scope = v
        end
      end

      if node and vim.startswith(kind, "local.definition") then
        table.insert(definitions, { kind = kind, node = node, scope = scope })
      end

      if node and kind == "local.scope" then
        table.insert(scopes, node)
      end

      if node and kind == "local.reference" then
        table.insert(references, { kind = kind, node = node, scope = scope })
      end
    end

    return definitions, references, scopes
  end



  local function recurse_local_nodes(local_def, accumulator, full_match, last_match)
    if type(local_def) ~= "table" then
      return
    end
    if local_def.node then
      accumulator(local_def, local_def.node, full_match, last_match)
    else
      for match_key, def in pairs(local_def) do
        recurse_local_nodes(def, accumulator,
          full_match and (full_match .. "." .. match_key) or match_key, match_key)
      end
    end
  end

  local get_local_nodes = function(local_def)
    local result = {}
    recurse_local_nodes(local_def, function(def, _, kind)
      table.insert(result, vim.tbl_extend("keep", { kind = kind }, def))
    end)
    return result
  end

  local contents = function(cb)
    coroutine.wrap(function()
      local co = coroutine.running()
      for _, definition in ipairs(get(opts.bufnr)) do
        local nodes = get_local_nodes(definition)
        for _, node in ipairs(nodes) do
          if node.node then
            vim.schedule(function()
              -- Remove node prefix, e.g. `locals.definition.var`
              node.kind = node.kind and node.kind:gsub(".*%.", "")
              local lnum, col, _, _ = vim.treesitter.get_node_range(node.node)
              local node_text = vim.treesitter.get_node_text(node.node, opts.bufnr)
              local node_kind = node.kind and utils.ansi_from_hl(kind2hl(node.kind), node.kind)
              local entry = string.format("[%s]%s%s:%s:%s\t\t[%s] %s",
                utils.ansi_codes[opts.hls.buf_nr](tostring(opts.bufnr)),
                utils.nbsp,
                utils.ansi_codes[opts.hls.buf_name](opts._bufname),
                utils.ansi_codes[opts.hls.buf_linenr](tostring(lnum + 1)),
                utils.ansi_codes[opts.hls.path_colnr](tostring(col + 1)),
                node_kind or "",
                node_text)
              cb(entry, function(err)
                coroutine.resume(co)
                if err then cb(nil) end
              end)
            end)
            coroutine.yield()
          end
        end
      end
      cb(nil)
    end)()
  end

  opts = core.set_header(opts, opts.headers or { "actions" })

  return core.fzf_exec(contents, opts)
end

M.spellcheck = function(opts)
  opts = config.normalize_opts(opts, "spellcheck")
  if not opts then return end

  if #vim.bo.spelllang == 0 then
    utils.info("Spell language not set, use ':setl spl=...' to enable spell checking.")
    return
  end

  -- Default to current buffer
  opts._bufnr = tonumber(opts.bufnr) or vim.api.nvim_get_current_buf()
  opts._bufname = path.basename(vim.api.nvim_buf_get_name(opts._bufnr))
  if not opts._bufname or #opts._bufname == 0 then
    opts._bufname = utils.nvim_buf_get_name(opts._bufnr)
  end

  if utils.mode_is_visual() then
    local _, sel = utils.get_visual_selection()
    opts.start_line = opts.start_line or sel.start.line
    opts.end_line = opts.end_line or sel["end"].line
  end

  local contents = function(cb)
    coroutine.wrap(function()
      local co = coroutine.running()
      local data = {}

      -- Use vim.schedule to avoid
      -- E5560: vimL function must not be called in a lua loop callback
      vim.schedule(function()
        local bufnr = opts._bufnr
        local filepath = vim.api.nvim_buf_get_name(bufnr)
        if vim.api.nvim_buf_is_loaded(bufnr) then
          data = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
        elseif vim.fn.filereadable(filepath) ~= 0 then
          data = vim.fn.readfile(filepath, "")
        end
        coroutine.resume(co)
      end)

      -- wait for vim.schedule
      coroutine.yield()

      local offset = 0
      local start_line = opts.start_line or 1
      local end_line = opts.end_line or #data
      local lines = end_line - start_line + 1

      if opts.start == "cursor" then
        -- start display from current line and wrap from bottom
        offset = core.CTX().cursor[1] - start_line
      end

      for i = 1, lines do
        local lnum = i + offset
        if lnum > lines then
          lnum = lnum % lines
        end
        lnum = lnum + start_line - 1

        local line, from, to = data[lnum], 1, nil
        repeat
          local word_separator = opts.word_separator or "[%s%p]"
          local function trim(s)
            return s:gsub("^" .. word_separator .. "+", ""):gsub(word_separator .. "+$", "")
          end
          from, to = string.find(line, "%w+", from)
          local word = from and string.sub(line, from, to)
          local prefix = from and string.sub(line, from - 1, from - 1) or ""
          local postfix = to and string.sub(line, to + 1, to + 1) or ""
          local valid_word = word
              and (#prefix == 0 or prefix:match("^" .. word_separator))
              and (#postfix == 0 or postfix:match(word_separator .. "$"))
          if valid_word then
            local _, lead = word:find("^" .. word_separator .. "+")
            local spell = vim.spell.check(trim(word))[1]
            if spell then
              cb(string.format("[%s]%s%s:%s:%s\t\t%s",
                utils.ansi_codes[opts.hls.buf_nr](tostring(opts._bufnr)),
                utils.nbsp,
                utils.ansi_codes[opts.hls.buf_name](opts._bufname),
                utils.ansi_codes[opts.hls.buf_linenr](tostring(lnum)),
                utils.ansi_codes[opts.hls.path_colnr](tostring(from + (lead or 0))),
                trim(word)
              ), function(err)
                coroutine.resume(co)
                if err then cb(nil) end
              end)
              coroutine.yield()
            end
          end
          if from then from = to + 1 end
        until not from
      end
      cb(nil)
    end)()
  end

  opts = core.set_header(opts, opts.headers or { "actions" })

  return core.fzf_exec(contents, opts)
end

return M
