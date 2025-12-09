---@diagnostic disable-next-line: deprecated
local api, uv, fn = vim.api, vim.uv or vim.loop, vim.fn
assert(#api.nvim_list_uis() == 0)
local __FILE__ = debug.getinfo(1, "S").source:gsub("^@", "")
local dir = fn.fnamemodify(fn.resolve(__FILE__), ":h:h:p")
vim.opt.rtp:append(dir)
vim.cmd.runtime("plugin/fzf-lua.lua")
local path = require("fzf-lua.path")
-- append icon plugin to rtp, only the first found is loaded
local data = fn.stdpath("data") --[[@as string]]
for _, plug in ipairs({ "nvim-web-devicons", "mini.nvim" }) do
  local found
  for _, parts in ipairs({
    { data, "site", "pack", plug, "opt" },
    { data, "site", "pack", plug, "start" },
    { data, "lazy", plug },
    { dir,  "deps", plug }
  }) do
    if not found then
      local ppath = path.join(parts)
      if uv.fs_stat(ppath) then
        found = true
        vim.opt.rtp:append(ppath)
      end
    end
  end
end
vim.o.swapfile = false
vim.o.showmode = false
vim.o.showcmd = false
if vim.v.servername and #vim.v.servername > 0 then
  pcall(fn.serverstop, vim.v.servername)
end

require("fzf-lua").setup({ "cli" })

-- load user config
local xdg = vim.env.XDG_CONFIG_HOME or path.join({ vim.env.HOME, ".config" })
local config_paths = {
  path.join({ xdg, "fzf-lua.lua" }),
  path.join({ xdg, "fzf-lua", "init.lua" }),
  path.join({ xdg, "fzf-lua", "config.lua" }),
}
for _, config_path in ipairs(config_paths) do
  if uv.fs_stat(config_path) then
    dofile(config_path)
    break
  end
end

_G.fzf_jobstart = function(cmd, opts)
  FzfLua.libuv.uv_spawn(cmd[1], {
      cwd = opts.cwd,
      args = vim.list_slice(cmd, 2),
      stdio = { 0 },
      env = opts.env,
    },
    vim.schedule_wrap(function(rc)
      opts.on_exit(nil, rc, nil)
      if not opts.no_quit and #api.nvim_get_proc_children(fn.getpid()) == 0 then
        vim.cmd.cquit { count = rc, bang = true }
      end
    end))
end

require("fzf-lua.cmd").run_command(unpack(_G.arg))

while true do
  vim.wait(100)
end
