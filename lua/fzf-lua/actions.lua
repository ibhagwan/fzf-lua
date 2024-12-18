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
      if not v or k:match("^_") then return end
      k = k == "default" and "enter" or k
      v = type(v) == "table" and v or { fn = v }
      if opts.__FZF_VERSION and opts.__FZF_VERSION >= 0.53 then
        -- `print(...)` action was only added with fzf 0.53
        -- NOTE: we can no longer combine `--expect` and `--bind` as this will
        -- print an extra empty line regardless of the pressaed keybind (#1241)
        table.insert(binds, string.format("%s:print(%s)%s%s+accept",
          k,
          k,
          v.prefix and "+" or "",
          v.prefix and v.prefix:gsub("accept$", ""):gsub("%+$", "") or ""
        ))
      elseif opts.__SK_VERSION and opts.__SK_VERSION >= 0.14 then
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

M.normalize_selected = function(actions, selected, opts)
  -- The below separates the keybind from the item(s)
  -- and makes sure 'selected' contains only item(s) or {}
  -- so it can always be enumerated safely
  if not actions or not selected then return end
  if opts.__FZF_VERSION and opts.__FZF_VERSION >= 0.53
      or opts.__SK_VERSION and opts.__SK_VERSION >= 0.14 then
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

M.act = function(actions, selected, opts)
  if not actions or not selected then return end
  local keybind, entries = M.normalize_selected(actions, selected, opts)
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
M.dummy_abort = function()
end

M.resume = function(_, _)
  -- call via loadstring to prevent a circular ref
  loadstring([[require("fzf-lua").resume()]])()
end

M.vimcmd_entry = function(_vimcmd, selected, opts, pcall_vimcmd)
  for i, sel in ipairs(selected) do
    (function()
      -- Lua 5.1 goto compatiblity hack (function wrap)
      local entry = path.entry_to_file(sel, opts, opts._uri)
      -- "<none>" could be set by `autocmds`
      if entry.path == "<none>" then return end
      local fullpath = entry.bufname or entry.uri and entry.uri:match("^%a+://(.*)") or entry.path
      -- Something is not right, goto next entry
      if not fullpath then return end
      if not path.is_absolute(fullpath) then
        fullpath = path.join({ opts.cwd or opts._cwd or uv.cwd(), fullpath })
      end
      -- Adjust "<auto>" edits based on entry being buffer or filename
      local vimcmd = _vimcmd:gsub("<auto>", entry.bufnr and entry.bufname and "b" or "e")
      -- Do not execute "edit" commands if we already have the same buffer/file open
      -- or if we are dealing with a URI as it's open with `vim.lsp.util.show_document`
      -- opts.__CTX isn't guaranteed by API users (#1414)
      local CTX = opts.__CTX or utils.CTX()
      if vimcmd == "e" and (entry.uri or path.equals(fullpath, CTX.bname))
          or vimcmd == "b" and entry.bufnr and entry.bufnr == CTX.bufnr
      then
        vimcmd = nil
      end
      -- ":b" and ":e" commands replace the current buffer
      local will_replace_curbuf = vimcmd == "e" or vimcmd == "b"
      if will_replace_curbuf
          and not vim.o.hidden
          and not vim.o.autowriteall
          and utils.buffer_is_dirty(nil, false, true) then
        -- when `:set nohidden`, confirm with the user when trying to switch
        -- from a dirty buffer, abort if declined, save buffer if requested
        if utils.save_dialog(nil) then
          vimcmd = vimcmd .. "!"
        else
          return
        end
      end
      if will_replace_curbuf
          and vim.fn.exists("&winfixbuf") == 1
          and vim.wo.winfixbuf
      then
        utils.warn("'winfixbuf' is set for current window, will open in a split.")
        vimcmd = "split | " .. vimcmd
      end
      -- Can't be called from term window (for example, "reload" actions) due to
      -- nvim_exec2(): Vim(normal):Can't re-enter normal mode from terminal mode
      -- NOTE: we do not use `opts.__CTX.bufnr` as caller might be the fzf term
      if not utils.is_term_buffer(0) then
        vim.cmd("normal! m`")
      end
      if vimcmd then
        -- Killing term buffers requires "!" (#1078)
        if entry.terminal and vimcmd == "bd" then
          vimcmd = vimcmd .. "!"
        end
        -- URI entries only execute new buffers (new|vnew|tabnew)
        if not entry.uri then
          -- Force full paths when `autochdir=true` (#882)
          vimcmd = string.format("%s %s", vimcmd, (function()
            -- `:argdel|:argadd` uses only paths
            if vimcmd:match("^arg") then return entry.path end
            if entry.bufnr then return tostring(entry.bufnr) end
            -- We normalize the path or Windows will fail with directories starting
            -- with special characters, for example "C:\app\(web)" will be translated
            -- by neovim to "c:\app(web)" (#1082)
            local relpath = vim.o.autochdir and fullpath or path.relative_to(entry.path, uv.cwd())
            return vim.fn.fnameescape(path.normalize(relpath))
          end)())
        end
        if pcall_vimcmd ~= false then
          local ok, err = pcall(function() vim.cmd(vimcmd) end)
          if not ok then utils.warn(string.format("':%s' failed: %s", vimcmd, err)) end
        else
          vim.cmd(vimcmd)
        end
      end
      -- Reload actions from fzf's (buf/arg del, etc) window end here
      if utils.is_term_buffer(0) and vim.bo.ft == "fzf" then
        return
      end
      -- Java LSP entries, 'jdt://...' or LSP locations
      if entry.uri then
        if utils.is_term_bufname(entry.uri) then
          -- nvim_exec2(): Vim(normal):Can't re-enter normal mode from terminal mode
          pcall(utils.jump_to_location, entry, "utf-16")
        else
          utils.jump_to_location(entry, "utf-16")
        end
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
  local vimcmd = "<auto>"
  M.vimcmd_entry(vimcmd, selected, opts)
end

M.file_split = function(selected, opts)
  local vimcmd = "split | <auto>"
  M.vimcmd_entry(vimcmd, selected, opts)
end

M.file_vsplit = function(selected, opts)
  local vimcmd = "vsplit | <auto>"
  M.vimcmd_entry(vimcmd, selected, opts)
end

M.file_tabedit = function(selected, opts)
  local vimcmd = "tab split | <auto>"
  M.vimcmd_entry(vimcmd, selected, opts)
end

M.file_open_in_background = function(selected, opts)
  local vimcmd = "badd"
  M.vimcmd_entry(vimcmd, selected, opts)
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
  local title = string.format("[FzfLua] %s%s",
    opts.__INFO and opts.__INFO.cmd .. ": " or "",
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
    vim.fn.setqflist({}, " ", {
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
  local tabh, winid = selected[1]:match("(%d+):(%d+)%)")
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
    if entry.bufnr and not utils.buffer_is_dirty(entry.bufnr, true, false) then
      vim.api.nvim_buf_delete(entry.bufnr, { force = true })
    end
  end
end

M.arg_add = function(selected, opts)
  local vimcmd = "argadd"
  M.vimcmd_entry(vimcmd, selected, opts)
end

M.arg_del = function(selected, opts)
  local vimcmd = "argdel"
  -- since we don't dedup argdel can fail if file is added
  -- more than once into the arglist
  M.vimcmd_entry(vimcmd, selected, opts, true)
end

M.colorscheme = function(selected, opts)
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
  utils.info(string.format([[background set to "%s"]], vim.o.background))
end

M.run_builtin = function(selected)
  local method = selected[1]
  pcall(loadstring(string.format("require'fzf-lua'.%s()", method)))
end

M.ex_run = function(selected)
  local cmd = selected[1]
  vim.cmd("stopinsert")
  vim.fn.feedkeys(string.format(":%s", cmd), "n")
  return cmd
end

M.ex_run_cr = function(selected)
  local cmd = selected[1]
  vim.cmd(cmd)
  vim.fn.histadd("cmd", cmd)
end

M.exec_menu = function(selected)
  local cmd = selected[1]
  vim.cmd("emenu " .. cmd)
end


M.search = function(selected, opts)
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
  local mark = selected[1]
  mark = mark:match("[^ ]+")
  vim.cmd("stopinsert")
  vim.cmd("normal! `" .. mark)
  -- vim.fn.feedkeys(string.format("'%s", mark))
end

M.goto_jump = function(selected, opts)
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

M.spell_apply = function(selected)
  local word = selected[1]
  vim.cmd("normal! ciw" .. word)
  vim.cmd("stopinsert")
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
  vim.cmd("help " .. helptags(selected, opts)[1])
end

M.help_vert = function(selected, opts)
  vim.cmd("vert help " .. helptags(selected, opts)[1])
end

M.help_tab = function(selected, opts)
  vim.cmd("tab help " .. helptags(selected, opts)[1])
end

local function mantags(s)
  return vim.tbl_map(require("fzf-lua.providers.manpages").manpage_vim_arg, s)
end

M.man = function(selected)
  vim.cmd("Man " .. mantags(selected)[1])
end

M.man_vert = function(selected)
  vim.cmd("vert Man " .. mantags(selected)[1])
end

M.man_tab = function(selected)
  vim.cmd("tab Man " .. mantags(selected)[1])
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
    table.insert(cmd, "--detach")
  end
  table.insert(cmd, branch)
  local output, rc = utils.io_systemlist(cmd)
  if rc ~= 0 then
    utils.err(unpack(output))
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
      utils.err(unpack(output))
    else
      utils.info(string.format("Created branch '%s'.", branch))
    end
  end
end

M.git_branch_del = function(selected, opts)
  local cmd_del_branch = path.git_cwd(opts.cmd_del, opts)
  local cmd_cur_branch = path.git_cwd({ "git", "rev-parse", "--abbrev-ref", "HEAD" }, opts)
  local branch = selected[1]:match("[^%s%*]+")
  local cur_branch = utils.io_systemlist(cmd_cur_branch)[1]
  if branch == cur_branch then
    utils.warn(string.format("Cannot delete active branch '%s'", branch))
    return
  end
  if vim.fn.confirm("Delete branch " .. branch .. "?", "&Yes\n&No") == 1 then
    table.insert(cmd_del_branch, branch)
    local output, rc = utils.io_systemlist(cmd_del_branch)
    if rc ~= 0 then
      utils.err(unpack(output))
    else
      utils.info(unpack(output))
    end
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
  local commit_hash = match_commit_hash(selected[1], opts)
  if vim.o.clipboard == "unnamed" then
    vim.fn.setreg([[*]], commit_hash)
  elseif vim.o.clipboard == "unnamedplus" then
    vim.fn.setreg([[+]], commit_hash)
  else
    vim.fn.setreg([["]], commit_hash)
  end
  -- copy to the yank register regardless
  vim.fn.setreg([[0]], commit_hash)
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
      utils.err(unpack(output))
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
      utils.err(unpack(output) or string.format("exit code %d", rc))
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
    requires_processing = opts.rg_glob or opts.__call_opts.rg_glob,
    -- when used with tags pass the resolved ctags_file from tags-option as
    -- `tagfiles()` might not return the correct file called from the float (#700)
    ctags_file = opts.ctags_file,
  })
end

M.sym_lsym = function(_, opts)
  opts.__ACT_TO({ resume = true })
end

M.toggle_flag = function(_, opts)
  local o = vim.tbl_deep_extend("keep", { resume = true }, opts.__call_opts)
  local flag = opts.toggle_flag
  if not flag then
    utils.err("'toggle_flag' not set")
    return
  end
  if not flag:match("^%s") then
    -- flag must be preceded by whitespace
    flag = " " .. flag
  end
  -- grep|live_grep sets `opts._cmd` to the original
  -- command without the search argument
  local cmd = opts._cmd or opts.cmd
  if cmd:match(utils.lua_regex_escape(flag)) then
    o.cmd = cmd:gsub(utils.lua_regex_escape(flag), "")
  else
    local bin, args = cmd:match("([^%s]+)(.*)$")
    o.cmd = string.format("%s%s%s", bin, flag, args)
  end
  opts.__call_fn(o)
end

M.toggle_ignore = function(_, opts)
  local flag = opts.toggle_ignore_flag or "--no-ignore"
  M.toggle_flag(_, vim.tbl_extend("force", opts, { toggle_flag = flag }))
end

M.toggle_hidden = function(_, opts)
  local flag = opts.toggle_hidden_flag or "--hidden"
  M.toggle_flag(_, vim.tbl_extend("force", opts, { toggle_flag = flag }))
end

M.tmux_buf_set_reg = function(selected, opts)
  local buf = selected[1]:match("^%[(.-)%]")
  local data, rc = utils.io_system({ "tmux", "show-buffer", "-b", buf })
  if rc == 0 and data and #data > 0 then
    opts.register = opts.register or [["]]
    local ok, err = pcall(vim.fn.setreg, opts.register, data)
    if ok then
      utils.info(string.format("%d characters copied into register %s",
        #data, opts.register))
    else
      utils.err(string.format("setreg(%s) failed: %s", opts.register, err))
    end
  end
end

M.paste_register = function(selected)
  local reg = selected[1]:match("%[(.-)%]")
  local ok, data = pcall(vim.fn.getreg, reg)
  if ok and #data > 0 then
    vim.api.nvim_paste(data, false, -1)
  end
end

M.set_qflist = function(selected, opts)
  local nr = selected[1]:match("[(%d+)]")
  vim.cmd(string.format("%d%s", tonumber(nr),
    opts._is_loclist and "lhistory" or "chistory"))
  vim.cmd(opts._is_loclist and "lopen" or "copen")
end

---@param selected string[]
---@param opts table
M.apply_profile = function(selected, opts)
  local entry = path.entry_to_file(selected[1])
  local fname = entry.path
  local profile = entry.stripped:sub(#fname + 2):match("[^%s]+")
  local ok = utils.load_profile_fname(fname, profile, opts.silent)
  if ok then
    loadstring(string.format([[require("fzf-lua").setup({"%s"})]], profile))()
  end
end

M.complete = function(selected, opts)
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

return M
