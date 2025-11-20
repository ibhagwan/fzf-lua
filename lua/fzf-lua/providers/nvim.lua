local uv = vim.uv or vim.loop
local core = require "fzf-lua.core"
local path = require "fzf-lua.path"
local utils = require "fzf-lua.utils"
local config = require "fzf-lua.config"
local devicons = require "fzf-lua.devicons"

local M = {}

M.commands = function(opts)
  ---@type fzf-lua.config.Commands
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
          if line:match("^%s+%S") then
            local desc_continue = line:match("^%s*(.*%S)")
            desc = desc .. (desc_continue and " " .. desc_continue or "")
          end
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

  local add_subcommand = function(k, ansi_color)
    local flattened = vim.is_callable(opts.flatten[k]) and opts.flatten[k](opts)
        or opts.flatten[k] and vim.fn.getcompletion(k .. " ", "cmdline")
        or {}
    vim.list_extend(entries,
      vim.tbl_map(function(cmd) return ansi_color(k .. " " .. cmd) end,
        flattened))
  end

  opts.flatten = opts.flatten or {}
  for k, _ in pairs(global_commands) do
    table.insert(entries, utils.ansi_codes[opts.hls.cmd_global](k))
    add_subcommand(k, utils.ansi_codes[opts.hls.cmd_global])
  end

  for k, v in pairs(buf_commands) do
    if type(v) == "table" then
      table.insert(entries, utils.ansi_codes[opts.hls.cmd_buf](k))
      add_subcommand(k, utils.ansi_codes[opts.hls.cmd_buf])
    end
  end

  -- Sort before adding "builtin" so they don't end up atop the list
  if not opts.sort_lastused then
    table.sort(entries, function(a, b) return a < b end)
  end

  for k, _ in pairs(builtin_commands) do
    table.insert(entries, utils.ansi_codes[opts.hls.cmd_ex](k))
  end

  opts.preview = function(args)
    local cmd = args[1]
    if commands[cmd] then
      cmd = vim.inspect(commands[cmd])
    end
    return cmd
  end

  return core.fzf_exec(entries, opts)
end

---@param opts table
---@param str ":"|"/"
local history = function(opts, str)
  local histnr          = vim.fn.histnr(str)
  local dr              = opts.reverse_list and 1 or -1
  local bulk            = 500
  local from, to, delta = dr, dr * histnr, dr * bulk
  local content         = coroutine.wrap(function(cb)
    local co = coroutine.running()
    for i = from, to, delta do
      vim.schedule(function()
        local count = bulk
        for j = 0, delta - dr, dr do
          local index = i + j
          if dr > 0 and index <= to or dr < 0 and index >= to then
            cb(vim.fn.histget(str, index), function()
              count = count - 1
              if count == 0 or index == to then
                coroutine.resume(co)
              end
            end)
          end
        end
      end)
      coroutine.yield()
    end
    cb(nil)
  end)
  core.fzf_exec(content, opts)
end

M.command_history = function(opts)
  ---@type fzf-lua.config.CommandHistory
  opts = config.normalize_opts(opts, "command_history")
  if not opts then return end
  history(opts, ":")
end

M.search_history = function(opts)
  ---@type fzf-lua.config.SearchHistory
  opts = config.normalize_opts(opts, "search_history")
  if not opts then return end
  history(opts, "/")
end

M.changes = function(opts)
  ---@type fzf-lua.config.Changes
  opts = config.normalize_opts(opts, "changes")
  if not opts then return end
  return M.changes_or_jumps(opts)
end

M.jumps = function(opts)
  ---@type fzf-lua.config.Jumps
  opts = config.normalize_opts(opts, "jumps")
  if not opts then return end
  return M.changes_or_jumps(opts)
end

M.changes_or_jumps = function(opts)
  local jumps = vim.split(vim.fn.execute(opts.cmd), "\n")

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

  return core.fzf_exec(entries, opts)
end

M.tagstack = function(opts)
  ---@type fzf-lua.config.Tagstack
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

  return core.fzf_exec(entries, opts)
end


M.marks = function(opts)
  ---@type fzf-lua.config.Marks
  opts = config.normalize_opts(opts, "marks")
  if not opts then return end

  local contents = function(cb)
    local buf = utils.CTX().bufnr
    local entries = {}
    local function add_mark(mark, line, col, text)
      if opts.marks and not string.match(mark, opts.marks) then return end
      table.insert(entries, string.format("%s  %s  %s %s",
        utils.ansi_codes[opts.hls.buf_nr](string.format("%4s", mark)),
        utils.ansi_codes[opts.hls.path_linenr](string.format("%4s", tostring(line))),
        utils.ansi_codes[opts.hls.path_colnr](string.format("%3s", tostring(col))),
        text))
    end

    -- local buffer marks
    for _, m in ipairs(vim.fn.getmarklist(buf)) do
      local mark, lnum, col = m.mark:sub(2, 2), m.pos[2], m.pos[3]
      local text = vim.api.nvim_buf_get_lines(buf, lnum - 1, lnum, false)[1]
      add_mark(mark, lnum, col, utils.ansi_from_hl("Directory", text or "-invalid-"))
    end

    -- global marks
    for _, m in ipairs(vim.fn.getmarklist()) do
      local mark, bufnr, lnum, col, file = m.mark:sub(2, 2), m.pos[1], m.pos[2], m.pos[3], m.file
      file = path.relative_to(file, uv.cwd())
      if path.is_absolute(file) then
        file = path.HOME_to_tilde(file)
      end
      if bufnr == utils.CTX().bufnr then
        local text = vim.api.nvim_buf_get_lines(bufnr, lnum - 1, lnum, false)[1]
        add_mark(mark, lnum, col, utils.ansi_from_hl("Directory", text or "-invalid-"))
      else
        add_mark(mark, lnum, col, file or "-invalid-")
      end
    end

    if opts.sort then
      table.sort(entries, function(a, b) return a < b end)
    end
    table.insert(entries, 1,
      string.format("%-5s %s  %s %s", "mark", "line", "col", "file/text"))

    vim.tbl_map(cb, entries)
    cb(nil)
  end

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

  return core.fzf_exec(contents, opts)
end

M.registers = function(opts)
  ---@type fzf-lua.config.Registers
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

  if type(opts.filter) == "string" or type(opts.filter) == "function" then
    local filter = type(opts.filter) == "function" and opts.filter
        or function(r)
          return r:match(opts.filter) ~= nil
        end
    registers = vim.tbl_filter(filter, registers)
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
      local regtype = vim.fn.getregtype(r)
      local function convert_regtype(t)
        local first = string.sub(t, 1, 1)
        if first == "v" then
          return "c"
        elseif first == "V" then
          return "l"
        elseif first == "\22" then
          return "b" .. string.sub(t, 2)
        else
          return t
        end
      end

      local reg_fmt = require("fzf-lua.utils").ansi_codes.yellow(r)
      local regtype_fmt = require("fzf-lua.utils").ansi_codes.blue(convert_regtype(regtype))
      entries[#entries + 1] = string.format("[%s] [%s] %s", reg_fmt, regtype_fmt, contents)
    end
  end

  opts.preview = function(args)
    local r = args[1]:match("%[(.*)%] ")
    local _, contents = pcall(vim.fn.getreg, r)
    return contents and register_escape_special(contents) or args[1]
  end

  return core.fzf_exec(entries, opts)
end

M.keymaps = function(opts)
  ---@type fzf-lua.config.Keymaps
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
    info.desc = field_fmt.rhs and string.sub(info.desc or "", 1, 33) or info.desc
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

  return core.fzf_exec(entries, opts)
end

M.nvim_options = function(opts)
  ---@type fzf-lua.config.NvimOptions
  opts = config.normalize_opts(opts, "nvim_options")
  if not opts then return end

  local format_str = function(info)
    local fields = { "option", "value" }
    local field_fmt = { option = "%-20s", value = "%s" }
    local ret

    for _, f in ipairs(fields) do
      if field_fmt[f] then
        ret = string.format(
          "%s%s" .. field_fmt[f],
          ret or "",
          ret and string.format(" %s ", utils.ansi_codes["grey"](opts.separator))
          or " ",
          info[f] or ""
        )
      end
    end
    return ret
  end

  local format_option_entries = function()
    local entries = {}
    for _, v in pairs(vim.api.nvim_get_all_options_info()) do
      local ok, value = pcall(vim.api.nvim_get_option_value, v.name, {})

      if ok then
        local color_value = utils.ansi_codes["grey"](tostring(value))
        if value == true and opts.color_values then
          color_value = utils.ansi_codes["green"](tostring(value))
        elseif value == false and opts.color_values then
          color_value = utils.ansi_codes["red"](tostring(value))
        end

        local str = format_str({ option = v.name, value = color_value })
        table.insert(entries, str)
      end
    end

    table.sort(entries)
    local header = format_str({ option = "Option", value = "Value" })
    local keymaps = (":: %s %s, %s %s"):format(
      utils.ansi_from_hl(opts.hls.header_bind, "<enter>"),
      utils.ansi_from_hl(opts.hls.header_text, "local scope"),
      utils.ansi_from_hl(opts.hls.header_bind, "<alt-enter>"),
      utils.ansi_from_hl(opts.hls.header_text, "global scope"))
    table.insert(entries, 1, keymaps)
    table.insert(entries, 2, header)
    return entries
  end

  local contents = function(cb)
    vim.api.nvim_win_call(opts.__CTX.winid, function()
      coroutine.wrap(function()
        local co = coroutine.running()
        local entries = format_option_entries()
        for _, entry in pairs(entries) do
          vim.schedule(function()
            cb(entry, function()
              coroutine.resume(co)
            end)
          end)
          coroutine.yield()
        end
        cb()
      end)()
    end)
  end

  opts.fzf_opts["--header-lines"] = "2"

  return core.fzf_exec(contents, opts)
end

M.spell_suggest = function(opts)
  ---@type fzf-lua.config.SpellSuggest
  opts = config.normalize_opts(opts, "spell_suggest")
  if not opts then return end

  local match = opts.word_pattern or "[^%s\"'%(%)%.%%%+%-%*%?%[%]%^%$:#,]*"
  local line = vim.api.nvim_get_current_line()
  local col = vim.api.nvim_win_get_cursor(0)[2] + 1
  local before = col > 1 and line:sub(1, col - 1):reverse():match(match):reverse() or ""
  local after = line:sub(col):match(match) or ""
  -- special case when the cursor is on the left surrounding char
  if #before == 0 and #after == 0 and #line > col then
    col = col + 1
    after = line:sub(col):match(match) or ""
  end

  local cursor_word = before .. after
  local entries = vim.fn.spellsuggest(cursor_word)

  opts.complete = function(selected, _o, l, _)
    if #selected == 0 then return end
    local replace_at = col - #before
    local before_path = replace_at > 1 and l:sub(1, replace_at - 1) or ""
    local rest_of_line = #l >= (col + #after) and l:sub(col + #after) or ""
    return before_path .. selected[1] .. rest_of_line,
        -- this goes to `nvim_win_set_cursor` which is 0-based
        replace_at + #selected[1] - 2
  end

  if utils.tbl_isempty(entries) then return end

  return core.fzf_exec(entries, opts)
end

M.filetypes = function(opts)
  ---@type fzf-lua.config.Filetypes
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

  return core.fzf_exec(entries, opts)
end

M.packadd = function(opts)
  ---@type fzf-lua.config.Packadd
  opts = config.normalize_opts(opts, "packadd")
  if not opts then return end

  local entries = vim.fn.getcompletion("", "packadd")
  if utils.tbl_isempty(entries) then return end

  return core.fzf_exec(entries, opts)
end

M.menus = function(opts)
  ---@type fzf-lua.config.Menus
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

  return core.fzf_exec(entries, opts)
end

M.autocmds = function(opts)
  ---@type fzf-lua.config.Autocmds
  opts = config.normalize_opts(opts, "autocmds")
  if not opts then return end

  local autocmds = vim.api.nvim_get_autocmds({})
  if not autocmds or utils.tbl_isempty(autocmds) then
    return
  end

  local separator = "│"
  local fields = { "event", "pattern", "group", "code", "desc" }
  local field_fmt = {
    event = "%-28s",
    pattern = "%-22s",
    group = "%-40s",
    code = "%-44s",
    desc = "%s",
  }

  if opts.show_desc == false then field_fmt.desc = nil end

  local format = function(info)
    local ret
    for _, f in ipairs(fields) do
      if field_fmt[f] then
        local fmt = field_fmt[f]
        if info.color == false then
          local len = tonumber(fmt:match("%d+"))
          if len then
            fmt = fmt:gsub("%d+", tostring(len - 11))
          end
        end
        ret = string.format("%s%s" .. fmt, ret or "",
          ret and string.format(" %s ", separator) or "", info[f] or "")
      end
    end
    return ret
  end

  local contents = function(cb)
    coroutine.wrap(function()
      local co = coroutine.running()
      cb(string.format("%s:%d:%s%s", "<none>", 0, separator, format({
        event = "event",
        pattern = "pattern",
        group = "group",
        code = "code",
        desc = "description",
        color = false,
      })), function(err)
        coroutine.resume(co)
        if err then cb(nil) end
      end)
      for _, a in ipairs(autocmds) do
        local file, line = "<none>", 0
        if a.callback then
          local info = debug.getinfo(a.callback, "S")
          file = info and info.source and info.source:sub(2) or ""
          line = info and info.linedefined or 0
        end
        local entry = string.format("%s:%d:%s%s", file, line, separator, format({
          event = utils.ansi_codes.blue(a.event),
          pattern = utils.ansi_codes.yellow(a.pattern),
          group = utils.ansi_codes.green(a.group_name and vim.trim(tostring(a.group_name)) or " "),
          code = a.callback and utils.ansi_codes.red(tostring(a.callback)) or a.command,
          desc = a.desc,
        }))
        cb(entry, function(err)
          coroutine.resume(co)
          if err then cb(nil) end
        end)
        coroutine.yield()
      end
      cb(nil)
    end)()
  end

  opts.fzf_opts["--header-lines"] = "1"
  return core.fzf_exec(contents, opts)
end

return M
