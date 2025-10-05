local uv = vim.uv or vim.loop
local utils = require "fzf-lua.utils"
local path = require "fzf-lua.path"
local libuv = require "fzf-lua.libuv"

local M = {}

-- return fzf '--expect=' string from actions keyval tbl
-- on fzf >= 0.53 add the `prefix` key to the bind flags
-- https://github.com/junegunn/fzf/issues/3829#issuecomment-2143235993
M.expect = function(actions, opts)
  if not actions then return nil end
  local expect = {}
  local binds = {}
  for k, v in pairs(actions) do
    -- actions that starts with _underscore are internal ashouldn't be set as fzf binds
    -- the user can then use a custom bind and map it to the _underscore action using:
    --   keymap = { fzf = { ["backward-eof"] = "print(_myaction)+accept" } },
    --   actions = { ["_myaction"] = function(sel, opts) ... end,
    (function()
      -- Lua 5.1 goto compatiblity hack (function wrap)
      -- Ignore `false` actions and execute-silent/reload actions
      if not v or type(v) == "table" and v._ignore or k:match("^_") then return end
      k = k == "default" and "enter" or k
      v = type(v) == "table" and v or { fn = v }
      if utils.has(opts, "fzf", { 0, 53 }) then
        -- `print(...)` action was only added with fzf 0.53
        -- NOTE: we can no longer combine `--expect` and `--bind` as this will
        -- print an extra empty line regardless of the pressaed keybind (#1241)
        table.insert(binds, string.format("%s:print(%s)%s%s+accept",
          k,
          k,
          v.prefix and "+" or "",
          v.prefix and v.prefix:gsub("accept$", ""):gsub("%+$", "") or ""
        ))
      elseif utils.has(opts, "sk", { 0, 14 }) then
        -- sk 0.14 deprecated `--expect`, instead `accept(<key>)` should be used
        -- skim does not yet support case sensitive alt-shift binds, they are ignored
        -- if k:match("^alt%-%u") then return end
        if type(v.prefix) == "string" and not v.prefix:match("%+$") then
          v.prefix = v.prefix .. "+"
        end
        table.insert(binds, string.format("%s:%saccept(%s)", k, v.prefix or "", k))
      elseif k ~= "enter" then
        -- Skim does not support case sensitive alt-shift binds
        -- which are supported with fzf since version 0.25
        if not opts._is_skim or not k:match("^alt%-%u") then
          table.insert(expect, k)
        end
      end
    end)()
  end
  return #expect > 0 and expect or nil, #binds > 0 and binds or nil
end

M.normalize_selected = function(selected, opts)
  -- The below separates the keybind from the item(s)
  -- and makes sure 'selected' contains only item(s) or {}
  -- so it can always be enumerated safely
  if not selected then return end
  local actions = opts.actions
  -- Backward compat, "default" action trumps "enter"
  if actions.default then actions.enter = actions.default end
  if utils.has(opts, "fzf", { 0, 53 }) or utils.has(opts, "sk", { 0, 14 }) then
    -- Using the new `print` action keybind is expected at `selected[1]`
    -- NOTE: if `--select-1|-q` was used we'll be missing the keybind
    -- since `-1` triggers "accept" assume "enter" (#1589)
    -- NOTE2: pressing a bind when no results are present also meets
    -- the condtion `#selected ==1` so make sure `selected[1]` is not
    -- an action (e.g. pressing `esc` when no results, #1594)
    if selected and #selected == 1 and not actions[selected[1]] then
      table.insert(selected, 1, "enter")
    end
    local entries = vim.deepcopy(selected)
    local keybind = table.remove(entries, 1)
    return keybind, entries
  else
    -- 1. If there are no additional actions but the default,
    --    the selected table will contain the selected item(s)
    -- 2. If at least one non-default action was defined, our 'expect'
    --    function above sent fzf the '--expect` flag, from `man fzf`:
    --      When this option is set, fzf will print the name of the key pressed as the
    --      first line of its output (or as the second line if --print-query is also used).
    if utils.tbl_count(actions) > 1 or not actions.enter then
      -- After removal of query (due to `--print-query`), keybind should be in item #1
      -- when `--expect` is present, default (enter) keybind prints an empty string
      local entries = vim.deepcopy(selected)
      local keybind = table.remove(entries, 1)
      if #keybind == 0 then keybind = "enter" end
      return keybind, entries
    else
      -- Only default (enter) action exists, no `--expect` was specified
      -- therefore enter was pressed and no empty line in `selected[1]`
      return "enter", selected
    end
  end
end

M.act = function(selected, opts)
  if not selected then return end
  local actions = opts.actions
  local keybind, entries = M.normalize_selected(selected, opts)
  -- fzf >= 0.53 and `--exit-0`
  if not keybind then return end
  local action = actions[keybind]
  -- Backward compat, was action defined as "default"
  if not action and keybind == "enter" then
    action = actions.default
  end
  if type(action) == "table" then
    -- Two types of action as table:
    --   (1) map containing action properties (reload, noclose, etc)
    --   (2) array of actions to be executed serially
    if action.fn then
      action.fn(entries, opts)
    else
      for _, f in ipairs(action) do
        f(entries, opts)
      end
    end
  elseif type(action) == "function" then
    action(entries, opts)
  elseif type(action) == "string" then
    vim.cmd(action)
  else
    utils.warn(("unsupported action: '%s', type:%s"):format(keybind, type(action)))
  end
end

-- Dummy abort action for `esc|ctrl-c|ctrl-q`
M.dummy_abort = function(_, o)
  -- try to resume mode if `complete` is set
  if o.complete and o.__CTX.mode == "i" then
    vim.cmd [[noautocmd lua vim.api.nvim_feedkeys('i', 'n', true)]]
  end
end

M.resume = function(_, _)
  require("fzf-lua").resume()
end

local edit_entry = function(entry, fullpath, will_replace_curbuf, opts)
  local curbuf = vim.api.nvim_win_get_buf(0)
  local curbname = vim.api.nvim_buf_get_name(curbuf)
  if entry.bufnr == curbuf or path.equals(curbname, fullpath) then
    -- requested buffer already loaded in the current window (split?)
    return true
  end
  local bufnr = entry.bufnr or (function()
    -- Always open files relative to the current win/tab cwd (#1854)
    -- We normalize the path or Windows will fail with directories starting
    -- with special characters, for example "C:\app\(web)" will be translated
    -- by neovim to "c:\app(web)" (#1082)
    local relpath = path.normalize(path.relative_to(fullpath, uv.cwd()))
    local bufnr = vim.fn.bufadd(relpath)
    if bufnr == 0 and not opts.silent then
      utils.warn("Unable to add buffer %s", relpath)
      return
    end
    vim.bo[bufnr].buflisted = true
    return bufnr
  end)()
  -- abort if we're unable to load the buffer
  if not tonumber(bufnr) then return end
  -- wipe unnamed empty buffers (e.g. "new") on switch
  if will_replace_curbuf
      and vim.bo.buftype == ""
      and vim.bo.filetype == ""
      and vim.api.nvim_buf_line_count(0) == 1
      and vim.api.nvim_buf_get_lines(0, 0, -1, false)[1] == ""
      and vim.api.nvim_buf_get_name(0) == ""
  then
    vim.bo.bufhidden = "wipe"
  end
  -- NOTE: nvim_set_current_buf will load the buffer if needed
  -- calling bufload will mess up `BufReadPost` autocmds
  -- vim.fn.bufload(bufnr)
  local ok, _ = pcall(vim.api.nvim_set_current_buf, bufnr)
  -- When `:set nohidden && set confirm`, neovim will invoke the save dialog
  -- and confirm with the user when trying to switch from a dirty buffer, if
  -- user cancelles the save dialog pcall will fail with:
  -- Vim:E37: No write since last change (add ! to override)
  if not ok then return end
  return true
end

---@param vimcmd string
---@param selected string[]
---@param opts fzf-lua.Config
---@param bufedit boolean?
---@return string?
M.vimcmd_entry = function(vimcmd, selected, opts, bufedit)
  for i, sel in ipairs(selected) do
    (function()
      -- Lua 5.1 goto compatiblity hack (function wrap)
      local entry = path.entry_to_file(sel, opts, opts._uri)
      -- "<none>" could be set by `autocmds`
      if entry.path == "<none>" then return end
      local fullpath = entry.bufname
          or entry.uri and entry.uri:match("^[%a%-]+://(.*)")
          or entry.path
      -- Something is not right, goto next entry
      if not fullpath then return end
      if not path.is_absolute(fullpath) then
        -- cwd priority is first user supplied, then original call cwd
        -- technically we should never get to the `uv.cwd()` fallback
        fullpath = path.join({ opts.cwd or opts._cwd or uv.cwd(), fullpath })
      end
      -- Can't be called from term window (for example, "reload" actions) due to
      -- nvim_exec2(): Vim(normal):Can't re-enter normal mode from terminal mode
      -- NOTE: we do not use `opts.__CTX.bufnr` as caller might be the fzf term
      if not utils.is_term_buffer(0) then
        vim.cmd("normal! m`")
      end
      if bufedit then
        local will_replace_curbuf = (function()
          if #vimcmd > 0 then return false end
          local curbuf = vim.api.nvim_win_get_buf(0)
          local curbname = vim.api.nvim_buf_get_name(curbuf)
          if entry.bufnr == curbuf or path.equals(curbname, fullpath) then
            -- requested buffer already loaded in the current window (split?)
            return false
          end
          return true
        end)()
        if will_replace_curbuf then
          if utils.wo.winfixbuf then
            utils.warn("'winfixbuf' is set for current window, will open in a split.")
            vimcmd, will_replace_curbuf = "split", false
          elseif not vim.o.hidden
              and not vim.o.confirm
              and utils.buffer_is_dirty(vim.api.nvim_get_current_buf(), true) then
            return
          end
        end
        if #vimcmd > 0 then vim.cmd(vimcmd) end
        -- NOTE: URI entries only execute new buffers (new|vnew|tabnew)
        -- and later use `utils.jump_to_location` to load the buffer
        if not entry.uri and not edit_entry(entry, fullpath, will_replace_curbuf, opts) then
          -- error loading buffer or save dialog cancelled
          return
        end
      else
        local relpath = path.normalize(path.relative_to(fullpath, uv.cwd()))
        vim.cmd(("%s %s"):format(vimcmd, relpath))
      end
      -- Reload actions from fzf's (buf/arg del, etc) window end here
      if utils.is_term_buffer(0) and vim.bo.ft == "fzf" then
        return
      end
      -- Java LSP entries, 'jdt://...' or LSP locations
      if entry.uri then
        -- pcall for two failed cases
        -- (1) nvim_exec2(): Vim(normal):Can't re-enter normal mode from terminal mode
        -- (2) save dialog cancellation
        pcall(utils.jump_to_location, entry, "utf-16", opts.reuse_win)
      elseif entry.ctag and entry.line == 0 then
        vim.api.nvim_win_set_cursor(0, { 1, 0 })
        vim.fn.search(entry.ctag, "W")
      elseif not opts.no_action_set_cursor and entry.line > 0 or entry.col > 0 then
        -- Make sure we have valid line/column
        -- e.g. qf lists from files (no line/col), dap_breakpoints
        pcall(vim.api.nvim_win_set_cursor, 0, {
          math.max(1, entry.line),
          math.max(1, entry.col) - 1
        })
      end
      -- Only "zz" after the last entry is loaded into the origin buffer
      if i == #selected and not opts.no_action_zz and not utils.is_term_buffer(0) then
        vim.cmd("norm! zvzz")
      end
    end)()
  end
end

-- file actions
M.file_edit = function(selected, opts)
  M.vimcmd_entry("", selected, opts, true)
end

M.file_split = function(selected, opts)
  M.vimcmd_entry("split", selected, opts, true)
end

M.file_vsplit = function(selected, opts)
  M.vimcmd_entry("vsplit", selected, opts, true)
end

M.file_tabedit = function(selected, opts)
  -- local vimcmd = "tab split | <auto>"
  M.vimcmd_entry("tabnew | setlocal bufhidden=wipe", selected, opts, true)
end

M.file_open_in_background = function(selected, opts)
  M.vimcmd_entry("badd", selected, opts)
end

local sel_to_qf = function(selected, opts, is_loclist)
  local qf_list = {}
  for i = 1, #selected do
    local file = path.entry_to_file(selected[i], opts)
    local text = file.stripped:match(":%d+:%d?%d?%d?%d?:?(.*)$")
    table.insert(qf_list, {
      bufnr = file.bufnr,
      filename = file.bufname or file.path or file.uri,
      lnum = file.line > 0 and file.line or 1,
      col = file.col,
      text = text,
    })
  end
  table.sort(qf_list, function(a, b)
    if a.filename == b.filename then
      if a.lnum == b.lnum then
        return math.max(0, a.col) < math.max(0, b.col)
      else
        return math.max(0, a.lnum) < math.max(0, b.lnum)
      end
    else
      return a.filename < b.filename
    end
  end)

  local cmd = utils.get_info().cmd
  local title = string.format("[FzfLua] %s%s", cmd and cmd .. ": " or "",
    utils.resume_get("query", opts) or "")
  if is_loclist then
    vim.fn.setloclist(0, {}, " ", {
      nr = "$",
      items = qf_list,
      title = title,
    })
    if type(opts.lopen) == "function" then
      opts.lopen(selected, opts)
    elseif opts.lopen ~= false then
      vim.cmd(opts.lopen or "botright lopen")
    end
  else
    -- Set the quickfix title to last query and
    -- append a new list to end of the stack (#635)
    vim.fn.setqflist({}, " ", { ---@diagnostic disable-next-line: assign-type-mismatch
      nr = "$",
      items = qf_list,
      title = title,
      -- nr = nr,
    })
    if type(opts.copen) == "function" then
      opts.copen(selected, opts)
    elseif opts.copen ~= false then
      vim.cmd(opts.copen or "botright copen")
    end
  end
end

M.list_del = function(selected, opts)
  local winid = opts.__CTX.winid
  local list = opts.is_loclist and vim.fn.getloclist(winid) or vim.fn.getqflist()

  local buf_del = (function()
    local ret = {}
    for _, s in ipairs(selected) do
      local b = s:match("%[(%d+)%]")
      ret[b] = true
    end
    return ret
  end)()

  local newlist = {}
  for _, l in ipairs(list) do
    if not buf_del[tostring(l.bufnr)] then
      table.insert(newlist, l)
    end
  end

  if opts.is_loclist then
    vim.fn.setloclist(winid, newlist, "r")
  else
    vim.fn.setqflist(newlist, "r")
  end
end

M.file_sel_to_qf = function(selected, opts)
  sel_to_qf(selected, opts)
end

M.file_sel_to_ll = function(selected, opts)
  sel_to_qf(selected, opts, true)
end

M.file_edit_or_qf = function(selected, opts)
  if #selected > 1 then
    return M.file_sel_to_qf(selected, opts)
  else
    return M.file_edit(selected, opts)
  end
end

M.file_switch = function(selected, opts)
  if not selected[1] then return false end
  -- If called from `:FzfLua tabs` switch to requested tab/win
  local tabh, winid = selected[1]:match("(%d+)\t(%d+)%)")
  if tabh and winid then
    vim.api.nvim_set_current_tabpage(tonumber(tabh))
    if tonumber(winid) > 0 then
      vim.api.nvim_set_current_win(tonumber(winid))
    end
    return true
  end
  local entry = path.entry_to_file(selected[1], opts)
  if not entry.bufnr then
    -- Search for the current entry's filepath in buffer list
    local fullpath = entry.path
    if not path.is_absolute(fullpath) then
      fullpath = path.join({ opts.cwd or uv.cwd(), fullpath })
    end
    for _, b in ipairs(vim.api.nvim_list_bufs()) do
      local bname = vim.api.nvim_buf_get_name(b)
      if bname == fullpath then
        entry.bufnr = b
        break
      end
    end
  end
  -- Entry isn't an existing buffer, abort
  if not entry.bufnr then return false end
  if not utils.is_term_buffer(0) then vim.cmd("normal! m`") end
  winid = utils.winid_from_tabh(0, entry.bufnr)
  if not winid then return false end
  vim.api.nvim_set_current_win(winid)
  if entry.line > 0 or entry.col > 0 then
    pcall(vim.api.nvim_win_set_cursor, 0, {
      math.max(1, entry.line),
      math.max(1, entry.col) - 1
    })
  end
  if not utils.is_term_buffer(0) and not opts.no_action_zz then vim.cmd("norm! zvzz") end
  return true
end

M.file_switch_or_edit = function(selected, opts)
  if not M.file_switch({ selected[1] }, opts) then
    M.file_edit({ selected[1] }, opts)
  end
end

M.buf_edit = M.file_edit
M.buf_split = M.file_split
M.buf_vsplit = M.file_vsplit
M.buf_tabedit = M.file_tabedit
M.buf_sel_to_qf = M.file_sel_to_qf
M.buf_sel_to_ll = M.file_sel_to_ll
M.buf_edit_or_qf = M.file_edit_or_qf
M.buf_switch = M.file_switch
M.buf_switch_or_edit = M.file_switch_or_edit

M.buf_del = function(selected, opts)
  for _, sel in ipairs(selected) do
    local entry = path.entry_to_file(sel, opts)
    if entry.bufnr then
      if not utils.buffer_is_dirty(entry.bufnr, true, false)
          or vim.api.nvim_buf_call(entry.bufnr, function()
            return utils.save_dialog(entry.bufnr)
          end)
      then
        vim.api.nvim_buf_delete(entry.bufnr, { force = true })
      end
    end
  end
end

local function arg_exec(cmd, selected, opts)
  for _, sel in ipairs(selected) do
    (function()
      local entry = path.entry_to_file(sel, opts)
      local relpath = entry.bufname or entry.path
      assert(relpath, "entry doesn't contain filepath")
      if not relpath then return end
      if path.is_absolute(relpath) then
        relpath = path.relative_to(relpath, vim.uv.cwd())
      end
      vim.cmd(cmd .. " " .. relpath)
    end)()
  end
end

M.arg_add = function(selected, opts)
  arg_exec("argadd", selected, opts)
  ---@diagnostic disable-next-line: param-type-mismatch
  pcall(vim.cmd, "argdedupe")
end

M.arg_del = function(selected, opts)
  arg_exec("argdel", selected, opts)
end

M.colorscheme = function(selected, opts)
  if #selected == 0 then return end
  local dbkey, idx = selected[1]:match("^(.-):(%d+):")
  if dbkey then
    opts._apply_awesome_theme(dbkey, idx, opts)
  else
    local colorscheme = selected[1]:match("^[^:]+")
    pcall(function() vim.cmd("colorscheme " .. colorscheme) end)
  end
end

M.cs_delete = function(selected, opts)
  for _, s in ipairs(selected) do
    local dbkey = s:match("^(.-):%d+:")
    opts._adm:delete(dbkey)
  end
end

M.cs_update = function(selected, opts)
  local dedup = {}
  for _, s in ipairs(selected) do
    local dbkey = s:match("^(.-):%d+:")
    if dbkey then dedup[dbkey] = true end
  end
  for k, _ in pairs(dedup) do
    opts._adm:update(k)
  end
end

M.toggle_bg = function(_, _)
  vim.o.background = vim.o.background == "dark" and "light" or "dark"
  utils.setup_highlights()
  utils.info([[background set to '%s']], vim.o.background)
end

M.hi = function(selected)
  if #selected == 0 then return end
  vim.cmd("hi " .. selected[1])
  vim.cmd("echo")
end

M.run_builtin = function(selected)
  if #selected == 0 then return end
  local method = selected[1]
  pcall(require "fzf-lua"[method])
end

M.ex_run = function(selected)
  if #selected == 0 then return end
  local cmd = selected[1]
  vim.cmd("stopinsert")
  vim.fn.feedkeys(string.format(":%s", cmd), "nt")
  return cmd
end

M.ex_run_cr = function(selected)
  if #selected == 0 then return end
  local cmd = selected[1]
  vim.cmd(cmd)
  vim.fn.histadd("cmd", cmd)
end

M.exec_menu = function(selected)
  if #selected == 0 then return end
  local cmd = selected[1]
  vim.cmd("emenu " .. cmd)
end


M.search = function(selected, opts)
  if #selected == 0 then return end
  local query = selected[1]
  vim.cmd("stopinsert")
  vim.fn.feedkeys(
    string.format("%s%s", opts.reverse_search and "?" or "/", query), "n")
  return query
end

M.search_cr = function(selected, opts)
  M.search(selected, opts)
  utils.feed_keys_termcodes("<CR>")
end

M.goto_mark = function(selected)
  if #selected == 0 then return end
  local mark = selected[1]
  mark = mark:match("[^ ]+")
  vim.cmd("stopinsert")
  vim.cmd("normal! `" .. mark)
  -- vim.fn.feedkeys(string.format("'%s", mark))
end

M.goto_mark_tabedit = function(selected)
  vim.cmd("tab split")
  M.goto_mark(selected)
end

M.goto_mark_split = function(selected)
  vim.cmd("split")
  M.goto_mark(selected)
end

M.goto_mark_vsplit = function(selected)
  vim.cmd("vsplit")
  M.goto_mark(selected)
end

M.mark_del = function(selected)
  local win = utils.CTX().winid
  local buf = utils.CTX().bufnr
  vim.api.nvim_win_call(win, function()
    vim.tbl_map(function(s)
      local mark = s:match "[^ ]+"
      local ok, res = pcall(vim.api.nvim_buf_del_mark, buf, mark)
      if ok and res then return end
      return vim.cmd.delm(mark)
    end, selected)
  end)
end

M.goto_jump = function(selected, opts)
  if #selected == 0 then return end
  if opts.jump_using_norm then
    local jump, _, _, _ = selected[1]:match("(%d+)%s+(%d+)%s+(%d+)%s+(.*)")
    if tonumber(jump) then
      vim.cmd(("normal! %d"):format(jump))
    end
  else
    local _, lnum, col, filepath = selected[1]:match("(%d+)%s+(%d+)%s+(%d+)%s+(.*)")
    local ok, res = pcall(libuv.expand, filepath)
    if not ok then
      filepath = ""
    else
      filepath = res
    end
    if not filepath or not uv.fs_stat(filepath) then
      -- no accessible file
      -- jump is in current
      filepath = vim.api.nvim_buf_get_name(0)
    end
    local entry = ("%s:%d:%d:"):format(filepath, tonumber(lnum), tonumber(col) + 1)
    M.file_edit({ entry }, opts)
  end
end

M.keymap_apply = function(selected)
  if #selected == 0 then return end
  -- extract lhs in the keymap. The lhs can't contain a whitespace.
  local key = selected[1]:match("[│]%s+([^%s]*)%s+[│]")
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(key, true, false, true), "t", true)
end

for _, fname in ipairs({ "edit", "split", "vsplit", "tabedit" }) do
  M["keymap_" .. fname] = function(selected, opts)
    local entry = path.keymap_to_entry(selected[1], opts)
    if entry.path then
      M["file_" .. fname]({ entry.stripped }, opts)
    end
  end
end

local nvim_opt_edit = function(selected, opts, scope)
  local nvim_set_option = function(opt, val, info)
    local set_opts = {}
    if scope == "local" then
      if info.scope == "global" then
        utils.warn("Cannot set global option " .. opt .. " in local scope")
        return
      elseif info.scope == "win" then
        set_opts.win = opts.__CTX.winid
      elseif info.scope == "buf" then
        set_opts.buf = opts.__CTX.bufnr
      end
    elseif scope == "global" then
      if (info.scope == "win" or info.scope == "buf") and info.global_local ~= true then
        utils.warn("Cannot set local option " .. opt .. " in global scope")
        return
      end
    end

    local ok, err = pcall(vim.api.nvim_set_option_value, opt, val, set_opts)
    if not ok and err then utils.warn(err) end
  end

  local show_option_value_input = function(option, old, info)
    local updated = utils.input(
      (scope == "local" and ":setlocal " or ":set ") .. option .. "=", old)
    if not updated or updated == old then return end

    if info.type == "number" then
      nvim_set_option(option, tonumber(updated), info)
    else
      nvim_set_option(option, updated, info)
    end
  end

  local parts = vim.split(selected[1], opts.separator)
  local option = vim.trim(parts[1])
  local old = vim.trim(parts[2])
  local info = vim.api.nvim_get_option_info2(option, {})

  vim.api.nvim_win_call(opts.__CTX.winid, function()
    if info.type == "boolean" then
      local str2bool = { ["true"] = true, ["false"] = false }
      nvim_set_option(option, not str2bool[old], info)
    elseif info.type == "number" then
      show_option_value_input(option, tonumber(old), info)
    else
      show_option_value_input(option, old, info)
    end
  end)
end

M.nvim_opt_edit_local = function(selected, opts)
  return nvim_opt_edit(selected, opts, "local")
end

M.nvim_opt_edit_global = function(selected, opts)
  return nvim_opt_edit(selected, opts, "global")
end

M.spell_apply = function(selected, opts)
  if not selected[1] then return false end
  local word = selected[1]
  vim.cmd("normal! \"_ciw" .. word)
  if opts.__CTX.mode == "i" then
    vim.api.nvim_feedkeys("a", "n", true)
  end
end

M.spell_suggest = function(selected, opts)
  if not selected[1] then return false end
  M.file_edit(selected, opts)
  FzfLua.spell_suggest({ no_resume = true })
end

M.set_filetype = function(selected)
  vim.bo.filetype = selected[1]:match("[^" .. utils.nbsp .. "]+$")
end

M.packadd = function(selected)
  for i = 1, #selected do
    vim.cmd("packadd " .. selected[i])
  end
end

local function helptags(s, opts)
  return vim.tbl_map(function(x)
    local entry = path.entry_to_file(x, opts)
    if entry and entry.path and package.loaded.lazy then
      -- make sure the plugin is loaded. This won't do anything if already loaded
      local lazyConfig = require("lazy.core.config")
      local _, plugin = path.normalize(entry.path):match("(/([^/]+)/doc/)")
      if plugin and lazyConfig.plugins[plugin] then
        require("lazy").load({ plugins = { plugin } })
      end
    end
    return x:match("[^%s]+")
  end, s)
end

M.help = function(selected, opts)
  if #selected == 0 then return end
  vim.cmd("help " .. helptags(selected, opts)[1])
end

M.help_curwin = function(selected, opts)
  if #selected == 0 then return end
  local helpcmd
  local is_shown = false
  local current_win_number = 1
  local last_win_number = vim.fn.winnr("$")
  while current_win_number <= last_win_number do
    local buffer = vim.api.nvim_win_get_buf(vim.fn.win_getid(current_win_number))
    local type = vim.api.nvim_get_option_value("buftype", { buf = buffer })
    if type == "help" then
      is_shown = true
      break
    end
    current_win_number = current_win_number + 1
  end
  if is_shown then
    helpcmd = "help "
  else
    helpcmd = "enew | setlocal bufhidden=wipe | setlocal buftype=help | keepjumps help "
  end
  vim.cmd(helpcmd .. helptags(selected, opts)[1])
end

M.help_vert = function(selected, opts)
  if #selected == 0 then return end
  vim.cmd("vert help " .. helptags(selected, opts)[1])
end

M.help_tab = function(selected, opts)
  if #selected == 0 then return end
  -- vim.cmd("tab help " .. helptags(selected, opts)[1])
  utils.with({ go = { splitkeep = "cursor" } }, function()
    vim.cmd("tabnew | setlocal bufhidden=wipe | help " .. helptags(selected, opts)[1] .. " | only")
  end)
end

local function mantags(s)
  return vim.tbl_map(require("fzf-lua.providers.manpages").manpage_vim_arg, s)
end

M.man = function(selected)
  if #selected == 0 then return end
  vim.cmd("Man " .. mantags(selected)[1])
end

M.man_vert = function(selected)
  if #selected == 0 then return end
  vim.cmd("vert Man " .. mantags(selected)[1])
end

M.man_tab = function(selected)
  if #selected == 0 then return end
  utils.with({ go = { splitkeep = "cursor" } }, function()
    vim.cmd("tabnew | setlocal bufhidden=wipe | Man " .. mantags(selected)[1] .. " | only")
  end)
end

M.git_switch = function(selected, opts)
  if not selected[1] then return end
  local cmd = path.git_cwd({ "git", "checkout" }, opts)
  local git_ver = utils.git_version()
  -- git switch was added with git version 2.23
  if git_ver and git_ver >= 2.23 then
    cmd = path.git_cwd({ "git", "switch" }, opts)
  end
  -- remove anything past space
  local branch = selected[1]:match("[^ ]+")
  -- do nothing for active branch
  if branch:find("%*") ~= nil then return end
  if branch:find("^remotes/") then
    if opts.remotes == "detach" then
      table.insert(cmd, "--detach")
    else
      branch = branch:match("remotes/.-/(.-)$")
    end
  end
  table.insert(cmd, branch)
  local output, rc = utils.io_systemlist(cmd)
  if rc ~= 0 then
    utils.error(unpack(output))
  else
    utils.info(unpack(output))
    vim.cmd("checktime")
  end
end

M.git_branch_add = function(selected, opts)
  -- "reload" actions (fzf version >= 0.36) use field_index = "{q}"
  -- so the prompt input will be found in `selected[1]`
  -- previous fzf versions (or skim) restart the process instead
  -- so the prompt input will be found in `opts.last_query`
  local branch = opts.last_query or selected[1]
  if type(branch) ~= "string" or #branch == 0 then
    utils.warn("Branch name cannot be empty, use prompt for input.")
  else
    local cmd_add_branch = path.git_cwd(opts.cmd_add, opts)
    table.insert(cmd_add_branch, branch)
    local output, rc = utils.io_systemlist(cmd_add_branch)
    if rc ~= 0 then
      utils.error(unpack(output))
    else
      utils.info("Created branch '%s'.", branch)
    end
  end
end

M.git_branch_del = function(selected, opts)
  if #selected == 0 then return end
  local cmd_del_branch = path.git_cwd(opts.cmd_del, opts)
  local cmd_cur_branch = path.git_cwd({ "git", "rev-parse", "--abbrev-ref", "HEAD" }, opts)
  local branch = selected[1]:match("[^%s%*]+")
  local cur_branch = utils.io_systemlist(cmd_cur_branch)[1]
  if branch == cur_branch then
    utils.warn("Cannot delete active branch '%s'", branch)
    return
  end
  if vim.fn.confirm("Delete branch " .. branch .. "?", "&Yes\n&No") == 1 then
    table.insert(cmd_del_branch, branch)
    local output, rc = utils.io_systemlist(cmd_del_branch)
    if rc ~= 0 then
      utils.error(unpack(output))
    else
      utils.info(unpack(output))
    end
  end
end

M.git_worktree_cd = function(selected, opts)
  if not selected[1] then return end
  local cwd = selected[1]:match("^[^%s]+")
  if not path.is_absolute(cwd) then
    cwd = path.join({ uv.cwd(), cwd })
  end
  if cwd == vim.uv.cwd() then
    utils.warn(("cwd already set to '%s'"):format(cwd))
    return
  end
  if uv.fs_stat(cwd) then
    local cmd = (opts.scope == "local" or opts.scope == "win") and "lcd"
        or opts.scope == "tab" and "tcd" or "cd"
    vim.cmd(cmd .. " " .. cwd)
    utils.info(("cwd set to '%s'"):format(cwd))
  else
    utils.warn(("Unable to set cwd to '%s', directory is not accessible"):format(cwd))
  end
end

local match_commit_hash = function(line, opts)
  if type(opts.fn_match_commit_hash) == "function" then
    return opts.fn_match_commit_hash(line, opts)
  else
    return line:match("[^ ]+")
  end
end

M.git_yank_commit = function(selected, opts)
  if not selected[1] then return end
  local commit_hash = match_commit_hash(selected[1], opts)
  local regs, cb = {}, vim.o.clipboard
  if cb:match("unnamed") then regs[#regs + 1] = [[*]] end
  if cb:match("unnamedplus") then regs[#regs + 1] = [[+]] end
  if #regs == 0 then regs[#regs + 1] = [["]] end
  -- copy to the yank register regardless
  for _, reg in ipairs(regs) do
    vim.fn.setreg(reg, commit_hash)
  end
  vim.fn.setreg([[0]], commit_hash)
  utils.info({
    "commit hash ",
    { commit_hash, "DiagnosticVirtualLinesWarn" },
    " copied to register ",
    { regs[1],     "DiagnosticVirtualLinesHint" },
    ", use '",
    { "p", "DiagnosticVirtualLinesHint" },
    "' to paste.",
  })
end

M.git_checkout = function(selected, opts)
  local cmd_cur_commit = path.git_cwd({ "git", "rev-parse", "--short", "HEAD" }, opts)
  local commit_hash = match_commit_hash(selected[1], opts)
  local current_commit = utils.io_systemlist(cmd_cur_commit)[1]
  if commit_hash == current_commit then return end
  if vim.fn.confirm("Checkout commit " .. commit_hash .. "?", "&Yes\n&No") == 1 then
    local cmd_checkout = path.git_cwd({ "git", "checkout" }, opts)
    table.insert(cmd_checkout, commit_hash)
    local output, rc = utils.io_systemlist(cmd_checkout)
    if rc ~= 0 then
      utils.error(unpack(output))
    else
      utils.info(unpack(output))
      vim.cmd("checktime")
    end
  end
end

local git_exec = function(selected, opts, cmd, silent)
  local success
  for _, e in ipairs(selected) do
    local file = path.relative_to(path.entry_to_file(e, opts).path, opts.cwd)
    local _cmd = vim.deepcopy(cmd)
    table.insert(_cmd, file)
    local output, rc = utils.io_systemlist(_cmd)
    if rc ~= 0 and not silent then
      utils.error(unpack(output) or string.format("exit code %d", rc))
    end
    success = rc == 0
  end
  return success
end

M.git_stage = function(selected, opts)
  for _, s in ipairs(selected) do
    -- calling stage on an already deleted file will err:
    -- "fatal: pathspec '<file>' did not match any files
    -- string.byte("D", 1) = 68
    if string.byte(s, 1) ~= 68 then
      local cmd = path.git_cwd({ "git", "add", "--" }, opts)
      git_exec({ s }, opts, cmd)
    end
  end
end

M.git_unstage = function(selected, opts)
  local cmd = path.git_cwd({ "git", "reset", "--" }, opts)
  git_exec(selected, opts, cmd)
end

M.git_stage_unstage = function(selected, opts)
  for _, s in ipairs(selected) do
    local cmd = path.git_cwd({ "git", "diff", "--cached", "--quiet", "--" }, opts)
    local is_unstaged = git_exec({ s }, opts, cmd, true)
    if is_unstaged then
      M.git_stage({ s }, opts)
    else
      M.git_unstage({ s }, opts)
    end
  end
end

M.git_reset = function(selected, opts)
  if vim.fn.confirm("Reset " .. #selected .. " file(s)?", "&Yes\n&No") == 1 then
    for _, s in ipairs(selected) do
      s = utils.strip_ansi_coloring(s)
      local is_untracked = s:sub(5, 5) == "?"
      local cmd = is_untracked
          and path.git_cwd({ "git", "clean", "-f" }, opts)
          or path.git_cwd({ "git", "checkout", "HEAD", "--" }, opts)
      git_exec({ s }, opts, cmd)
      -- trigger autoread or warn the users buffer(s) was changed
      vim.cmd("checktime")
    end
  end
end

M.git_stash_drop = function(selected, opts)
  if vim.fn.confirm("Drop " .. #selected .. " stash(es)?", "&Yes\n&No") == 1 then
    local cmd = path.git_cwd({ "git", "stash", "drop" }, opts)
    git_exec(selected, opts, cmd)
  end
end

M.git_stash_pop = function(selected, opts)
  if vim.fn.confirm("Pop " .. #selected .. " stash(es)?", "&Yes\n&No") == 1 then
    local cmd = path.git_cwd({ "git", "stash", "pop" }, opts)
    git_exec(selected, opts, cmd)
    -- trigger autoread or warn the users buffer(s) was changed
    vim.cmd("checktime")
  end
end

M.git_stash_apply = function(selected, opts)
  if vim.fn.confirm("Apply " .. #selected .. " stash(es)?", "&Yes\n&No") == 1 then
    local cmd = path.git_cwd({ "git", "stash", "apply" }, opts)
    git_exec(selected, opts, cmd)
    -- trigger autoread or warn the users buffer(s) was changed
    vim.cmd("checktime")
  end
end

M.git_buf_edit = function(selected, opts)
  if #selected == 0 then return end
  local cmd = path.git_cwd({ "git", "show" }, opts)
  local git_root = path.git_root(opts, true)
  local win = vim.api.nvim_get_current_win()
  local buffer_filetype = vim.bo.filetype
  local file = path.relative_to(path.normalize(vim.fn.expand("%:p")), git_root)
  local commit_hash = match_commit_hash(selected[1], opts)
  table.insert(cmd, commit_hash .. ":" .. file)
  local git_file_contents = utils.io_systemlist(cmd)
  local buf = vim.api.nvim_create_buf(true, true)
  local file_name = string.gsub(file, "$", "[" .. commit_hash .. "]")
  vim.api.nvim_buf_set_lines(buf, 0, 0, true, git_file_contents)
  vim.api.nvim_buf_set_name(buf, file_name)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].modifiable = false
  vim.bo[buf].filetype = buffer_filetype
  vim.api.nvim_win_set_buf(win, buf)
end

M.git_buf_tabedit = function(selected, opts)
  vim.cmd("tab split")
  M.git_buf_edit(selected, opts)
end

M.git_buf_split = function(selected, opts)
  vim.cmd("split")
  M.git_buf_edit(selected, opts)
end

M.git_buf_vsplit = function(selected, opts)
  vim.cmd("vsplit")
  M.git_buf_edit(selected, opts)
end

M.git_goto_line = function(selected, _)
  if #selected == 0 then return end
  local line = selected[1] and selected[1]:match("^.-(%d+)%)")
  if tonumber(line) then
    vim.api.nvim_win_set_cursor(0, { tonumber(line), 0 })
  end
end

M.grep_lgrep = function(_, opts)
  opts.__ACT_TO({
    resume = true,
    -- different lookup key for grep|lgrep_curbuf
    __resume_key = opts.__resume_key,
    rg_glob = opts.rg_glob or opts.__call_opts.rg_glob,
    -- globs always require command processing with 'multiprocess'
    multiprocess = opts.multiprcess and (opts.rg_glob or opts.__call_opts.rg_glob) and 1,
    -- when used with tags pass the resolved ctags_file from tags-option as
    -- `tagfiles()` might not return the correct file called from the float (#700)
    ctags_file = opts.ctags_file,
  })
end

M.sym_lsym = function(_, opts)
  opts.__ACT_TO({ resume = true })
end

-- NOTE: not used, left for backward compat
-- some users may still be using this func
M.toggle_flag = function(_, opts)
  local o = vim.tbl_deep_extend("keep", {
    -- grep|live_grep sets `opts._cmd` to the original
    -- command without the search argument
    cmd = utils.toggle_cmd_flag(assert(opts._cmd or opts.cmd), assert(opts.toggle_flag)),
    resume = true
  }, opts.__call_opts)
  opts.__call_fn(o)
end

M.toggle_opt = function(opts, opt_name)
  -- opts.__call_opts[opt_name] = not opts[opt_name]
  local o = vim.tbl_deep_extend("keep", { resume = true }, opts.__call_opts)
  o[opt_name] = not opts[opt_name]
  opts.__call_fn(o)
end

M.toggle_ignore = function(_, opts)
  M.toggle_opt(opts, "no_ignore")
end

M.toggle_hidden = function(_, opts)
  M.toggle_opt(opts, "hidden")
end

M.toggle_follow = function(_, opts)
  M.toggle_opt(opts, "follow")
end

M.tmux_buf_set_reg = function(selected, opts)
  if #selected == 0 then return end
  local buf = selected[1]:match("^%[(.-)%]")
  local data, rc = utils.io_system({ "tmux", "show-buffer", "-b", buf })
  if rc == 0 and data and #data > 0 then
    opts.register = opts.register or [["]]
    local ok, err = pcall(vim.fn.setreg, opts.register, data)
    if ok then
      utils.info("%d characters copied into register %s", #data, opts.register)
    else
      utils.error("setreg(%s) failed: %s", opts.register, err)
    end
  end
end

M.paste_register = function(selected)
  if #selected == 0 then return end
  local reg = selected[1]:match("%[(.-)%]")
  local ok, data = pcall(vim.fn.getreg, reg)
  if ok and #data > 0 then
    vim.api.nvim_paste(data, false, -1)
  end
end

M.set_qflist = function(selected, opts)
  if #selected == 0 then return end
  local nr = selected[1]:match("[(%d+)]")
  vim.cmd(string.format("%d%s", tonumber(nr),
    opts._is_loclist and "lhistory" or "chistory"))
  vim.cmd(opts._is_loclist and "lopen" or "copen")
end

---@param selected string[]
---@param opts table
M.apply_profile = function(selected, opts)
  if #selected == 0 then return end
  local entry = path.entry_to_file(selected[1])
  local fname = entry.path
  local profile = entry.stripped:sub(#fname + 2):match("[^%s]+")
  local ok = utils.load_profile_fname(fname, profile, opts.silent)
  if ok then
    require("fzf-lua").setup({ profile })
  end
end

M.complete = function(selected, opts)
  if #selected == 0 then
    if opts.__CTX.mode == "i" then
      vim.cmd [[noautocmd lua vim.api.nvim_feedkeys('i', 'n', true)]]
    end
    return
  end
  -- cusror col is 0-based
  local col = opts.__CTX.cursor[2] + 1
  local newline, newcol
  if type(opts.complete) == "function" then
    newline, newcol = opts.complete(selected, opts, opts.__CTX.line, col)
  else
    local line = opts.__CTX.line
    local after = #line > col and line:sub(col + 1) or ""
    newline = line:sub(1, col) .. selected[1] .. after
    newcol = col + #selected[1]
  end
  vim.api.nvim_set_current_line(newline or opts.__CTX.line)
  vim.api.nvim_win_set_cursor(0, { opts.__CTX.cursor[1], newcol or col })
  if opts.__CTX.mode == "i" then
    vim.cmd [[noautocmd lua vim.api.nvim_feedkeys('a', 'n', true)]]
  end
end

M.dap_bp_del = function(selected, opts)
  local bufnrs = {}
  local dap_bps = require("dap.breakpoints")
  for _, e in ipairs(selected) do
    local entry = path.entry_to_file(e, opts)
    if entry.bufnr > 0 and tonumber(entry.line) and entry.line > 0 then
      dap_bps.remove(entry.bufnr, tonumber(entry.line))
      table.insert(bufnrs, tonumber(entry.bufnr))
    end
  end
  -- removing the BP will update the UI, if we're in session
  -- we also need to broadcast the BP delete to the DAP server
  local session = require("dap").session()
  if session then
    local bps = dap_bps.get()
    for _, b in ipairs(bufnrs) do
      -- If all BPs were removed from a buffer we must clear the buffer
      -- by sending an empty table in the bufnr index
      bps[b] = bps[b] or {}
    end
    session:set_breakpoints(bps)
  end
end

M.zoxide_cd = function(selected, opts)
  if #selected == 0 then return end
  local cwd = selected[1]:match("[^\t]+$") or selected[1]
  if opts.cwd then
    cwd = path.join({ opts.cwd, cwd })
  end
  local git_root = opts.git_root and path.git_root({ cwd = cwd }, true) or nil
  cwd = git_root or cwd
  if cwd == vim.uv.cwd() then
    utils.warn(("cwd already set to '%s'"):format(cwd))
    return
  end
  if uv.fs_stat(cwd) then
    local cmd = (opts.scope == "local" or opts.scope == "win") and "lcd"
        or opts.scope == "tab" and "tcd" or "cd"
    vim.cmd(cmd .. " " .. cwd)
    utils.io_system({ "zoxide", "add", "--", cwd })
    utils.info(("cwd set to %s'%s'"):format(git_root and "git root " or "", cwd))
  else
    utils.warn(("Unable to set cwd to '%s', directory is not accessible"):format(cwd))
  end
end

return M
