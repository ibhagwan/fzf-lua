local uv = vim.uv or vim.loop
local core = require "fzf-lua.core"
local path = require "fzf-lua.path"
local utils = require "fzf-lua.utils"
local config = require "fzf-lua.config"
local devicons = require "fzf-lua.devicons"

local M = {}

M.commands = function(opts)
  opts = config.normalize_opts(opts, "commands")
  if not opts then return end

  local global_commands = vim.api.nvim_get_commands {}
  local buf_commands = vim.api.nvim_buf_get_commands(0, {})

  local builtin_commands = {}
  -- parse help doc to get builtin commands and descriptions
  if opts.include_builtin then
    local help = vim.fn.globpath(vim.o.rtp, "doc/index.txt")
    if uv.fs_stat(help) then
      local cmd, desc
      for line in utils.read_file(help):gmatch("[^\n]*\n") do
        if line:match("^|:[^|]") then
          if cmd then builtin_commands[cmd] = desc end
          cmd, desc = line:match("^|:(%S+)|%s*%S+%s*(.*%S)")
        elseif cmd then -- found
          if line:match("^%s%+%S") then desc = desc .. (line:match("^%s*(.*%S)") or "") end
          if line:match("^%s*$") then break end
        end
      end
      if cmd then builtin_commands[cmd] = desc end
    end
  end

  local commands = vim.tbl_extend("force", {}, global_commands, buf_commands, builtin_commands)

  local entries = {}

  if opts.sort_lastused then
    -- display last used commands at the top of the list (#748)
    -- iterate the command history from last used backwards
    -- each command found gets added to the top of the list
    -- and removed from the command map
    local history = vim.split(vim.fn.execute("history"), "\n")
    for i = #history, #history - 3, -1 do
      local cmd = history[i]:match("%d+%s+([^%s]+)")
      if buf_commands[cmd] then
        table.insert(entries, cmd)
        buf_commands[cmd] = nil
      end
      if global_commands[cmd] then
        table.insert(entries, cmd)
        global_commands[cmd] = nil
      end
      if builtin_commands[cmd] then
        table.insert(entries, cmd)
      end
    end
  end

  for k, _ in pairs(global_commands) do
    table.insert(entries, utils.ansi_codes.blue(k))
  end

  for k, v in pairs(buf_commands) do
    if type(v) == "table" then
      table.insert(entries, utils.ansi_codes.green(k))
    end
  end

  -- Sort before adding "builtin" so they don't end up atop the list
  if not opts.sort_lastused then
    table.sort(entries, function(a, b) return a < b end)
  end

  for k, _ in pairs(builtin_commands) do
    table.insert(entries, utils.ansi_codes.magenta(k))
  end

  opts.preview = function(args)
    local cmd = args[1]
    if commands[cmd] then
      cmd = vim.inspect(commands[cmd])
    end
    return cmd
  end

  core.fzf_exec(entries, opts)
end

local history = function(opts, str)
  local history = vim.fn.execute("history " .. str)
  history = vim.split(history, "\n")

  local entries = {}
  for i = #history, 3, -1 do
    local item = history[i]
    local _, finish = string.find(item, "%d+ +")
    table.insert(
      entries,
      opts.reverse_list and 1 or #entries + 1,
      string.sub(item, finish + 1))
  end

  core.fzf_exec(entries, opts)
end

local arg_header = function(sel_key, edit_key, text)
  sel_key = utils.ansi_codes.yellow(sel_key)
  edit_key = utils.ansi_codes.yellow(edit_key)
  return (":: %s to %s, %s to edit"):format(sel_key, text, edit_key)
end

M.command_history = function(opts)
  opts = config.normalize_opts(opts, "command_history")
  if not opts then return end
  if opts.fzf_opts["--header"] == nil then
    opts.fzf_opts["--header"] = arg_header("<CR>", "<Ctrl-e>", "execute")
  end
  history(opts, "cmd")
end

M.search_history = function(opts)
  opts = config.normalize_opts(opts, "search_history")
  if not opts then return end
  if opts.fzf_opts["--header"] == nil then
    opts.fzf_opts["--header"] = arg_header("<CR>", "<Ctrl-e>", "search")
  end
  history(opts, "search")
end

M.changes = function(opts)
  opts = config.normalize_opts(opts, "changes")
  return M.jumps(opts)
end

M.jumps = function(opts)
  opts = config.normalize_opts(opts, "jumps")
  if not opts then return end

  local jumps = vim.fn.execute(opts.cmd)
  jumps = vim.split(jumps, "\n")

  local entries = {}
  for i = #jumps - 1, 3, -1 do
    local jump, line, col, text = jumps[i]:match("(%d+)%s+(%d+)%s+(%d+)%s+(.*)")
    table.insert(entries, string.format(" %16s %15s %15s %s",
      utils.ansi_codes.yellow(jump),
      utils.ansi_codes.blue(line),
      utils.ansi_codes.green(col),
      text))
  end

  if utils.tbl_isempty(entries) then
    utils.info(("%s list is empty."):format(opts.h1 or "jump"))
    return
  end

  table.insert(entries, 1,
    string.format("%6s %s  %s %s", opts.h1 or "jump", "line", "col", "file/text"))

  opts.fzf_opts["--header-lines"] = 1

  core.fzf_exec(entries, opts)
end

M.tagstack = function(opts)
  opts = config.normalize_opts(opts, "tagstack")
  if not opts then return end

  local tagstack = vim.fn.gettagstack().items

  local tags = {}
  for i = #tagstack, 1, -1 do
    local tag = tagstack[i]
    tag.bufnr = tag.from[1]
    if vim.api.nvim_buf_is_valid(tag.bufnr) then
      tags[#tags + 1] = tag
      tag.filename = vim.fn.bufname(tag.bufnr)
      tag.lnum = tag.from[2]
      tag.col = tag.from[3]

      tag.text = vim.api.nvim_buf_get_lines(tag.bufnr, tag.lnum - 1, tag.lnum, false)[1] or ""
    end
  end

  if utils.tbl_isempty(tags) then
    utils.info("No tagstack available")
    return
  end

  local entries = {}
  for i, tag in ipairs(tags) do
    local bufname = path.HOME_to_tilde(path.relative_to(tag.filename, uv.cwd()))
    local buficon, hl
    if opts.file_icons then
      buficon, hl = devicons.get_devicon(bufname)
      if hl and opts.color_icons then
        buficon = utils.ansi_from_rgb(hl, buficon)
      end
    end
    -- table.insert(entries, ("%s)%s[%s]%s%s%s%s:%s:%s: %s %s"):format(
    table.insert(entries, ("%s)%s%s%s%s:%s:%s: %s %s"):format(
      utils.ansi_codes.yellow(tostring(i)),
      utils.nbsp,
      -- utils.ansi_codes.yellow(tostring(tag.bufnr)),
      -- utils.nbsp,
      buficon or "",
      buficon and utils.nbsp or "",
      utils.ansi_codes.magenta(#bufname > 0 and bufname or "[No Name]"),
      utils.ansi_codes.green(tostring(tag.lnum)),
      tag.col,
      utils.ansi_codes.red("[" .. tag.tagname .. "]"),
      tag.text))
  end

  core.fzf_exec(entries, opts)
end


M.marks = function(opts)
  opts = config.normalize_opts(opts, "marks")
  if not opts then return end

  local marks = vim.fn.execute("marks")
  marks = vim.split(marks, "\n")

  local entries = {}
  local pattern = opts.marks and opts.marks or ""
  for i = #marks, 3, -1 do
    local mark, line, col, text = marks[i]:match("(.)%s+(%d+)%s+(%d+)%s+(.*)")
    col = tostring(tonumber(col) + 1)
    if path.is_absolute(text) then
      text = path.HOME_to_tilde(text)
    end
    if not pattern or string.match(mark, pattern) then
      table.insert(entries, string.format(" %-15s %15s %15s %s",
        utils.ansi_codes.yellow(mark),
        utils.ansi_codes.blue(line),
        utils.ansi_codes.green(col),
        text))
    end
  end

  table.sort(entries, function(a, b) return a < b end)
  table.insert(entries, 1,
    string.format("%-5s %s  %s %s", "mark", "line", "col", "file/text"))

  opts.fzf_opts["--header-lines"] = 1
  --[[ opts.preview = function (args, fzf_lines, _)
    local mark = args[1]:match("[^ ]+")
    local bufnr, lnum, _, _ = unpack(vim.fn.getpos("'"..mark))
    if vim.api.nvim_buf_is_loaded(bufnr) then
      return vim.api.nvim_buf_get_lines(bufnr, lnum, fzf_lines+lnum, false)
    else
      local name = vim.fn.expand(args[1]:match(".* (.*)"))
      if vim.fn.filereadable(name) ~= 0 then
        return vim.fn.readfile(name, "", fzf_lines)
      end
      return "UNLOADED: " .. name
    end
  end ]]

  core.fzf_exec(entries, opts)
end

M.registers = function(opts)
  opts = config.normalize_opts(opts, "registers")
  if not opts then return end

  local registers = { [["]], "_", "#", "=", "_", "/", "*", "+", ":", ".", "%" }
  -- named
  for i = 0, 9 do
    table.insert(registers, tostring(i))
  end
  -- alphabetical
  for i = 65, 90 do
    table.insert(registers, string.char(i))
  end

  local function register_escape_special(reg, nl)
    if not reg then return end
    local gsub_map = {
      ["\3"]  = "^C", -- <C-c>
      ["\27"] = "^[", -- <Esc>
      ["\18"] = "^R", -- <C-r>
    }
    for k, v in pairs(gsub_map) do
      reg = reg:gsub(k, utils.ansi_codes.magenta(v))
    end
    return not nl and reg
        or nl == 2 and reg:gsub("\n$", "")
        or reg:gsub("\n", utils.ansi_codes.magenta("\\n"))
  end

  local entries = {}
  for _, r in ipairs(registers) do
    -- pcall as this could fail with:
    -- E5108: Error executing lua Vim:clipboard:
    --        provider returned invalid data
    local _, contents = pcall(vim.fn.getreg, r)
    contents = register_escape_special(contents, opts.multiline and 2 or 1)
    if (contents and #contents > 0) or not opts.ignore_empty then
      table.insert(entries, string.format("[%s] %s",
        utils.ansi_codes.yellow(r), contents))
    end
  end

  opts.preview = function(args)
    local r = args[1]:match("%[(.*)%] ")
    local _, contents = pcall(vim.fn.getreg, r)
    return contents and register_escape_special(contents) or args[1]
  end

  core.fzf_exec(entries, opts)
end

M.keymaps = function(opts)
  opts = config.normalize_opts(opts, "keymaps")
  if not opts then return end

  local key_modes = opts.modes or { "n", "i", "c", "v", "t" }
  local modes = {
    n = "blue",
    i = "red",
    c = "yellow",
    v = "magenta",
    t = "green"
  }
  local keymaps = {}
  local separator = "│"
  local fields = { "mode", "lhs", "desc", "rhs" }
  local field_fmt = { mode = "%s", lhs = "%-14s", desc = "%-33s", rhs = "%s" }

  if opts.show_desc == false then field_fmt.desc = nil end
  if opts.show_details == false then field_fmt.rhs = nil end

  local format = function(info)
    info.desc = string.sub(info.desc or "", 1, 33)
    local ret
    for _, f in ipairs(fields) do
      if field_fmt[f] then
        ret = string.format("%s%s" .. field_fmt[f], ret or "",
          ret and string.format(" %s ", separator) or "", info[f] or "")
      end
    end
    return ret
  end

  local function add_keymap(keymap)
    -- ignore dummy mappings
    if type(keymap.rhs) == "string" and #keymap.rhs == 0 then
      return
    end

    -- by default we ignore <SNR> and <Plug> mappings
    if type(keymap.lhs) == "string" and type(opts.ignore_patterns) == "table" then
      for _, p in ipairs(opts.ignore_patterns) do
        -- case insensitive pattern match
        local pattern, lhs = p:lower(), vim.trim(keymap.lhs:lower())
        if lhs:match(pattern) then
          return
        end
      end
    end

    keymap.str = format({
      mode = utils.ansi_codes[modes[keymap.mode] or "blue"](keymap.mode),
      lhs  = keymap.lhs:gsub("%s", "<Space>"),
      -- desc can be a multi-line string, normalize it
      desc = keymap.desc and string.gsub(keymap.desc, "\n%s+", "\r"),
      rhs  = keymap.rhs or string.format("%s", keymap.callback)
    })

    local k = string.format("[%s:%s:%s]", keymap.buffer, keymap.mode, keymap.lhs)
    keymaps[k] = keymap
  end

  for _, mode in pairs(key_modes) do
    local global = vim.api.nvim_get_keymap(mode)
    for _, keymap in pairs(global) do
      add_keymap(keymap)
    end
    local buf_local = vim.api.nvim_buf_get_keymap(0, mode)
    for _, keymap in pairs(buf_local) do
      add_keymap(keymap)
    end
  end

  local entries = {}
  for _, v in pairs(keymaps) do
    table.insert(entries, v.str)
  end

  opts.fzf_opts["--header-lines"] = "1"

  -- sort alphabetically
  table.sort(entries)

  local header_str = format({ mode = "m", lhs = "keymap", desc = "description", rhs = "detail" })
  table.insert(entries, 1, header_str)

  core.fzf_exec(entries, opts)
end

M.spell_suggest = function(opts)
  -- if not vim.wo.spell then return false end
  opts = config.normalize_opts(opts, "spell_suggest")
  if not opts then return end

  local cursor_word = vim.fn.expand "<cword>"
  local entries = vim.fn.spellsuggest(cursor_word)

  if utils.tbl_isempty(entries) then return end

  core.fzf_exec(entries, opts)
end

M.filetypes = function(opts)
  opts = config.normalize_opts(opts, "filetypes")
  if not opts then return end

  local entries = vim.fn.getcompletion("", "filetype")
  if utils.tbl_isempty(entries) then return end

  if opts.file_icons then
    entries = vim.tbl_map(function(ft)
      local buficon, hl = devicons.icon_by_ft(ft)
      if not buficon then buficon = " " end
      if hl then buficon = utils.ansi_from_hl(hl, buficon) end
      return string.format("%s%s%s", buficon, utils.nbsp, ft)
    end, entries)
  end

  core.fzf_exec(entries, opts)
end

M.packadd = function(opts)
  opts = config.normalize_opts(opts, "packadd")
  if not opts then return end

  local entries = vim.fn.getcompletion("", "packadd")
  if utils.tbl_isempty(entries) then return end

  core.fzf_exec(entries, opts)
end

M.menus = function(opts)
  opts = config.normalize_opts(opts, "menus")
  if not opts then return end

  -- @param prefix will be prepended to the entry name
  local function gen_menu_entries(prefix, entry)
    local name = prefix and ("%s.%s"):format(prefix, entry.name) or entry.name
    if entry.submenus then
      -- entry.submenus is a list of {}
      return vim.tbl_map(
        function(x)
          return gen_menu_entries(name, x)
        end, entry.submenus)
    else
      -- if we reached a leaf
      return name
    end
  end

  local entries = utils.tbl_flatten(vim.tbl_map(
    function(x)
      return gen_menu_entries(nil, x)
    end, vim.fn.menu_get("")))

  if utils.tbl_isempty(entries) then
    utils.info("No menus available")
    return
  end

  core.fzf_exec(entries, opts)
end

M.autocmds = function(opts)
  opts = config.normalize_opts(opts, "autocmds")
  if not opts then return end

  local autocmds = vim.api.nvim_get_autocmds({})
  if not autocmds or utils.tbl_isempty(autocmds) then
    return
  end

  local contents = function(cb)
    coroutine.wrap(function()
      local co = coroutine.running()
      for _, a in ipairs(autocmds) do
        local file, line = "<none>", 0
        if a.callback then
          local info = debug.getinfo(a.callback, "S")
          file = info and info.source and info.source:sub(2) or ""
          line = info and info.linedefined or 0
        end
        local group = a.group_name and vim.trim(a.group_name) or " "
        local entry = string.format("%s:%d:|%-28s │ %-34s │ %-18s │ %s",
          file, line,
          utils.ansi_codes.yellow(a.event),
          utils.ansi_codes.blue(group),
          a.pattern,
          a.callback and utils.ansi_codes.red(tostring(a.callback)) or a.command)
        cb(entry, function(err)
          coroutine.resume(co)
          if err then cb(nil) end
        end)
        coroutine.yield()
      end
      cb(nil)
    end)()
  end

  return core.fzf_exec(contents, opts)
end

return M
