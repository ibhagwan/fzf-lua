local core = require "fzf-lua.core"
local path = require "fzf-lua.path"
local utils = require "fzf-lua.utils"
local shell = require "fzf-lua.shell"
local config = require "fzf-lua.config"
local make_entry = require "fzf-lua.make_entry"

local M = {}

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
  local bufnrs = vim.tbl_filter(function(b)
    if not vim.api.nvim_buf_is_valid(b) then
      excluded[b] = true
    elseif not opts.show_unlisted and vim.fn.buflisted(b) ~= 1 then
      excluded[b] = true
    elseif not opts.show_unloaded and not vim.api.nvim_buf_is_loaded(b) then
      excluded[b] = true
    elseif opts.ignore_current_buffer and b == core.CTX().bufnr then
      excluded[b] = true
    elseif opts.current_tab_only and not curtab_bufnrs[b] then
      excluded[b] = true
    elseif opts.no_term_buffers and utils.is_term_buffer(b) then
      excluded[b] = true
    elseif opts.cwd_only and not path.is_relative_to(vim.api.nvim_buf_get_name(b), vim.loop.cwd()) then
      excluded[b] = true
    elseif opts.cwd and not path.is_relative_to(vim.api.nvim_buf_get_name(b), opts.cwd) then
      excluded[b] = true
    end
    if utils.buf_is_qf(b) then
      if opts.show_quickfix then
        -- show_quickfix trumps show_unlisted
        excluded[b] = nil
      else
        excluded[b] = true
      end
    end
    if not excluded[b] and b > max_bufnr then
      max_bufnr = b
    end
    return not excluded[b]
  end, unfiltered)

  return bufnrs, excluded, max_bufnr
end

local populate_buffer_entries = function(opts, bufnrs, tabh)
  local buffers = {}
  for _, bufnr in ipairs(bufnrs) do
    local flag = (bufnr == core.CTX().bufnr and "%")
        or (bufnr == core.CTX().alt_bufnr and "#") or " "

    local element = {
      bufnr = bufnr,
      flag = flag,
      info = vim.fn.getbufinfo(bufnr)[1],
      readonly = vim.api.nvim_buf_get_option(bufnr, "readonly")
    }

    -- Get the name for missing/quickfix/location list buffers
    -- NOTE: we get it here due to `gen_buffer_entry` called within a fast event
    if not element.info.name or #element.info.name == 0 then
      element.info.name = utils.nvim_buf_get_name(element.bufnr, element.info)
    end

    -- get the correct lnum for tabbed buffers
    if tabh then
      local winid = utils.winid_from_tabh(tabh, bufnr)
      if winid then
        element.info.lnum = vim.api.nvim_win_get_cursor(winid)[1]
      end
    end

    table.insert(buffers, element)
  end
  if opts.sort_lastused then
    -- switching buffers and opening 'buffers' in quick succession
    -- can lead to incorrect sort as 'lastused' isn't updated fast
    -- enough (neovim bug?), this makes sure the current buffer is
    -- always on top (#646)
    -- Hopefully this gets solved before the year 2100
    -- DON'T FORCE ME TO UPDATE THIS HACK NEOVIM LOL
    local future = os.time({ year = 2100, month = 1, day = 1, hour = 0, minute = 00 })
    local get_unixtime = function(buf)
      if buf.flag == "%" then
        return future
      elseif buf.flag == "#" then
        return future - 1
      else
        return buf.info.lastused
      end
    end
    table.sort(buffers, function(a, b)
      return get_unixtime(a) > get_unixtime(b)
    end)
  end
  return buffers
end


local function gen_buffer_entry(opts, buf, max_bufnr, cwd)
  -- local hidden = buf.info.hidden == 1 and 'h' or 'a'
  local hidden = ""
  local readonly = buf.readonly and "=" or " "
  local changed = buf.info.changed == 1 and "+" or " "
  local flags = hidden .. readonly .. changed
  local leftbr = "["
  local rightbr = "]"
  local bufname = #buf.info.name > 0 and path.relative_to(buf.info.name, cwd or vim.loop.cwd())
  if opts.filename_only then
    bufname = path.basename(bufname)
  end
  -- replace $HOME with '~' for paths outside of cwd
  bufname = path.HOME_to_tilde(bufname)
  if opts.path_shorten and not bufname:match("^%a+://") then
    bufname = path.shorten(bufname, tonumber(opts.path_shorten))
  end
  -- add line number
  bufname = ("%s:%s"):format(bufname, buf.info.lnum > 0 and buf.info.lnum or "")
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
    if utils.is_term_bufname(buf.info.name) then
      -- get shell-like icon for terminal buffers
      buficon, hl = make_entry.get_devicon(buf.info.name, "sh")
    else
      local filename = path.tail(buf.info.name)
      local extension = path.extension(filename)
      buficon, hl = make_entry.get_devicon(filename, extension)
    end
    if opts.color_icons then
      -- fallback to "grey" color (#817)
      local fn = utils.ansi_codes[hl] or utils.ansi_codes["dark_grey"]
      buficon = fn(buficon)
    end
  end
  local max_bufnr_w = 3 + #tostring(max_bufnr) + utils.ansi_escseq_len(bufnrstr)
  local item_str = string.format("%s%s%s%s%s%s%s%s",
    utils._if(opts._prefix, opts._prefix, ""),
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

  opts.__fn_reload = opts.__fn_reload or function(_)
    return function(cb)
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
  end

  -- build the "reload" cmd and remove '-- {+}' from the initial cmd
  local reload, id = shell.reload_action_cmd(opts, "{+}")
  local contents = reload:gsub("%-%-%s+{%+}$", "")
  opts.__reload_cmd = reload

  -- get current tab/buffer/previous buffer
  -- save as a func ref for resume to reuse
  opts._fn_pre_fzf = function()
    shell.set_protected(id)
    core.CTX(true) -- include `nvim_list_bufs` in context
  end

  if opts.fzf_opts["--header-lines"] == nil then
    opts.fzf_opts["--header-lines"] =
        (not opts.ignore_current_buffer and opts.sort_lastused) and "1"
  end

  opts = core.set_header(opts, opts.headers or { "actions", "cwd" })
  opts = core.set_fzf_field_index(opts)

  core.fzf_exec(contents, opts)
end

M.lines = function(opts)
  opts = config.normalize_opts(opts, "lines")
  M.buffer_lines(opts)
end

M.blines = function(opts)
  opts = config.normalize_opts(opts, "blines")
  opts.current_buffer_only = true
  M.buffer_lines(opts)
end


M.buffer_lines = function(opts)
  if not opts then return end

  opts.fn_pre_fzf = function() core.CTX(true) end
  opts.fn_pre_fzf()

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

      for _, bufnr in ipairs(buffers) do
        local data = {}
        local bufname, buficon, hl
        -- use vim.schedule to avoid
        -- E5560: vimL function must not be called in a lua loop callback
        vim.schedule(function()
          local filepath = vim.api.nvim_buf_get_name(bufnr)
          if vim.api.nvim_buf_is_loaded(bufnr) then
            data = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
          elseif vim.fn.filereadable(filepath) ~= 0 then
            data = vim.fn.readfile(filepath, "")
          end
          bufname = path.basename(filepath)
          if opts.file_icons then
            local filename = path.tail(bufname)
            local extension = path.extension(filename)
            buficon, hl = make_entry.get_devicon(filename, extension)
            if opts.color_icons then
              buficon = utils.ansi_codes[hl](buficon)
            end
          end
          if not bufname or #bufname == 0 then
            bufname = utils.nvim_buf_get_name(bufnr)
          end
          coroutine.resume(co)
        end)

        -- wait for vim.schedule
        coroutine.yield()

        local offset, lines = 0, #data
        if opts.current_buffer_only and opts.start == "cursor" then
          -- start display from current line and wrap from bottom (#822)
          offset = core.CTX().cursor[1] - 1
        end

        for i = 1, lines do
          local lnum = i + offset
          if lnum > lines then
            lnum = lnum % lines
          end
          add_entry(string.format("[%s]%s%s%s%s:%s: %s",
            utils.ansi_codes[opts.hls.buf_nr](tostring(bufnr)),
            utils.nbsp,
            buficon or "",
            buficon and utils.nbsp or "",
            utils.ansi_codes[opts.hls.buf_name](bufname),
            utils.ansi_codes[opts.hls.buf_linenr](tostring(lnum)),
            data[lnum]), co)
        end
      end
      cb(nil)
    end)()
  end

  opts = core.set_fzf_field_index(opts, "{3}", opts._is_skim and "{}" or "{..-2}")

  core.fzf_exec(contents, opts)
end

M.tabs = function(opts)
  opts = config.normalize_opts(opts, "tabs")
  if not opts then return end

  opts._list_bufs = function()
    local res = {}
    for i, t in ipairs(vim.api.nvim_list_tabpages()) do
      for _, w in ipairs(vim.api.nvim_tabpage_list_wins(t)) do
        local b = vim.api.nvim_win_get_buf(w)
        -- since this function is called after fzf window
        -- is created, exclude the scratch fzf buffers
        if core.CTX().bufmap[tostring(b)] then
          opts._tab_to_buf[i] = opts._tab_to_buf[i] or {}
          opts._tab_to_buf[i][b] = t
          table.insert(res, b)
        end
      end
    end
    return res
  end

  opts.__fn_reload = opts.__fn_reload or function(_)
    -- we do not return the populate function with cb directly to avoid
    -- E5560: nvim_exec must not be called in a lua loop callback
    local entries = {}
    local populate = function(cb)
      opts._tab_to_buf = {}

      local filtered, excluded, max_bufnr = filter_buffers(opts, opts._list_bufs)
      if not next(filtered) then return end

      -- remove the filtered-out buffers
      for b, _ in pairs(excluded) do
        for _, bufnrs in pairs(opts._tab_to_buf) do
          bufnrs[b] = nil
        end
      end

      for t, bufnrs in pairs(opts._tab_to_buf) do
        local tab_cwd = vim.fn.getcwd(-1, t)

        local opt_hl = function(k, default_msg, default_hl)
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

        local tab_cwd_tilde = path.HOME_to_tilde(tab_cwd)
        local title, fn_title_hl = opt_hl("tab_title",
          function(s)
            return string.format("%s%s#%d%s", s, utils.nbsp, t,
              (vim.loop.cwd() == tab_cwd and ""
                or string.format(": %s", tab_cwd_tilde)))
          end,
          utils.ansi_codes[opts.hls.tab_title])

        local marker, fn_marker_hl = opt_hl("tab_marker",
          function(s) return s end,
          utils.ansi_codes[opts.hls.tab_marker])

        local tab_cwd_tilde_base64 = vim.base64
            and vim.base64.encode(tab_cwd_tilde)
            or tab_cwd_tilde
        if not opts.current_tab_only then
          cb(string.format("%d)%s:%s%s\t%s", t, tab_cwd_tilde_base64, utils.nbsp,
            fn_title_hl(title),
            (t == core.CTX().tabnr) and fn_marker_hl(marker) or ""))
        end

        local bufnrs_flat = {}
        for b, _ in pairs(bufnrs) do
          table.insert(bufnrs_flat, b)
        end

        opts.sort_lastused = false
        opts._prefix = string.format("%d)%s:%s%s%s",
          t, tab_cwd_tilde_base64, utils.nbsp, utils.nbsp, utils.nbsp)
        local tabh = vim.api.nvim_list_tabpages()[t]
        local buffers = populate_buffer_entries(opts, bufnrs_flat, tabh)
        for _, bufinfo in pairs(buffers) do
          cb(gen_buffer_entry(opts, bufinfo, max_bufnr, tab_cwd))
        end
      end
      cb(nil)
    end
    populate(function(e)
      if e then
        table.insert(entries, e)
      end
    end)
    return entries
  end

  -- build the "reload" cmd and remove '-- {+}' from the initial cmd
  local reload, id = shell.reload_action_cmd(opts, "{+}")
  local contents = reload:gsub("%-%-%s+{%+}$", "")
  opts.__reload_cmd = reload

  -- get current tab/buffer/previous buffer
  -- save as a func ref for resume to reuse
  opts._fn_pre_fzf = function()
    shell.set_protected(id)
    core.CTX(true) -- include `nvim_list_bufs` in context
  end

  opts = core.set_header(opts, opts.headers or { "actions", "cwd" })
  opts = core.set_fzf_field_index(opts, "{3}", "{}")

  core.fzf_exec(contents, opts)
end

return M
