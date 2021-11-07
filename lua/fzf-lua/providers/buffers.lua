if not pcall(require, "fzf") then
  return
end

local action = require("fzf.actions").action
local core = require "fzf-lua.core"
local path = require "fzf-lua.path"
local utils = require "fzf-lua.utils"
local config = require "fzf-lua.config"
local actions = require "fzf-lua.actions"
local fn, api = vim.fn, vim.api

local M = {}

local function getbufnumber(line)
  return tonumber(string.match(line, "%[(%d+)"))
end

local function getfilename(line)
  -- return string.match(line, "%[.*%] (.+)")
  -- greedy match anything after last nbsp
  return line:match("[^" .. utils.nbsp .. "]*$")
end

local filter_buffers = function(opts, unfiltered)
  local curtab_bufnrs = {}
  if opts.current_tab_only then
    local curtab = vim.api.nvim_win_get_tabpage(0)
    for _, w in ipairs(vim.api.nvim_tabpage_list_wins(curtab)) do
      local b = vim.api.nvim_win_get_buf(w)
      curtab_bufnrs[b] = true
    end
  end

  local excluded = {}
  local bufnrs = vim.tbl_filter(function(b)
    if 1 ~= vim.fn.buflisted(b) then
      excluded[b] = true
    end
    -- only hide unloaded buffers if opts.show_all_buffers is false, keep them listed if true or nil
    if opts.show_all_buffers == false and not vim.api.nvim_buf_is_loaded(b) then
      excluded[b] = true
    end
    if opts.ignore_current_buffer and b == vim.api.nvim_get_current_buf() then
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
    end
    return not excluded[b]
  end, unfiltered)

  return bufnrs, excluded
end

local make_buffer_entries = function(opts, bufnrs, tabnr, curbuf)
  local header_line = false
  local buffers = {}
  curbuf = curbuf or vim.fn.bufnr('')
  for _, bufnr in ipairs(bufnrs) do
    local flag = bufnr == curbuf and '%' or (bufnr == vim.fn.bufnr('#') and '#' or ' ')

    local element = {
      bufnr = bufnr,
      flag = flag,
      info = vim.fn.getbufinfo(bufnr)[1],
    }

    -- get the correct lnum for tabbed buffers
    if tabnr then
      local winid = utils.winid_from_tab_buf(tabnr, bufnr)
      if winid then
        element.info.lnum = vim.api.nvim_win_get_cursor(winid)[1]
      end
    end

    if opts.sort_lastused and flag == "%" then
      header_line = true
    end

    table.insert(buffers, element)
  end
  if opts.sort_lastused then
    table.sort(buffers, function(a, b)
      return a.info.lastused > b.info.lastused
    end)
  end
  return buffers, header_line
end


local function add_buffer_entry(opts, buf, items, header_line)
  -- local hidden = buf.info.hidden == 1 and 'h' or 'a'
  local hidden = ''
  local readonly = vim.api.nvim_buf_get_option(buf.bufnr, 'readonly') and '=' or ' '
  local changed = buf.info.changed == 1 and '+' or ' '
  local flags = hidden .. readonly .. changed
  local leftbr = utils.ansi_codes.clear('[')
  local rightbr = utils.ansi_codes.clear(']')
  local bufname = string.format("%s:%s",
    utils._if(#buf.info.name>0, path.relative(buf.info.name, vim.loop.cwd()), "[No Name]"),
    utils._if(buf.info.lnum>0, buf.info.lnum, ""))
  if buf.flag == '%' then
    flags = utils.ansi_codes.red(buf.flag) .. flags
    if not header_line then
      leftbr = utils.ansi_codes.green('[')
      rightbr = utils.ansi_codes.green(']')
      bufname = utils.ansi_codes.green(bufname)
    end
  elseif buf.flag == '#' then
    flags = utils.ansi_codes.cyan(buf.flag) .. flags
  else
    flags = utils.nbsp .. flags
  end
  local bufnrstr = string.format("%s%s%s", leftbr,
    utils.ansi_codes.yellow(string.format(buf.bufnr)), rightbr)
  local buficon = ''
  local hl = ''
  if opts.file_icons then
    if utils.is_term_bufname(buf.info.name) then
      -- get shell-like icon for terminal buffers
      buficon, hl = core.get_devicon(buf.info.name, "sh")
    else
      local filename = path.tail(buf.info.name)
      local extension = path.extension(filename)
      buficon, hl = core.get_devicon(filename, extension)
    end
    if opts.color_icons then
      buficon = utils.ansi_codes[hl](buficon)
    end
  end
  local item_str = string.format("%s%s%s%s%s%s%s%s",
    utils._if(opts._prefix, opts._prefix, ''),
    string.format("%-32s", bufnrstr),
    utils.nbsp,
    flags,
    utils.nbsp,
    buficon,
    utils.nbsp,
    bufname)
  table.insert(items, item_str)
  return items
end

M.buffers = function(opts)

  opts = config.normalize_opts(opts, config.globals.buffers)
  if not opts then return end

    local act = action(function (items, fzf_lines, _)
      -- only preview first item
      local item = items[1]
      local buf = getbufnumber(item)
      if api.nvim_buf_is_loaded(buf) then
        return api.nvim_buf_get_lines(buf, 0, fzf_lines, false)
      else
        local name = getfilename(item)
        if fn.filereadable(name) ~= 0 then
          return fn.readfile(name, "", fzf_lines)
        end
        return "UNLOADED: " .. name
      end
    end)

  local filtered = filter_buffers(opts,
    opts._list_bufs and opts._list_bufs() or vim.api.nvim_list_bufs())

  if not next(filtered) then return end

  coroutine.wrap(function ()
    local items = {}

    local buffers, header_line = make_buffer_entries(opts, filtered, nil, opts.curbuf)
    for _, buf in pairs(buffers) do
      items = add_buffer_entry(opts, buf, items, header_line)
    end

    opts.fzf_opts['--preview'] = act
    if header_line and not opts.ignore_current_buffer then
      opts.fzf_opts['--header-lines'] = '1'
    end

    local selected = core.fzf(opts, items)
    if not selected then return end

    actions.act(opts.actions, selected, opts)

  end)()
end

M.lines = function(opts)
  opts = config.normalize_opts(opts, config.globals.lines)
  M.buffer_lines(opts)
end

M.blines = function(opts)
  opts = config.normalize_opts(opts, config.globals.blines)
  opts.current_buffer_only = true
  M.buffer_lines(opts)
end


M.buffer_lines = function(opts)
  if not opts then return end

  opts.no_term_buffers = true
  local buffers = filter_buffers(opts,
    opts.current_buffer_only and { vim.api.nvim_get_current_buf() } or
    vim.api.nvim_list_bufs())

  coroutine.wrap(function()
    local items = {}

    for _, bufnr in ipairs(buffers) do
      local data = {}
      local filepath = api.nvim_buf_get_name(bufnr)
      if api.nvim_buf_is_loaded(bufnr) then
        data = api.nvim_buf_get_lines(bufnr, 0, -1, false)
      elseif vim.fn.filereadable(filepath) ~= 0 then
        data = vim.fn.readfile(filepath, "")
      end
      local bufname = path.basename(filepath)
      local buficon, hl
      if opts.file_icons then
        local filename = path.tail(bufname)
        local extension = path.extension(filename)
        buficon, hl = core.get_devicon(filename, extension)
        if opts.color_icons then
          buficon = utils.ansi_codes[hl](buficon)
        end
      end
      for l, text in ipairs(data) do
        table.insert(items, ("[%s]%s%s%s%s:%s: %s"):format(
          utils.ansi_codes.yellow(tostring(bufnr)),
          utils.nbsp,
          buficon or '',
          buficon and utils.nbsp or '',
          utils.ansi_codes.magenta(#bufname>0 and bufname or "[No Name]"),
          utils.ansi_codes.green(tostring(l)),
          text))
      end
    end

    -- ignore bufnr when searching
    -- disable multi-select
    opts.fzf_opts["--no-multi"] = ''
    opts.fzf_opts["--preview-window"] = 'hidden:right:0'
    opts.fzf_opts["--delimiter"] = vim.fn.shellescape(']')
    opts.fzf_opts["--nth"] = '2,-1'

    if opts.search and #opts.search>0 then
      opts.fzf_opts['--query'] = vim.fn.shellescape(opts.search)
    end

    local selected = core.fzf(opts, items)
    if not selected then return end

    -- get the line number
    local line = tonumber(selected[2]:match(":(%d+):"))

    actions.act(opts.actions, selected, opts)

    if line then
      -- add current location to jumplist
      vim.cmd("normal! m`")
      vim.api.nvim_win_set_cursor(0, {line, 0})
      vim.cmd("norm! zz")
    end

  end)()
end

M.tabs = function(opts)

  opts = config.normalize_opts(opts, config.globals.tabs)
  if not opts then return end

  local curtab = vim.api.nvim_win_get_tabpage(0)

  opts._tab_to_buf = {}
  opts._list_bufs = function()
    local res = {}
    for _, t in ipairs(vim.api.nvim_list_tabpages()) do
      for _, w in ipairs(vim.api.nvim_tabpage_list_wins(t)) do
        local b = vim.api.nvim_win_get_buf(w)
        opts._tab_to_buf[t] = opts._tab_to_buf[t] or {}
        opts._tab_to_buf[t][b] = true
        table.insert(res, b)
      end
    end
    return res
  end


  local filtered, excluded = filter_buffers(opts, opts._list_bufs())
  if not next(filtered) then return end

  -- remove the filtered-out buffers
  for b, _ in pairs(excluded) do
    for _, bufnrs in pairs(opts._tab_to_buf) do
      bufnrs[b] = nil
    end
  end
  coroutine.wrap(function ()
    local items = {}

    for t, bufnrs in pairs(opts._tab_to_buf) do

      table.insert(items, ("%d)%s%s\t%s"):format(t, utils.nbsp,
        utils.ansi_codes.blue("%s%s#%d"):format(opts.tab_title, utils.nbsp, t),
          (t==curtab) and utils.ansi_codes.blue(utils.ansi_codes.bold(opts.tab_marker)) or ''))

      local bufnrs_flat = {}
      for b, _ in pairs(bufnrs) do
        table.insert(bufnrs_flat, b)
      end

      opts.sort_lastused = false
      opts._prefix = ("%d)%s%s%s"):format(t, utils.nbsp, utils.nbsp, utils.nbsp)
      local buffers = make_buffer_entries(opts, bufnrs_flat, t)
      for _, buf in pairs(buffers) do
        items = add_buffer_entry(opts, buf, items, true)
      end
    end

    opts.fzf_opts["--no-multi"] = ''
    opts.fzf_opts["--preview-window"] = 'hidden:right:0'
    opts.fzf_opts["--delimiter"] = vim.fn.shellescape('[\\)]')
    opts.fzf_opts["--with-nth"] = '2'

    local selected = core.fzf(opts, items)

    if not selected then return end

    actions.act(opts.actions, selected, opts)

  end)()
end

return M
