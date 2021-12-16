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
  local action, entries = M.normalize_selected(actions, selected)
  if actions[action] then
    actions[action](entries, opts)
  end
end

M.vimcmd = function(vimcmd, selected)
  for i = 1, #selected do
    vim.cmd(vimcmd .. " " .. vim.fn.fnameescape(selected[i]))
  end
end

M.vimcmd_file = function(vimcmd, selected, opts)
  local curbuf = vim.api.nvim_buf_get_name(0)
  for i = 1, #selected do
    local entry = path.entry_to_file(selected[i])
    entry.ctag = path.entry_to_ctag(selected[i])
    -- Java LSP entries, 'jdt://...'
    if entry.uri then
      vim.cmd("normal! m`")
      vim.lsp.util.jump_to_location(entry)
      vim.cmd("norm! zvzz")
    else
      -- only change buffer if we need to (issue #122)
      local fullpath = entry.path
      if not path.starts_with_separator(fullpath) then
        fullpath = path.join({opts.cwd or vim.loop.cwd(), fullpath})
      end
      if vimcmd == 'e' and curbuf ~= fullpath
         and not vim.o.hidden and
         utils.buffer_is_dirty(nil, true) then
         -- warn the user when trying to switch from a dirty buffer
         -- when `:set nohidden`
         return
      end
      -- add current location to jumplist
      vim.cmd("normal! m`")
      if vimcmd ~= "e" or curbuf ~= fullpath then
        vim.cmd(vimcmd .. " " .. vim.fn.fnameescape(entry.path))
      end
      if entry.ctag or entry.line>1 or entry.col>1 then
        if entry.line>1 or entry.col>1 then
          vim.api.nvim_win_set_cursor(0, {tonumber(entry.line), tonumber(entry.col)-1})
        else
          vim.api.nvim_win_set_cursor(0, {1, 0})
          vim.fn.search(entry.ctag, "W")
        end
        vim.cmd("norm! zvzz")
      end
    end
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
    -- check if the file contains line
    local file, line, col, text = selected[i]:match("^([^ :]+):(%d+):(%d+):(.*)")
    if file and line and col then
      table.insert(qf_list, {filename = file, lnum = line, col = col, text = text})
    else
      table.insert(qf_list, {filename = selected[i], lnum = 1, col = 1})
    end
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

-- buffer actions
M.vimcmd_buf = function(vimcmd, selected, _)
  for i = 1, #selected do
    local bufnr = string.match(selected[i], "%[(%d+)")
    if vimcmd == 'b'
      and not vim.o.hidden and
      utils.buffer_is_dirty(nil, true) then
      -- warn the user when trying to switch from a dirty buffer
      -- when `:set nohidden`
      return
    end
    vim.cmd(vimcmd .. " " .. bufnr)
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

M.colorscheme = function(selected)
  local colorscheme = selected[1]
  vim.cmd("colorscheme " .. colorscheme)
end

M.run_builtin = function(selected)
  local method = selected[1]
  vim.cmd(string.format("lua require'fzf-lua'.%s()", method))
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
  local has_mode_nt = not vim.tbl_isempty(
    vim.fn.getcompletion('ModeChanged', 'event'))
    or vim.fn.has('nvim-0.6') == 1
  if has_mode_nt then
    local mode = vim.api.nvim_get_mode()
    local wininfo = vim.fn.getwininfo(vim.api.nvim_get_current_win())[1]
    if vim.bo.ft == 'fzf'
      and wininfo.terminal == 1
      and mode and mode.mode == 't' then
      vim.cmd[[noautocmd lua vim.api.nvim_feedkeys('i', 'n', true)]]
    end
  end
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
    print(entry)
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
  M.vimcmd(vimcmd, selected)
end

M.help_vert = function(selected)
  local vimcmd = "vert help"
  M.vimcmd(vimcmd, selected)
end

M.help_tab = function(selected)
  local vimcmd = "tab help"
  M.vimcmd(vimcmd, selected)
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
  local cmd = path.git_cwd({"git", "checkout"}, opts.cwd)
  local git_ver = utils.git_version()
  -- git switch was added with git version 2.23
  if git_ver and git_ver >= 2.23 then
    cmd = path.git_cwd({"git", "switch"}, opts.cwd)
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
  local cmd_checkout = path.git_cwd({"git", "checkout"}, opts.cwd)
  local cmd_cur_commit = path.git_cwd({"git", "rev-parse", "--short HEAD"}, opts.cwd)
  local commit_hash = selected[1]:match("[^ ]+")
  if vim.fn.input("Checkout commit " .. commit_hash .. "? [y/n] ") == "y" then
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

M.git_buf_edit = function(selected, opts)
  local cmd = path.git_cwd({"git", "show"}, opts.cwd)
  local git_root = path.git_root(opts.cwd, true)
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

return M
