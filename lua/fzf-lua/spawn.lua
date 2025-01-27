-- This file should only be loaded from the headless instance
assert(#vim.api.nvim_list_uis() == 0)

-- When running CI tests there's a bug on Windows which adds a space after the runtime
-- path, this will subsequently cause `vim.filetype.match` to fail  when it attempts to
--`require("vim.filetype.detect")` which will fail our custom `path.ft_match`. This will
-- fail mini.icons UI tests as any icon that requires the use of `vim.filetype.match`
-- will return a default icon
local VIMRUNTIME = os.getenv("VIMRUNTIME")
if VIMRUNTIME and VIMRUNTIME:match("%s$") then
  vim.opt.runtimepath:prepend(vim.trim(VIMRUNTIME))
  -- package.path = ("%s/lua/?.lua;"):format(vim.trim(VIMRUNTIME)) .. package.path
end

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

return { spawn_stdio = require("fzf-lua.libuv").spawn_stdio }
