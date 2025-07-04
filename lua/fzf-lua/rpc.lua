-- modified version of:
-- https://github.com/vijaymarupudi/nvim-fzf/blob/master/action_helper.lua
local uv = vim.uv or vim.loop

local _is_win = vim.fn.has("win32") == 1 or vim.fn.has("win64") == 1

if vim.v.servername and #vim.v.servername > 0 then
  pcall(vim.fn.serverstop, vim.v.servername)
end

---@return string
local function windows_pipename()
  local tmpname = vim.fn.tempname()
  tmpname = string.gsub(tmpname, "\\", "")
  return ([[\\.\pipe\%s]]):format(tmpname)
end

local function get_preview_socket()
  local tmp = _is_win and windows_pipename() or vim.fn.tempname()
  local socket = uv.new_pipe(false)
  uv.pipe_bind(socket, tmp)
  return socket, tmp
end

local preview_socket, preview_socket_path = get_preview_socket()

local preview_receive_socket
uv.listen(preview_socket, 1, function(_)
  preview_receive_socket = uv.new_pipe(false)
  uv.accept(preview_socket, preview_receive_socket)

  -- Avoid dangling temp dir on premature process kills (live grep)
  -- see more complete note in spawn.lua
  if not _is_win then
    uv.fs_unlink(preview_socket_path)
    local tmpdir = vim.fn.fnamemodify(preview_socket_path, ":h")
    if tmpdir and #tmpdir > 0 then uv.fs_rmdir(tmpdir) end
  end

  preview_receive_socket:read_start(function(err, data)
    assert(not err)
    if not data then
      uv.close(preview_receive_socket)
      uv.close(preview_socket)
      -- on windows: ci fail when use uv.stop()
      -- on linux: zero event can freeze https://github.com/ibhagwan/fzf-lua/pull/1955#issuecomment-2785474217
      -- uv.stop()
      os.exit(0)
      return
    end
    io.write(data)
  end)
end)

local rpc_nvim_exec_lua = function(opts)
  local success, errmsg = pcall(function()
    -- for skim compatibility
    local preview_lines = vim.env.FZF_PREVIEW_LINES or vim.env.LINES
    local preview_cols = vim.env.FZF_PREVIEW_COLUMNS or vim.env.COLUMNS
    local chan_id = vim.fn.sockconnect("pipe", opts.fzf_lua_server, { rpc = true })
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
      opts.fnc_id,
      preview_socket_path,
      opts.fzf_selection,
      tonumber(preview_lines),
      tonumber(preview_cols),
    })
    vim.fn.chanclose(chan_id)
  end)

  if not success or opts.debug then
    io.stderr:write(("[DEBUG] debug = %s\n"):format(opts.debug))
    io.stderr:write(("[DEBUG] function ID = %d\n"):format(opts.fnc_id))
    io.stderr:write(("[DEBUG] fzf_lua_server = %s\n"):format(opts.fzf_lua_server))
    for i, v in pairs(_G.arg) do
      io.stderr:write(("[DEBUG] argv[%d] = %s\n"):format(i, v))
    end
    for _, var in ipairs({ "LINES", "COLUMNS" }) do
      io.stderr:write(("[DEBUG] $%s = %s\n"):format(var, os.getenv(var) or "<null>"))
    end
  end

  if not success then
    io.stderr:write(("FzfLua Error: %s\n"):format(errmsg or "<null>"))
    os.exit(1)
  end

  uv.run("once")
  uv.run() -- noreturn, quit by os.exit
end

local args = vim.deepcopy(_G.arg)
args[0] = nil -- remove filename
local opts = {
  fnc_id = tonumber(table.remove(args, 1)),
  debug = table.remove(args, 1) == "true",
  fzf_selection = args,
  fzf_lua_server = vim.env.FZF_LUA_SERVER or vim.env.SKIM_FZF_LUA_SERVER or vim.env.NVIM,
}
rpc_nvim_exec_lua(opts)
