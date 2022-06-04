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
    return string.format("--expect=%s", table.concat(keys, ','))
  end
  return nil
end

M.normalize_selected = function(actions, selected)
  -- 1. If there are no additional actions but the default
  --    the selected table will contain the selected item(s)
  -- 2. If multiple actions where defined the first item
  --    will contain the action keybind string
  --
  -- The below makes separates the keybind from the item(s)
  -- and makes sure 'selected' contains only items or {}
  -- so it can always be enumerated safely
  if not actions or not selected then return end
  local action = _default_action
  if utils.tbl_length(actions)>1 then
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
  if type(action) == 'table' then
    for _, f in ipairs(action) do
      f(entries, opts)
    end
  elseif type(action) == 'function' then
    action(entries, opts)
  elseif type(action) == 'string' then
    vim.cmd(action)
  else
    utils.warn(("unsupported action: '%s', type:%s")
      :format(action, type(action)))
  end
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
    entry.ctag = opts._ctag and path.entry_to_ctag(selected[i])
    local fullpath = entry.path or entry.uri and entry.uri:match("^%a+://(.*)")
    if not path.starts_with_separator(fullpath) then
      fullpath = path.join({opts.cwd or vim.loop.cwd(), fullpath})
    end
    if vimcmd == 'e'
        and curbuf ~= fullpath
        and not vim.o.hidden and
        utils.buffer_is_dirty(nil, true) then
        -- warn the user when trying to switch from a dirty buffer
        -- when `:set nohidden`
        return
    end
    -- add current location to jumplist
    if not is_term then vim.cmd("normal! m`") end
    -- only change buffer if we need to (issue #122)
    if vimcmd ~= "e" or curbuf ~= fullpath then
      if entry.path then
        -- do not run ':<cmd> <file>' for uri entries (#341)
        vim.cmd(vimcmd .. " " .. vim.fn.fnameescape(entry.path))
      elseif vimcmd ~= 'e' then
        -- uri entries only execute new buffers (new|vnew|tabnew)
        vim.cmd(vimcmd)
      end
    end
    -- Java LSP entries, 'jdt://...' or LSP locations
    if entry.uri then
      vim.lsp.util.jump_to_location(entry, "utf-16")
    elseif entry.ctag then
      vim.api.nvim_win_set_cursor(0, {1, 0})
      vim.fn.search(entry.ctag, "W")
    elseif entry.line>1 or entry.col>1 then
      -- make sure we have valid column
      -- 'nvim-dap' for example sets columns to 0
      entry.col = entry.col and entry.col>0 and entry.col or 1
      vim.api.nvim_win_set_cursor(0, {tonumber(entry.line), tonumber(entry.col)-1})
    end
    if not is_term then vim.cmd("norm! zvzz") end
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

M.file_sel_to_qf = function(selected, _)
  local qf_list = {}
  for i = 1, #selected do
    local file = path.entry_to_file(selected[i])
    local text = selected[i]:match(":%d+:%d?%d?%d?%d?:?(.*)$")
    table.insert(qf_list, {
      filename = file.path,
      lnum = file.line,
      col = file.col,
      text = text,
    })
  end
  vim.fn.setqflist(qf_list)
  vim.cmd 'copen'
end

M.file_edit_or_qf = function(selected, opts)
  if #selected>1 then
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
    fullpath = path.join({opts.cwd or vim.loop.cwd(), fullpath})
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
  local winid = utils.winid_from_tab_buf(0, bufnr)
  if winid then vim.api.nvim_set_current_win(winid) end
  if entry.line>1 or entry.col>1 then
    vim.api.nvim_win_set_cursor(0, {tonumber(entry.line), tonumber(entry.col)-1})
  end
  if not is_term then vim.cmd("norm! zvzz") end
  return true
end

M.file_switch_or_edit = function(...)
  M.file_switch(...)
  M.file_edit(...)
end

-- buffer actions
M.vimcmd_buf = function(vimcmd, selected, _)
  local curbuf = vim.api.nvim_get_current_buf()
  for i = 1, #selected do
    local bufnr = string.match(selected[i], "%[(%d+)")
    if bufnr then
      if vimcmd == 'b'
        and curbuf ~= tonumber(bufnr)
        and not vim.o.hidden and
        utils.buffer_is_dirty(nil, true) then
        -- warn the user when trying to switch from a dirty buffer
        -- when `:set nohidden`
        return
      end
      if vimcmd ~= "b" or curbuf ~= tonumber(bufnr) then
        local cmd = vimcmd .. " " .. bufnr
        local ok, res = pcall(vim.cmd, cmd)
        if not ok then
          utils.warn(("':%s' failed: %s"):format(cmd, res))
        end
      end
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
    return not utils.buffer_is_dirty(b, true)
  end, selected)
  M.vimcmd_buf(vimcmd, bufnrs, opts)
end

M.buf_switch = function(selected, _)
  local tabnr = selected[1]:match("(%d+)%)")
  if tabnr then
    vim.cmd("tabn " .. tabnr)
  else
    tabnr = vim.api.nvim_win_get_tabpage(0)
  end
  local bufnr = tonumber(string.match(selected[1], "%[(%d+)"))
  if bufnr then
    local winid = utils.winid_from_tab_buf(tabnr, bufnr)
    if winid then vim.api.nvim_set_current_win(winid) end
  end
end

M.buf_switch_or_edit = function(...)
  M.buf_switch(...)
  M.buf_edit(...)
end

M.buf_sel_to_qf = function(selected, opts)
  return M.file_sel_to_qf(selected, opts)
end

M.buf_edit_or_qf = function(selected, opts)
  if #selected>1 then
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
    if not ok then filepath = ''
    else filepath = res end
    if not filepath or not vim.loop.fs_stat(filepath) then
      -- no accessible file
      -- jump is in current
      filepath = vim.api.nvim_buf_get_name(0)
    end
    local entry = ("%s:%d:%d:"):format(filepath, tonumber(lnum), tonumber(col)+1)
    M.file_edit({ entry }, opts)
  end
end

M.spell_apply = function(selected)
  local word = selected[1]
  vim.cmd("normal! ciw" .. word)
  vim.cmd("stopinsert")
end

M.set_filetype = function(selected)
  vim.api.nvim_buf_set_option(0, 'filetype', selected[1])
end

M.packadd = function(selected)
  for i = 1, #selected do
    vim.cmd("packadd " .. selected[i])
  end
end

M.help = function(selected)
  local vimcmd = "help"
  M.vimcmd(vimcmd, selected, true)
end

M.help_vert = function(selected)
  local vimcmd = "vert help"
  M.vimcmd(vimcmd, selected, true)
end

M.help_tab = function(selected)
  local vimcmd = "tab help"
  M.vimcmd(vimcmd, selected, true)
end

M.man = function(selected)
  local vimcmd = "Man"
  M.vimcmd(vimcmd, selected)
end

M.man_vert = function(selected)
  local vimcmd = "vert Man"
  M.vimcmd(vimcmd, selected)
end

M.man_tab = function(selected)
  local vimcmd = "tab Man"
  M.vimcmd(vimcmd, selected)
end


M.git_switch = function(selected, opts)
  local cmd = path.git_cwd({"git", "checkout"}, opts)
  local git_ver = utils.git_version()
  -- git switch was added with git version 2.23
  if git_ver and git_ver >= 2.23 then
    cmd = path.git_cwd({"git", "switch"}, opts)
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
  local cmd_checkout = path.git_cwd({"git", "checkout"}, opts)
  local cmd_cur_commit = path.git_cwd({"git", "rev-parse", "--short HEAD"}, opts)
  local commit_hash = selected[1]:match("[^ ]+")
  if utils.input("Checkout commit " .. commit_hash .. "? [y/n] ") == "y" then
    local current_commit = utils.io_systemlist(cmd_cur_commit)
    if(commit_hash == current_commit) then return end
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
  local cmd = path.git_cwd({"git", "add", "--"}, opts)
  git_exec(selected, opts, cmd)
end

M.git_unstage = function(selected, opts)
  local cmd = path.git_cwd({"git", "reset", "--"}, opts)
  git_exec(selected, opts, cmd)
end

M.git_reset = function(selected, opts)
  local cmd = path.git_cwd({"git", "checkout", "HEAD", "--"}, opts)
  git_exec(selected, opts, cmd)
end

M.git_stash_drop = function(selected, opts)
  local cmd = path.git_cwd({"git", "stash", "drop"}, opts)
  git_exec(selected, opts, cmd)
end

M.git_stash_pop = function(selected, opts)
  if utils.input("Pop " .. #selected .. " stash(es)? [y/n] ") == "y" then
    local cmd = path.git_cwd({"git", "stash", "pop"}, opts)
    git_exec(selected, opts, cmd)
    vim.cmd("e!")
  end
end

M.git_stash_apply = function(selected, opts)
  if utils.input("Apply " .. #selected .. " stash(es)? [y/n] ") == "y" then
    local cmd = path.git_cwd({"git", "stash", "apply"}, opts)
    git_exec(selected, opts, cmd)
    vim.cmd("e!")
  end
end

M.git_buf_edit = function(selected, opts)
  local cmd = path.git_cwd({"git", "show"}, opts)
  local git_root = path.git_root(opts, true)
  local win = vim.api.nvim_get_current_win()
  local buffer_filetype = vim.bo.filetype
  local file = path.relative(vim.fn.expand("%:p"), git_root)
  local commit_hash = selected[1]:match("[^ ]+")
  table.insert(cmd, commit_hash .. ":" .. file)
  local git_file_contents = utils.io_systemlist(cmd)
  local buf = vim.api.nvim_create_buf(true, true)
  local file_name = string.gsub(file,"$","[" .. commit_hash .. "]")
  vim.api.nvim_buf_set_lines(buf,0,0,true,git_file_contents)
  vim.api.nvim_buf_set_name(buf,file_name)
  vim.api.nvim_buf_set_option(buf, 'buftype', 'nofile')
  vim.api.nvim_buf_set_option(buf, 'bufhidden', 'wipe')
  vim.api.nvim_buf_set_option(buf, 'filetype', buffer_filetype)
  vim.api.nvim_buf_set_option(buf, 'modifiable', false)
  vim.api.nvim_win_set_buf(win, buf)
end

M.git_buf_tabedit = function(selected, opts)
  vim.cmd('tab split')
  M.git_buf_edit(selected, opts)
end

M.git_buf_split = function(selected, opts)
  vim.cmd('split')
  M.git_buf_edit(selected, opts)
end

M.git_buf_vsplit = function(selected, opts)
  vim.cmd('vsplit')
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

  -- 'FNCREF' is set only on 'M.live_grep' calls
  -- 'MODULE' is set on 'M.grep' and 'live_grep' calls
  assert(opts.__MODULE__
    and type(opts.__MODULE__.grep) == 'function'
    or type(opts.__MODULE__.live_grep) == 'function')

  local o = vim.tbl_extend("keep", {
      search = false,
      continue_last_search = true,
      continue_last_search_default = '',
      rg_glob = opts.rg_glob or opts.__call_opts.rg_glob,
      -- globs always require command processing with 'multiprocess'
      requires_processing = opts.rg_glob or opts.__call_opts.rg_glob,
    }, opts.__call_opts or {})

  if opts.__FNCREF__ then
    opts.__MODULE__.grep(o)
  else
    opts.__MODULE__.live_grep(o)
  end
end

return M
