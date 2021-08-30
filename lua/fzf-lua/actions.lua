local utils = require "fzf-lua.utils"
local path = require "fzf-lua.path"

local M = {}

-- return fzf '--expect=' string from actions keyval tbl
M.expect = function(actions)
  if not actions then return '' end
  local keys = {}
  for k, v in pairs(actions) do
    if k ~= "default" and v ~= false then
      table.insert(keys, k)
    end
  end
  if #keys > 0 then
    return string.format("--expect=%s", table.concat(keys, ','))
  end
  return nil
end

M.act = function(actions, selected)
  if not actions or not selected then return end
  local action = "default"
  -- if there are no actions besides default
  -- the table will contain the results directly
  -- otherwise 'selected[1]` will contain the keybind
  -- empty string in selected[1] represents default
  if #selected>1 and #selected[1]>0 then action = selected[1] end
  if actions[action] then
    actions[action](selected)
  end
end

M.vimcmd = function(vimcmd, selected)
  if not selected or #selected < 2 then return end
  for i = 2, #selected do
    vim.cmd(vimcmd .. " " .. vim.fn.fnameescape(selected[i]))
  end
end

M.vimcmd_file = function(vimcmd, selected)
  if not selected or #selected < 2 then return end
  for i = 2, #selected do
    -- check if the file contains line
    local file, line = selected[i]:match("^([^:]+):(%d+)")
    if file and line then
      vim.cmd(string.format("%s +%s %s", vimcmd, line, vim.fn.fnameescape(file)))
    else
      vim.cmd(vimcmd .. " " .. vim.fn.fnameescape(selected[i]))
    end
  end
end

-- file actions
M.file_edit = function(selected)
  local vimcmd = "e"
  M.vimcmd_file(vimcmd, selected)
end

M.file_split = function(selected)
  local vimcmd = "new"
  M.vimcmd_file(vimcmd, selected)
end

M.file_vsplit = function(selected)
  local vimcmd = "vnew"
  M.vimcmd_file(vimcmd, selected)
end

M.file_tabedit = function(selected)
  local vimcmd = "tabnew"
  M.vimcmd_file(vimcmd, selected)
end

M.file_open_in_background = function(selected)
  local vimcmd = "badd"
  M.vimcmd_file(vimcmd, selected)
end

M.file_sel_to_qf = function(selected)
  if not selected or #selected < 2 then return end
  local qf_list = {}
  for i = 2, #selected do
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

-- buffer actions
M.buf_edit = function(selected)
  local vimcmd = "b"
  M.vimcmd(vimcmd, selected)
end

M.buf_split = function(selected)
  local vimcmd = "split | b"
  M.vimcmd(vimcmd, selected)
end

M.buf_vsplit = function(selected)
  local vimcmd = "vertical split | b"
  M.vimcmd(vimcmd, selected)
end

M.buf_tabedit = function(selected)
  local vimcmd = "tab split | b"
  M.vimcmd(vimcmd, selected)
end

M.buf_del = function(selected)
  local vimcmd = "bd"
  M.vimcmd(vimcmd, selected)
end

M.colorscheme = function(selected)
  if not selected then return end
  local colorscheme = selected[1]
  if #selected>1 then colorscheme = selected[2] end
  vim.cmd("colorscheme " .. colorscheme)
end

M.run_builtin = function(selected)
  if not selected then return end
  local method = selected[1]
  if #selected>1 then method = selected[2] end
  vim.cmd(string.format("lua require'fzf-lua'.%s()", method))
end

M.ex_run = function(selected)
  if not selected then return end
  local cmd = selected[1]
  if #selected>1 then cmd = selected[2] end
  vim.cmd("stopinsert")
  vim.fn.feedkeys(string.format(":%s ", cmd))
end

M.search = function(selected)
  if not selected then return end
  local query = selected[1]
  if #selected>1 then query = selected[2] end
  vim.cmd("stopinsert")
  utils.feed_keys_termcodes(string.format("/%s<CR>", query))
end

M.goto_mark = function(selected)
  if not selected then return end
  local mark = selected[1]
  if #selected>1 then mark = selected[2] end
  mark = mark:match("[^ ]+")
  vim.cmd("stopinsert")
  vim.cmd("normal! '" .. mark)
  -- vim.fn.feedkeys(string.format("'%s", mark))
end

M.spell_apply = function(selected)
  if not selected then return end
  local word = selected[1]
  if #selected>1 then word = selected[2] end
  vim.cmd("normal! ciw" .. word)
  vim.cmd("stopinsert")
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


M.git_switch = function(selected)
  -- remove anything past space
  local branch = selected[1]:match("[^ ]+")
  -- do nothing for active branch
  if branch:find("%*") ~= nil then return end
  local args = ""
  if branch:find("/") ~= nil then args = "--detach " end
  local output = vim.fn.systemlist("git switch " .. args .. branch)
  if utils.shell_error() then
    utils.err(unpack(output))
  else
    utils.info(unpack(output))
    vim.cmd("edit!")
  end
end

M.git_checkout = function(selected)
  local commit_hash = selected[1]:match("[^ ]+")
  if vim.fn.input("Checkout commit " .. commit_hash .. "? [y/n] ") == "y" then
    local current_commit = vim.fn.systemlist("git rev-parse --short HEAD")
    if(commit_hash == current_commit) then return end
    local output = vim.fn.systemlist("git checkout " .. commit_hash)
    if utils.shell_error() then
      utils.err(unpack(output))
    else
      utils.info(unpack(output))
      vim.cmd("edit!")
    end
  end
end

M.git_buf_edit = function(selected)
  -- there's an empty string in position 1 for some reason?
  table.remove(selected,1)
  local win = vim.api.nvim_get_current_win()
  local buffer_filetype = vim.bo.filetype
  local file = path.relative(vim.fn.expand("%"), vim.loop.cwd())
  local commit_hash = selected[1]:match("[^ ]+")
  local git_file_contents = vim.fn.systemlist("git show " .. commit_hash .. ":" .. file)
  local buf = vim.api.nvim_create_buf(true, false)
  local file_name = string.gsub(file,"%.","[" .. commit_hash .. "]%.")
  vim.api.nvim_buf_set_lines(buf,0,0,true,git_file_contents)
  vim.api.nvim_buf_set_name(buf,file_name)
  vim.api.nvim_buf_set_option(buf, 'buftype', 'nofile')
  vim.api.nvim_buf_set_option(buf, 'bufhidden', 'wipe')
  vim.api.nvim_buf_set_option(buf, 'filetype',buffer_filetype)
  vim.api.nvim_win_set_buf(win, buf)
end

M.git_buf_tabedit = function(selected)
  vim.cmd('tab split')
  M.git_buf_edit(selected)
end

M.git_buf_split = function(selected)
  vim.cmd('split')
  M.git_buf_edit(selected)
end

M.git_buf_vsplit = function(selected)
  vim.cmd('vsplit')
  M.git_buf_edit(selected)
end

return M
