-- modified version of:
-- https://github.com/vijaymarupudi/nvim-fzf/blob/master/action_helper.lua
local uv = vim.loop

local function get_preview_socket()
  local tmp = vim.fn.tempname()
  local socket = uv.new_pipe(false)
  uv.pipe_bind(socket, tmp)
  return socket, tmp
end

local preview_socket, preview_socket_path = get_preview_socket()

uv.listen(preview_socket, 100, function(err)
  local preview_receive_socket = uv.new_pipe(false)
  -- start listening
  uv.accept(preview_socket, preview_receive_socket)
  preview_receive_socket:read_start(function(err, data)
    assert(not err)
    if not data then
      uv.close(preview_receive_socket)
      uv.close(preview_socket)
      vim.schedule(function()
        vim.cmd[[qall]]
      end)
      return
    end
    io.write(data)
  end)
end)


local function_id = tonumber(vim.fn.argv(1))
local success, errmsg = pcall(function ()
  local nargs = vim.fn.argc()
  local args = {}
  -- this is guaranteed to be 2 or more, we are interested in those greater than 2
  for i=3,nargs do
    -- vim uses zero indexing
    table.insert(args, vim.fn.argv(i - 1))
  end
  local environ = vim.fn.environ()
  local chan_id = vim.fn.sockconnect("pipe", vim.fn.argv(0), { rpc = true })
  -- for skim compatibility
  local preview_lines = environ.FZF_PREVIEW_LINES or environ.LINES
  local preview_cols = environ.FZF_PREVIEW_COLUMNS or environ.COLUMNS
  vim.rpcrequest(chan_id, "nvim_exec_lua", [[
    local luaargs = {...}
    local function_id = luaargs[1]
    local preview_socket_path = luaargs[2]
    local fzf_selection = luaargs[3]
    local fzf_lines = luaargs[4]
    local fzf_columns = luaargs[5]
    local usr_func = require"fzf-lua.shell".get_func(function_id)
    return usr_func(preview_socket_path, fzf_selection, fzf_lines, fzf_columns)
  ]], {
    function_id,
    preview_socket_path,
    args,
    tonumber(preview_lines),
    tonumber(preview_cols)
  })
  vim.fn.chanclose(chan_id)
end)

if not success then
  io.stderr:write("FzfLua Error:\n\n" .. errmsg .. "\n")
  vim.cmd [[qall]]
end
