local is_windows = vim.fn.has("win32") == 1

-- modified version of:
-- https://github.com/vijaymarupudi/nvim-fzf/blob/master/action_helper.lua
local uv = vim.loop

local PathSeparator = vim.fn.has('win32') > 0 and "\\" or "/"
local LogPath = vim.fn.stdpath('data') .. PathSeparator .. "fzf-lua-shell-helper.log"

local function log_info(fmt, ...)
    local messages = string.format(fmt, ...)
    local split_messages = vim.split(messages, "\n")
    local fp = io.open(LogPath, "a")
    if fp then
        for _, line in ipairs(split_messages) do
            fp:write(
                string.format( "%s: %s\n", os.date("%Y-%m-%d %H:%M:%S"), line)
            )
        end
        fp:close()
    end
end

local function get_temporary_pipe_name()
  if is_windows then
    local random_filename = string.gsub(vim.fn.tempname(), "/", "")
    random_filename = string.gsub(random_filename, "\\", "")
    return ([[\\.\pipe\%s]]):format(random_filename)
  else
    return vim.fn.tempname()
  end
end

local function get_preview_socket()
  local tmp = get_temporary_pipe_name()
  local socket = uv.new_pipe(false)
  uv.pipe_bind(socket, tmp)
  return socket, tmp
end

local preview_socket, preview_socket_path = get_preview_socket()

uv.listen(preview_socket, 100, function(_)
  local preview_receive_socket = uv.new_pipe(false)
  -- start listening
  uv.accept(preview_socket, preview_receive_socket)
  preview_receive_socket:read_start(function(err, data)
    assert(not err)
    if not data then
      uv.close(preview_receive_socket)
      uv.close(preview_socket)
      vim.schedule(function()
        vim.cmd [[qall]]
      end)
      return
    end
    io.write(data)
  end)
end)


local function rpc_nvim_exec_lua(opts)
  local success, errmsg = pcall(function()
    -- fzf selection is unpacked as the argument list
    local fzf_selection = {}
    for i = 1, vim.fn.argc() do
      table.insert(fzf_selection, vim.fn.argv(i - 1))
    end
    -- for skim compatibility
    local preview_lines = vim.env.FZF_PREVIEW_LINES or vim.env.LINES
    local preview_cols = vim.env.FZF_PREVIEW_COLUMNS or vim.env.COLUMNS
    if is_windows then
      local chan_id = vim.fn.sockconnect("tcp", opts.fzf_lua_server, { rpc = true })
      log_info("[shell_helper|rpc_nvim_exec_lua] chan_id(%s):%s, opts(%s):%s", type(chan_id), vim.inspect(chan_id), type(opts), vim.inspect(opts))
    else
      local chan_id = vim.fn.sockconnect("pipe", opts.fzf_lua_server, { rpc = true })
    end
    vim.rpcrequest(chan_id, "nvim_exec_lua", [[
      local luaargs = {...}
      local function_id = luaargs[1]
      local preview_socket_path = luaargs[2]
      local fzf_selection = luaargs[3]
      local fzf_lines = luaargs[4]
      local fzf_columns = luaargs[5]
      local usr_func = require"fzf-lua.shell".get_func(function_id)
      log_info("[shell_helper|rpc_nvim_exec_lua.rpcrequest] chan_id(%s):%s, luaargs(%s):%s", type(chan_id), vim.inspect(chan_id), type(luaargs), vim.inspect(luaargs))
      return usr_func(preview_socket_path, fzf_selection, fzf_lines, fzf_columns)
    ]], {
      opts.fnc_id,
      preview_socket_path,
      fzf_selection,
      tonumber(preview_lines),
      tonumber(preview_cols)
    })
    vim.fn.chanclose(chan_id)
  end)

  if not success or opts.debug then
    io.stderr:write(("[DEBUG]\tdebug = %s\n"):format(opts.debug))
    io.stderr:write(("[DEBUG]\tfunction ID = %d\n"):format(opts.fnc_id))
    io.stderr:write(("[DEBUG]\tfzf_lua_server = %s\n"):format(opts.fzf_lua_server))
    for i = 1, #vim.v.argv do
      io.stderr:write(("[DEBUG]\targv[%d] = %s\n"):format(i, vim.v.argv[i]))
    end
    for i = 1, vim.fn.argc() do
      io.stderr:write(("[DEBUG]\targ[%d] = %s\n"):format(i, vim.fn.argv(i - 1)))
    end
  end

  if not success then
    io.stderr:write(("FzfLua Error: %s\n"):format(errmsg or "<null>"))
    vim.cmd [[qall]]
  end
end

return {
  rpc_nvim_exec_lua = rpc_nvim_exec_lua
}
