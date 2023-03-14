local core = require "fzf-lua.core"
local path = require "fzf-lua.path"
local utils = require "fzf-lua.utils"
local config = require "fzf-lua.config"
local make_entry = require "fzf-lua.make_entry"

local M = {}

-- will hold current/previous buffer/tab
local __STATE = {}

local UPDATE_STATE = function()
  __STATE = {
    curtabidx = vim.fn.tabpagenr(),
    curtab = vim.api.nvim_win_get_tabpage(0),
    curbuf = vim.api.nvim_get_current_buf(),
    prevbuf = vim.fn.bufnr("#"),
    buflist = vim.api.nvim_list_bufs(),
    bufmap = (function()
      local map = {}
      for _, b in ipairs(vim.api.nvim_list_bufs()) do
        map[b] = true
      end
      return map
    end)()
  }
end

local filter_buffers = function(opts, unfiltered)
  if type(unfiltered) == "function" then
    unfiltered = unfiltered()
  end

  local curtab_bufnrs = {}
  if opts.current_tab_only then
    for _, w in ipairs(vim.api.nvim_tabpage_list_wins(__STATE.curtab)) do
      local b = vim.api.nvim_win_get_buf(w)
      curtab_bufnrs[b] = true
    end
  end

  local excluded = {}
  local bufnrs = vim.tbl_filter(function(b)
    if not opts.show_unlisted and 1 ~= vim.fn.buflisted(b) then
      excluded[b] = true
    end
    -- only hide unloaded buffers if opts.show_all_buffers is false, keep them listed if true or nil
    if opts.show_all_buffers == false and not vim.api.nvim_buf_is_loaded(b) then
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
    if opts.ignore_current_buffer and b == __STATE.curbuf then
      excluded[b] = true
    end
    if opts.current_tab_only and not curtab_bufnrs[b] then
      excluded[b] = true
    end
    if opts.no_term_buffers and utils.is_term_buffer(b) then
      excluded[b] = true
    end
    if opts.cwd_only and not path.is_relative(vim.api.nvim_buf_get_name(b), vim.loop.cwd()) then
      excluded[b] = true
    elseif opts.cwd and not path.is_relative(vim.api.nvim_buf_get_name(b), opts.cwd) then
      excluded[b] = true
    end
    return not excluded[b]
  end, unfiltered)

  return bufnrs, excluded
end

local populate_buffer_entries = function(opts, bufnrs, tabh)
  local buffers = {}
  for _, bufnr in ipairs(bufnrs) do
    local flag = (bufnr == __STATE.curbuf and "%") or
        (bufnr == __STATE.prevbuf and "#") or " "

    local element = {
      bufnr = bufnr,
      flag = flag,
      info = vim.fn.getbufinfo(bufnr)[1],
    }

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


local function gen_buffer_entry(opts, buf, hl_curbuf, cwd)
  -- local hidden = buf.info.hidden == 1 and 'h' or 'a'
  local hidden = ""
  local readonly = vim.api.nvim_buf_get_option(buf.bufnr, "readonly") and "=" or " "
  local changed = buf.info.changed == 1 and "+" or " "
  local flags = hidden .. readonly .. changed
  local leftbr = utils.ansi_codes.clear("[")
  local rightbr = utils.ansi_codes.clear("]")
  local bufname = #buf.info.name > 0 and
      path.relative(buf.info.name, cwd or vim.loop.cwd()) or
      utils.nvim_buf_get_name(buf.bufnr, buf.info)
  if opts.filename_only then
    bufname = path.basename(bufname)
  end
  -- replace $HOME with '~' for paths outside of cwd
  bufname = path.HOME_to_tilde(bufname)
  -- add line number
  bufname = ("%s:%s"):format(bufname, buf.info.lnum > 0 and buf.info.lnum or "")
  if buf.flag == "%" then
    flags = utils.ansi_codes.red(buf.flag) .. flags
    if hl_curbuf then
      -- no header line, highlight current buffer
      leftbr = utils.ansi_codes.green("[")
      rightbr = utils.ansi_codes.green("]")
      bufname = utils.ansi_codes.green(bufname)
    end
  elseif buf.flag == "#" then
    flags = utils.ansi_codes.cyan(buf.flag) .. flags
  else
    flags = utils.nbsp .. flags
  end
  local bufnrstr = string.format("%s%s%s", leftbr,
    utils.ansi_codes.yellow(string.format(buf.bufnr)), rightbr)
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
      buficon = utils.ansi_codes[hl](buficon)
    end
  end
  local item_str = string.format("%s%s%s%s%s%s%s%s",
    utils._if(opts._prefix, opts._prefix, ""),
    string.format("%-32s", bufnrstr),
    utils.nbsp,
    flags,
    utils.nbsp,
    buficon,
    utils.nbsp,
    bufname)
  return item_str
end

M.buffers = function(opts)
  opts = config.normalize_opts(opts, config.globals.buffers)
  if not opts then return end

  -- get current tab/buffer/previous buffer
  -- save as a func ref for resume to reuse
  opts.fn_pre_fzf = UPDATE_STATE

  local contents = function(cb)
    local filtered = filter_buffers(opts, __STATE.buflist)

    if next(filtered) then
      local buffers = populate_buffer_entries(opts, filtered)
      for _, bufinfo in pairs(buffers) do
        cb(gen_buffer_entry(opts, bufinfo, not opts.sort_lastused))
      end
    end
    cb(nil)
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
  opts = config.normalize_opts(opts, config.globals.lines)
  M.buffer_lines(opts)
end

M.blines = function(opts)
  opts = config.normalize_opts(opts, config.globals.blines)
  opts.current_buffer_only = true
  opts.line_field_index = opts.line_field_index or 2
  M.buffer_lines(opts)
end


M.buffer_lines = function(opts)
  if not opts then return end

  opts.fn_pre_fzf = UPDATE_STATE
  opts.fn_pre_fzf()

  local buffers = filter_buffers(opts,
    opts.current_buffer_only and { __STATE.curbuf } or __STATE.buflist)

  local items = {}

  for _, bufnr in ipairs(buffers) do
    local data = {}
    local filepath = vim.api.nvim_buf_get_name(bufnr)
    if vim.api.nvim_buf_is_loaded(bufnr) then
      data = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    elseif vim.fn.filereadable(filepath) ~= 0 then
      data = vim.fn.readfile(filepath, "")
    end
    local bufname = path.basename(filepath)
    local buficon, hl
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
    for l, text in ipairs(data) do
      table.insert(items, ("[%s]%s%s%s%s:%s: %s"):format(
        utils.ansi_codes.yellow(tostring(bufnr)),
        utils.nbsp,
        buficon or "",
        buficon and utils.nbsp or "",
        utils.ansi_codes.magenta(bufname),
        utils.ansi_codes.green(tostring(l)),
        text))
    end
  end

  if opts.search and #opts.search > 0 then
    opts.fzf_opts["--query"] = vim.fn.shellescape(opts.search)
  end

  opts = core.set_fzf_field_index(opts, 3, opts._is_skim and "{}" or "{..-2}")

  core.fzf_exec(items, opts)
end

M.tabs = function(opts)
  opts = config.normalize_opts(opts, config.globals.tabs)
  if not opts then return end

  opts.fn_pre_fzf = UPDATE_STATE

  opts._list_bufs = function()
    local res = {}
    for i, t in ipairs(vim.api.nvim_list_tabpages()) do
      for _, w in ipairs(vim.api.nvim_tabpage_list_wins(t)) do
        local b = vim.api.nvim_win_get_buf(w)
        -- since this function is called after fzf window
        -- is created, exclude the scratch fzf buffers
        if __STATE.bufmap[b] then
          opts._tab_to_buf[i] = opts._tab_to_buf[i] or {}
          opts._tab_to_buf[i][b] = t
          table.insert(res, b)
        end
      end
    end
    return res
  end

  local contents = function(cb)
    opts._tab_to_buf = {}

    local filtered, excluded = filter_buffers(opts, opts._list_bufs)
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
            msg = opts[k][1](t, t == __STATE.curtabidx)
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
          msg = opts[k](t, t == __STATE.curtabidx)
        end
        return msg, hl
      end

      local title, fn_title_hl = opt_hl("tab_title",
        function(s)
          return string.format("%s%s#%d%s", s, utils.nbsp, t,
            (vim.loop.cwd() == tab_cwd and ""
            or string.format(": %s", path.HOME_to_tilde(tab_cwd))))
        end,
        utils.ansi_codes.blue)

      local marker, fn_marker_hl = opt_hl("tab_marker",
        function(s) return s end,
        function(s)
          return utils.ansi_codes.blue(utils.ansi_codes.bold(s));
        end)

      if not opts.current_tab_only then
        cb(string.format("%d)%s%s\t%s", t, utils.nbsp,
          fn_title_hl(title),
          (t == __STATE.curtabidx) and fn_marker_hl(marker) or ""))
      end

      local bufnrs_flat = {}
      for b, _ in pairs(bufnrs) do
        table.insert(bufnrs_flat, b)
      end

      opts.sort_lastused = false
      opts._prefix = ("%d)%s%s%s"):format(t, utils.nbsp, utils.nbsp, utils.nbsp)
      local tabh = vim.api.nvim_list_tabpages()[t]
      local buffers = populate_buffer_entries(opts, bufnrs_flat, tabh)
      for _, bufinfo in pairs(buffers) do
        cb(gen_buffer_entry(opts, bufinfo, false, tab_cwd))
      end
    end
    cb(nil)
  end

  opts = core.set_header(opts, opts.headers or { "actions", "cwd" })
  opts = core.set_fzf_field_index(opts, 3, "{}")

  core.fzf_exec(contents, opts)
end

return M
