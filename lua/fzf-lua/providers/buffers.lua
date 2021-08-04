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
  return string.match(line, "%[.*%] (.+)")
end

M.buffers = function(opts)

  opts = config.normalize_opts(opts, config.globals.buffers)

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

  coroutine.wrap(function ()
    local items = {}

    local bufnrs = vim.tbl_filter(function(b)
      if 1 ~= vim.fn.buflisted(b) then
          return false
      end
      -- only hide unloaded buffers if opts.show_all_buffers is false, keep them listed if true or nil
      if opts.show_all_buffers == false and not vim.api.nvim_buf_is_loaded(b) then
        return false
      end
      if opts.ignore_current_buffer and b == vim.api.nvim_get_current_buf() then
        return false
      end
      if opts.cwd_only and not string.find(vim.api.nvim_buf_get_name(b), vim.loop.cwd(), 1, true) then
        return false
      end
      return true
    end, vim.api.nvim_list_bufs())
    if not next(bufnrs) then return end

    local header_line = false
    local buffers = {}
    for _, bufnr in ipairs(bufnrs) do
      local flag = bufnr == vim.fn.bufnr('') and '%' or (bufnr == vim.fn.bufnr('#') and '#' or ' ')

      local element = {
        bufnr = bufnr,
        flag = flag,
        info = vim.fn.getbufinfo(bufnr)[1],
      }

      if opts.sort_lastused and (flag == "#" or flag == "%") then
        if flag == "%" then header_line = true end
        local idx = ((buffers[1] ~= nil and buffers[1].flag == "%") and 2 or 1)
        table.insert(buffers, idx, element)
      else
        table.insert(buffers, element)
      end
    end

    for _, buf in pairs(buffers) do
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
        bufname = utils.ansi_codes.green(bufname)
        leftbr = utils.ansi_codes.green('[')
        rightbr = utils.ansi_codes.green(']')
      elseif buf.flag == '#' then
        flags = utils.ansi_codes.cyan(buf.flag) .. flags
      else
        flags = " " .. flags
      end
      local bufnrstr = string.format("%s%s%s", leftbr,
        utils.ansi_codes.yellow(string.format(buf.bufnr)), rightbr)
      local buficon = ''
      if opts.file_icons then
        local extension = path.extension(buf.info.name)
        buficon = core.get_devicon(buf.info.name, extension)
        if opts.color_icons then
          buficon = utils.ansi_codes[config.globals.file_icon_colors[extension] or "dark_grey"](buficon) .. " "
        end
      end
      local item_str = string.format("%s%s %s %s%s",
        utils._if(buf.bufnr>9, '' , ' '),
        bufnrstr, flags, buficon, bufname)
      table.insert(items, item_str)
    end

    opts.preview = act
    opts._fzf_cli_args = utils._if(
      header_line and not opts.ignore_current_buffer,
      '--header-lines=1', ''
    )

    local selected = require("fzf").fzf(items,
      core.build_fzf_cli(opts),
      config.winopts(opts))

    if not selected then return end

    if #selected > 1 then
      for i = 2, #selected do
          selected[i] = tostring(getbufnumber(selected[i]))
      end
    end

    actions.act(opts.actions, selected)

  end)()
end

return M
