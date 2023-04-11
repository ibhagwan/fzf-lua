local utils = require "fzf-lua.utils"
local path = require "fzf-lua.path"

local M = {}

-- default action map key
local _default_action = "default"

-- return fzf '--expect=' string from actions keyval tbl
M.expect = function(actions)
  if not actions then return nil end
  local keys = {}
  for k, v in pairs(actions) do
    if k ~= _default_action and v ~= false then
      table.insert(keys, k)
    end
  end
  if #keys > 0 then
    return string.format("--expect=%s", table.concat(keys, ","))
  end
  return nil
end

M.normalize_selected = function(actions, selected)
  -- 1. If there are no additional actions but the default,
  --    the selected table will contain the selected item(s)
  -- 2. If at least one non-default action was defined, our 'expect'
  --    function above sent fzf the '--expect` flag, from `man fzf`:
  --      When this option is set, fzf will print the name of
  --      the key pressed as the first line of its output (or
  --      as the second line if --print-query is also used).
  --
  -- The below separates the keybind from the item(s)
  -- and makes sure 'selected' contains only item(s) or {}
  -- so it can always be enumerated safely
  if not actions or not selected then return end
  local action = _default_action
  if utils.tbl_length(actions) > 1 or not actions[_default_action] then
    -- keybind should be in item #1
    -- default keybind is an empty string
    -- so we leave that as "default"
    if #selected[1] > 0 then
      action = selected[1]
    end
    -- entries are items #2+
    local entries = {}
    for i = 2, #selected do
      table.insert(entries, selected[i])
    end
    return action, entries
  else
    return action, selected
  end
end

M.act = function(actions, selected, opts)
  if not actions or not selected then return end
  local keybind, entries = M.normalize_selected(actions, selected)
  local action = actions[keybind]
  if type(action) == "table" then
    for _, f in ipairs(action) do
      f(entries, opts)
    end
  elseif type(action) == "function" then
    action(entries, opts)
  elseif type(action) == "string" then
    vim.cmd(action)
  elseif keybind ~= _default_action then
    utils.warn(("unsupported action: '%s', type:%s")
      :format(keybind, type(action)))
  end
end

-- Dummy abort action for `esc|ctrl-c|ctrl-q`
M.dummy_abort = function()
end

M.resume = function(_, _)
  -- must call via vim.cmd or we create
  -- circular 'require'
  -- TODO: is this really a big deal?
  vim.cmd("lua require'fzf-lua'.resume()")
end

M.vimcmd = function(vimcmd, selected, noesc)
  for i = 1, #selected do
    vim.cmd(("%s %s"):format(vimcmd,
      noesc and selected[i] or vim.fn.fnameescape(selected[i])))
  end
end

M.vimcmd_file = function(vimcmd, selected, opts)
  local curbuf = vim.api.nvim_buf_get_name(0)
  local is_term = utils.is_term_buffer(0)
  for i = 1, #selected do
    local entry = path.entry_to_file(selected[i], opts, opts.force_uri)
    if entry.path == "<none>" then goto continue end
    entry.ctag = opts._ctag and path.entry_to_ctag(selected[i])
    local fullpath = entry.path or entry.uri and entry.uri:match("^%a+://(.*)")
    if not path.starts_with_separator(fullpath) then
      fullpath = path.join({ opts.cwd or vim.loop.cwd(), fullpath })
    end
    if vimcmd == "e"
        and curbuf ~= fullpath
        and not vim.o.hidden
        and utils.buffer_is_dirty(nil, false, true) then
      -- confirm with user when trying to switch
      -- from a dirty buffer when `:set nohidden`
      -- abort if the user declines
      -- save the buffer if requested
      if utils.save_dialog(nil) then
        vimcmd = vimcmd .. "!"
      else
        return
      end
    end
    -- add current location to jumplist
    if not is_term then vim.cmd("normal! m`") end
    -- only change buffer if we need to (issue #122)
    if vimcmd ~= "e" or curbuf ~= fullpath then
      if entry.path then
        -- do not run ':<cmd> <file>' for uri entries (#341)
        local relpath = path.relative(entry.path, vim.loop.cwd())
        vim.cmd(vimcmd .. " " .. vim.fn.fnameescape(relpath))
      elseif vimcmd ~= "e" then
        -- uri entries only execute new buffers (new|vnew|tabnew)
        vim.cmd(vimcmd)
      end
    end
    -- Java LSP entries, 'jdt://...' or LSP locations
    if entry.uri then
      vim.lsp.util.jump_to_location(entry, "utf-16")
    elseif entry.ctag then
      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      vim.fn.search(entry.ctag, "W")
    elseif entry.line > 1 or entry.col > 1 then
      -- make sure we have valid column
      -- 'nvim-dap' for example sets columns to 0
      entry.col = entry.col and entry.col > 0 and entry.col or 1
      vim.api.nvim_win_set_cursor(0, { tonumber(entry.line), tonumber(entry.col) - 1 })
    end
    if not is_term and not opts.no_action_zz then vim.cmd("norm! zvzz") end
    ::continue::
  end
end

-- file actions
M.file_edit = function(selected, opts)
  local vimcmd = "e"
  M.vimcmd_file(vimcmd, selected, opts)
end

M.file_split = function(selected, opts)
  local vimcmd = "new"
  M.vimcmd_file(vimcmd, selected, opts)
end

M.file_vsplit = function(selected, opts)
  local vimcmd = "vnew"
  M.vimcmd_file(vimcmd, selected, opts)
end

M.file_tabedit = function(selected, opts)
  local vimcmd = "tabnew"
  M.vimcmd_file(vimcmd, selected, opts)
end

M.file_open_in_background = function(selected, opts)
  local vimcmd = "badd"
  M.vimcmd_file(vimcmd, selected, opts)
end

local sel_to_qf = function(selected, opts, is_loclist)
  local qf_list = {}
  for i = 1, #selected do
    local file = path.entry_to_file(selected[i], opts)
    local text = selected[i]:match(":%d+:%d?%d?%d?%d?:?(.*)$")
    table.insert(qf_list, {
      filename = file.bufname or file.path,
      lnum = file.line,
      col = file.col,
      text = text,
    })
  end
  if is_loclist then
    vim.fn.setloclist(0, {}, " ", {
      nr = "$",
      items = qf_list,
      title = opts.__resume_data.last_query,
    })
    vim.cmd(opts.lopen or "lopen")
  else
    -- Set the quickfix title to last query and
    -- append a new list to end of the stack (#635)
    vim.fn.setqflist({}, " ", {
      nr = "$",
      items = qf_list,
      title = opts.__resume_data.last_query,
      -- nr = nr,
    })
    vim.cmd(opts.copen or "copen")
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
  local bufnr = nil
  local entry = path.entry_to_file(selected[1])
  local fullpath = entry.path
  if not path.starts_with_separator(fullpath) then
    fullpath = path.join({ opts.cwd or vim.loop.cwd(), fullpath })
  end
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    local bname = vim.api.nvim_buf_get_name(b)
    if bname and bname == fullpath then
      bufnr = b
      break
    end
  end
  if not bufnr then return false end
  local is_term = utils.is_term_buffer(0)
  if not is_term then vim.cmd("normal! m`") end
  local winid = utils.winid_from_tabh(0, bufnr)
  if winid then vim.api.nvim_set_current_win(winid) end
  if entry.line > 1 or entry.col > 1 then
    vim.api.nvim_win_set_cursor(0, { tonumber(entry.line), tonumber(entry.col) - 1 })
  end
  if not is_term and not opts.no_action_zz then vim.cmd("norm! zvzz") end
  return true
end

M.file_switch_or_edit = function(...)
  M.file_switch(...)
  M.file_edit(...)
end

-- buffer actions
M.vimcmd_buf = function(vimcmd, selected, opts)
  local curbuf = vim.api.nvim_get_current_buf()
  local lnum = vim.api.nvim_win_get_cursor(0)[1]
  local is_term = utils.is_term_buffer(0)
  for i = 1, #selected do
    local entry = path.entry_to_file(selected[i], opts)
    if not entry.bufnr then return end
    assert(type(entry.bufnr) == "number")
    if vimcmd == "b"
        and curbuf ~= entry.bufnr
        and not vim.o.hidden
        and utils.buffer_is_dirty(nil, false, true) then
      -- confirm with user when trying to switch
      -- from a dirty buffer when `:set nohidden`
      -- abort if the user declines
      -- save the buffer if requested
      if utils.save_dialog(nil) then
        vimcmd = vimcmd .. "!"
      else
        return
      end
    end
    -- add current location to jumplist
    if not is_term then vim.cmd("normal! m`") end
    if vimcmd ~= "b" or curbuf ~= entry.bufnr then
      local cmd = vimcmd .. " " .. entry.bufnr
      local ok, res = pcall(vim.cmd, cmd)
      if not ok then
        utils.warn(("':%s' failed: %s"):format(cmd, res))
      end
    end
    if vimcmd ~= "bd" and not opts.no_action_set_cursor then
      if curbuf ~= entry.bufnr or lnum ~= entry.line then
        -- make sure we have valid column
        entry.col = entry.col and entry.col > 0 and entry.col or 1
        vim.api.nvim_win_set_cursor(0, { tonumber(entry.line), tonumber(entry.col) - 1 })
      end
      if not is_term and not opts.no_action_zz then vim.cmd("norm! zvzz") end
    end
  end
end

M.buf_edit = function(selected, opts)
  local vimcmd = "b"
  M.vimcmd_buf(vimcmd, selected, opts)
end

M.buf_split = function(selected, opts)
  local vimcmd = "split | b"
  M.vimcmd_buf(vimcmd, selected, opts)
end

M.buf_vsplit = function(selected, opts)
  local vimcmd = "vertical split | b"
  M.vimcmd_buf(vimcmd, selected, opts)
end

M.buf_tabedit = function(selected, opts)
  local vimcmd = "tab split | b"
  M.vimcmd_buf(vimcmd, selected, opts)
end

M.buf_del = function(selected, opts)
  local vimcmd = "bd"
  local bufnrs = vim.tbl_filter(function(line)
    local b = tonumber(line:match("%[(%d+)"))
    return not utils.buffer_is_dirty(b, true, false)
  end, selected)
  M.vimcmd_buf(vimcmd, bufnrs, opts)
end

M.buf_switch = function(selected, _)
  local tabidx = tonumber(selected[1]:match("(%d+)%)"))
  local tabh = tabidx and vim.api.nvim_list_tabpages()[tabidx]
  if tabh then
    -- `:tabn` will result in the wrong tab
    -- if `:tabmove` was previously used (#515)
    vim.api.nvim_set_current_tabpage(tabh)
  else
    tabh = vim.api.nvim_win_get_tabpage(0)
  end
  local bufnr = tonumber(string.match(selected[1], "%[(%d+)"))
  if bufnr then
    local winid = utils.winid_from_tabh(tabh, bufnr)
    if winid then vim.api.nvim_set_current_win(winid) end
  end
end

M.buf_switch_or_edit = function(...)
  M.buf_switch(...)
  M.buf_edit(...)
end

M.buf_sel_to_qf = function(selected, opts)
  return sel_to_qf(selected, opts)
end

M.buf_sel_to_ll = function(selected, opts)
  return sel_to_qf(selected, opts, true)
end

M.buf_edit_or_qf = function(selected, opts)
  if #selected > 1 then
    return M.buf_sel_to_qf(selected, opts)
  else
    return M.buf_edit(selected, opts)
  end
end

M.colorscheme = function(selected)
  local colorscheme = selected[1]
  vim.cmd("colorscheme " .. colorscheme)
end

M.ensure_insert_mode = function()
  -- not sure what is causing this, tested with
  -- 'NVIM v0.6.0-dev+575-g2ef9d2a66'
  -- vim.cmd("startinsert") doesn't start INSERT mode
  -- 'mode' returns { blocking = false, mode = "t" }
  -- manually input 'i' seems to workaround this issue
  -- **only if fzf term window was succefully opened (#235)
  -- this is only required after the 'nt' (normal-terminal)
  -- mode was introduced along with the 'ModeChanged' event
  -- https://github.com/neovim/neovim/pull/15878
  -- https://github.com/neovim/neovim/pull/15840
  -- local has_mode_nt = not vim.tbl_isempty(
  --   vim.fn.getcompletion('ModeChanged', 'event'))
  --   or vim.fn.has('nvim-0.6') == 1
  -- if has_mode_nt then
  --   local mode = vim.api.nvim_get_mode()
  --   local wininfo = vim.fn.getwininfo(vim.api.nvim_get_current_win())[1]
  --   if vim.bo.ft == 'fzf'
  --     and wininfo.terminal == 1
  --     and mode and mode.mode == 't' then
  --     vim.cmd[[noautocmd lua vim.api.nvim_feedkeys('i', 'n', true)]]
  --   end
  -- end
  utils.warn("calling 'ensure_insert_mode' is no longer required and can be safely omitted.")
end

M.run_builtin = function(selected)
  local method = selected[1]
  vim.cmd(string.format("lua require'fzf-lua'.%s()", method))
end

M.ex_run = function(selected)
  local cmd = selected[1]
  vim.cmd("stopinsert")
  vim.fn.feedkeys(string.format(":%s", cmd), "n")
  return cmd
end

M.ex_run_cr = function(selected)
  local cmd = M.ex_run(selected)
  utils.feed_keys_termcodes("<CR>")
  vim.fn.histadd("cmd", cmd)
end

M.exec_menu = function(selected)
  local cmd = selected[1]
  vim.cmd("emenu " .. cmd)
end


M.search = function(selected)
  local query = selected[1]
  vim.cmd("stopinsert")
  vim.fn.feedkeys(string.format("/%s", query), "n")
  return query
end

M.search_cr = function(selected)
  local query = M.search(selected)
  utils.feed_keys_termcodes("<CR>")
  vim.fn.histadd("search", query)
end

M.goto_mark = function(selected)
  local mark = selected[1]
  mark = mark:match("[^ ]+")
  vim.cmd("stopinsert")
  vim.cmd("normal! '" .. mark)
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
    local ok, res = pcall(vim.fn.expand, filepath)
    if not ok then
      filepath = ""
    else
      filepath = res
    end
    if not filepath or not vim.loop.fs_stat(filepath) then
      -- no accessible file
      -- jump is in current
      filepath = vim.api.nvim_buf_get_name(0)
    end
    local entry = ("%s:%d:%d:"):format(filepath, tonumber(lnum), tonumber(col) + 1)
    M.file_edit({ entry }, opts)
  end
end

M.keymap_apply = function(selected)
  local key = selected[1]:match("[│]%s+(.*)%s+[│]")
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(key, true, false, true), "t", true)
end

M.spell_apply = function(selected)
  local word = selected[1]
  vim.cmd("normal! ciw" .. word)
  vim.cmd("stopinsert")
end

M.set_filetype = function(selected)
  vim.api.nvim_buf_set_option(0, "filetype", selected[1])
end

M.packadd = function(selected)
  for i = 1, #selected do
    vim.cmd("packadd " .. selected[i])
  end
end

local function helptags(s)
  return vim.tbl_map(function(x)
    return x:match("[^%s]+")
  end, s)
end

M.help = function(selected)
  local vimcmd = "help"
  M.vimcmd(vimcmd, helptags(selected), true)
end

M.help_vert = function(selected)
  local vimcmd = "vert help"
  M.vimcmd(vimcmd, helptags(selected), true)
end

M.help_tab = function(selected)
  local vimcmd = "tab help"
  M.vimcmd(vimcmd, helptags(selected), true)
end

local function mantags(s)
  return vim.tbl_map(function(x)
    return x:match("[^[,( ]+")
  end, s)
end

M.man = function(selected)
  local vimcmd = "Man"
  M.vimcmd(vimcmd, mantags(selected))
end

M.man_vert = function(selected)
  local vimcmd = "vert Man"
  M.vimcmd(vimcmd, mantags(selected))
end

M.man_tab = function(selected)
  local vimcmd = "tab Man"
  M.vimcmd(vimcmd, mantags(selected))
end


M.git_switch = function(selected, opts)
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
  local output = utils.io_systemlist(cmd)
  if utils.shell_error() then
    utils.err(unpack(output))
  else
    utils.info(unpack(output))
    vim.cmd("edit!")
  end
end

M.git_checkout = function(selected, opts)
  local cmd_checkout = path.git_cwd({ "git", "checkout" }, opts)
  local cmd_cur_commit = path.git_cwd({ "git", "rev-parse", "--short HEAD" }, opts)
  local commit_hash = selected[1]:match("[^ ]+")
  if utils.input("Checkout commit " .. commit_hash .. "? [y/n] ") == "y" then
    local current_commit = utils.io_systemlist(cmd_cur_commit)
    if (commit_hash == current_commit) then return end
    table.insert(cmd_checkout, commit_hash)
    local output = utils.io_systemlist(cmd_checkout)
    if utils.shell_error() then
      utils.err(unpack(output))
    else
      utils.info(unpack(output))
      vim.cmd("edit!")
    end
  end
end

local git_exec = function(selected, opts, cmd)
  for _, e in ipairs(selected) do
    local file = path.relative(path.entry_to_file(e, opts).path, opts.cwd)
    local _cmd = vim.deepcopy(cmd)
    table.insert(_cmd, file)
    local output = utils.io_systemlist(_cmd)
    if utils.shell_error() then
      utils.err(unpack(output))
      -- elseif not vim.tbl_isempty(output) then
      --   utils.info(unpack(output))
    end
  end
end

M.git_stage = function(selected, opts)
  local cmd = path.git_cwd({ "git", "add", "--" }, opts)
  git_exec(selected, opts, cmd)
end

M.git_unstage = function(selected, opts)
  local cmd = path.git_cwd({ "git", "reset", "--" }, opts)
  git_exec(selected, opts, cmd)
end

M.git_reset = function(selected, opts)
  local cmd = path.git_cwd({ "git", "checkout", "HEAD", "--" }, opts)
  git_exec(selected, opts, cmd)
end

M.git_stash_drop = function(selected, opts)
  local cmd = path.git_cwd({ "git", "stash", "drop" }, opts)
  git_exec(selected, opts, cmd)
end

M.git_stash_pop = function(selected, opts)
  if utils.input("Pop " .. #selected .. " stash(es)? [y/n] ") == "y" then
    local cmd = path.git_cwd({ "git", "stash", "pop" }, opts)
    git_exec(selected, opts, cmd)
    vim.cmd("e!")
  end
end

M.git_stash_apply = function(selected, opts)
  if utils.input("Apply " .. #selected .. " stash(es)? [y/n] ") == "y" then
    local cmd = path.git_cwd({ "git", "stash", "apply" }, opts)
    git_exec(selected, opts, cmd)
    vim.cmd("e!")
  end
end

M.git_buf_edit = function(selected, opts)
  local cmd = path.git_cwd({ "git", "show" }, opts)
  local git_root = path.git_root(opts, true)
  local win = vim.api.nvim_get_current_win()
  local buffer_filetype = vim.bo.filetype
  local file = path.relative(vim.fn.expand("%:p"), git_root)
  local commit_hash = selected[1]:match("[^ ]+")
  table.insert(cmd, commit_hash .. ":" .. file)
  local git_file_contents = utils.io_systemlist(cmd)
  local buf = vim.api.nvim_create_buf(true, true)
  local file_name = string.gsub(file, "$", "[" .. commit_hash .. "]")
  vim.api.nvim_buf_set_lines(buf, 0, 0, true, git_file_contents)
  vim.api.nvim_buf_set_name(buf, file_name)
  vim.api.nvim_buf_set_option(buf, "buftype", "nofile")
  vim.api.nvim_buf_set_option(buf, "bufhidden", "wipe")
  vim.api.nvim_buf_set_option(buf, "filetype", buffer_filetype)
  vim.api.nvim_buf_set_option(buf, "modifiable", false)
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

M.arg_add = function(selected, opts)
  local vimcmd = "argadd"
  M.vimcmd_file(vimcmd, selected, opts)
end

M.arg_del = function(selected, opts)
  local vimcmd = "argdel"
  M.vimcmd_file(vimcmd, selected, opts)
end

M.grep_lgrep = function(_, opts)
  -- 'MODULE' is set on 'grep' and 'live_grep' calls
  assert(opts.__MODULE__
    and type(opts.__MODULE__.grep) == "function"
    or type(opts.__MODULE__.live_grep) == "function")

  local o = vim.tbl_extend("keep", {
    search = false,
    resume = true,
    resume_search_default = "",
    rg_glob = opts.rg_glob or opts.__call_opts.rg_glob,
    -- globs always require command processing with 'multiprocess'
    requires_processing = opts.rg_glob or opts.__call_opts.rg_glob,
    -- grep has both search string and query prompt, when switching
    -- from live_grep to grep we want to restore both:
    --   * we save the last query prompt when exiting grep
    --   * we set query to the last known when entering grep
    __prev_query = not opts.fn_reload and opts.__resume_data.last_query,
    query = opts.fn_reload and opts.__call_opts.__prev_query,
    -- when used with tags pass the resolved ctags_file from tags-option as
    -- `tagfiles()` might not return the correct file called from the float (#700)
    ctags_file = opts.ctags_file,
  }, opts.__call_opts or {})

  -- 'fn_reload' is set only on 'live_grep' calls
  if opts.fn_reload then
    opts.__MODULE__.grep(o)
  else
    opts.__MODULE__.live_grep(o)
  end
end

M.sym_lsym = function(_, opts)
  assert(opts.__MODULE__
    and type(opts.__MODULE__.workspace_symbols) == "function"
    or type(opts.__MODULE__.live_workspace_symbols) == "function")

  local o = vim.tbl_extend("keep", {
    resume = true,
    lsp_query = false,
    -- ws has both search string and query prompt, when
    -- switching from live_ws to ws we want to restore both:
    --   * we save the last query prompt when exiting ws
    --   * we set query to the last known when entering ws
    __prev_query = not opts.fn_reload and opts.__resume_data.last_query,
    query = opts.fn_reload and opts.__call_opts.__prev_query,
  }, opts.__call_opts or {})

  -- 'fn_reload' is set only on 'live_xxx' calls
  if opts.fn_reload then
    opts.__MODULE__.workspace_symbols(o)
  else
    opts.__MODULE__.live_workspace_symbols(o)
  end
end

M.tmux_buf_set_reg = function(selected, opts)
  local buf = selected[1]:match("^%[(.-)%]")
  local data = vim.fn.system({ "tmux", "show-buffer", "-b", buf })
  if not utils.shell_error() and data and #data > 0 then
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

M.apply_profile = function(selected, opts)
  local fname = selected[1]:match("[^:]+")
  local profile = selected[1]:match(":([^%s]+)")
  local ok = utils.load_profile(fname, profile, opts.silent)
  if ok then
    vim.cmd(string.format([[lua require("fzf-lua").setup({"%s"})]], profile))
  end
end

M.complete_insert = function(selected, opts)
  local line = vim.api.nvim_get_current_line()
  local before = opts.cmp_string_col > 1 and line:sub(1, opts.cmp_string_col - 1) or ""
  local after = line:sub(opts.cmp_string_col + (opts.cmp_string and #opts.cmp_string or 0))
  local entry = selected[1]
  if opts.cmp_is_file then
    entry = path.relative(path.entry_to_file(selected[1], opts).path, opts.cwd)
  elseif opts.cmp_is_line then
    entry = selected[1]:match("^.*:%d+:%s(.*)")
  end
  local subst = (opts.cmp_prefix or "") .. entry
  vim.api.nvim_set_current_line(before .. subst .. after)
  vim.api.nvim_win_set_cursor(0, { opts.cmp_string_row, opts.cmp_string_col + #subst - 2 })
  if opts.cmp_mode == "i" then
    vim.cmd [[noautocmd lua vim.api.nvim_feedkeys('a', 'n', true)]]
  end
end

return M
