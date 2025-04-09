-- This file should only be loaded from the headless instance
local uv = vim.uv or vim.loop
assert(#vim.api.nvim_list_uis() == 0)

-- path to this file
local __FILE__ = debug.getinfo(1, "S").source:gsub("^@", "")

-- add the current folder to package.path so we can 'require'
-- prepend this folder first, so our modules always get first
-- priority over some unknown random module with the same name
package.path = ("%s/?.lua;"):format(vim.fn.fnamemodify(__FILE__, ":h:h")) .. package.path

-- due to 'os.exit' neovim doesn't delete the temporary
-- directory, save it so we can delete prior to exit (#329)
-- NOTE: opted to delete the temp dir at the start due to:
--   (1) spawn_stdio doesn't need a temp directory
--   (2) avoid dangling temp dirs on process kill (i.e. live_grep)
local tmpdir = vim.fn.fnamemodify(vim.fn.tempname(), ":h")
if tmpdir and #tmpdir > 0 then
  -- io.stdout:write(string.format("[DEBUG] tmpdir=%s\n", tmpdir))
  -- _G.dump(vim.uv.fs_stat(tmpdir))
  vim.fn.delete(tmpdir, "rf")
end

-- neovim might also automatically start the RPC server which will
-- generate a named pipe temp file, e.g. `/run/user/1000/nvim.14249.0`
-- we don't need the server in the headless "child" process, stopping
-- the server also deletes the temp file
if vim.v.servername and #vim.v.servername > 0 then
  pcall(vim.fn.serverstop, vim.v.servername)
end

-- global var indicating a headless instance
_G._fzf_lua_is_headless = true
local _, pid = require("fzf-lua.libuv").spawn_stdio(loadstring(_G.arg[1])())
-- while vim.uv.run() do end -- os.exit in spawn_stdio
while uv.os_getpriority(pid) do
  vim.wait(100, function() return uv.os_getpriority(pid) == nil end)
end
