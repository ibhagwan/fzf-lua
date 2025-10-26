local api, uv, fn = vim.api, vim.uv or vim.loop, vim.fn
assert(#api.nvim_list_uis() == 0)
_G._is_fzf_cli = true
local __FILE__ = debug.getinfo(1, "S").source:gsub("^@", "")
local dir = fn.fnamemodify(fn.resolve(__FILE__), ":h:h:p")
vim.opt.rtp:append(dir)
local path = require("fzf-lua.path")
vim.opt.rtp:append(path.join({ dir, "deps", "nvim-web-devicons" }))
vim.o.swapfile = false
vim.o.showmode = false
vim.o.showcmd = false
if vim.v.servername and #vim.v.servername > 0 then
  pcall(fn.serverstop, vim.v.servername)
end

local quit = function() vim.cmd.quit() end

api.nvim_create_autocmd("Signal", {
  callback = function(ev)
    vim.tbl_map(function(pid)
      FzfLua.libuv.process_kill(pid, ev.match)
    end, api.nvim_get_proc_children(uv.os_getpid()))
  end
})

require("fzf-lua").setup({
  vim.env.TMUX and "fzf-tmux" or "fzf-native",
  defaults = {
    fzf_opts = { ["--height"] = "50%" },
    keymap = { fzf = { ["ctrl-q"] = "toggle-all" } },
    actions = {
      esc = quit,
      ["ctrl-c"] = quit,
      enter = function(s, o)
        local entries = vim.tbl_map(
          function(e) return FzfLua.path.entry_to_file(e, o) end, s)
        io.stdout:write(vim.json.encode(entries) .. "\n")
        quit()
      end,
      ["ctrl-x"] = function(_, o)
        FzfLua.builtin(vim.tbl_deep_extend("force", o.__call_opts, {
          actions = {
            enter = function(s)
              if not s[1] then quit() end
              FzfLua[s[1]](o.__call_opts)
            end
          },
        }))
      end
    },
  }
})

-- load user config
local xdg = vim.env.XDG_CONFIG_HOME or path.join({ vim.env.HOME, ".config" })
local config_paths = { path.join({ xdg, "fzf-lua.lua" }), path.join({ xdg, "fzf-lua", "init.lua" }) }
for _, config_path in ipairs(config_paths) do
  if uv.fs_stat(config_path) then
    dofile(config_path)
    break
  end
end

_G.fzf_jobstart = function(cmd, opts)
  ---@diagnostic disable-next-line: missing-fields, missing-parameter
  FzfLua.libuv.uv_spawn(cmd[1], {
      cwd = opts.cwd,
      args = vim.list_slice(cmd, 2),
      stdio = { 0 },
      env = opts.env,
    },
    vim.schedule_wrap(function(rc)
      opts.on_exit(nil, rc, nil)
      if not opts.no_quit and #vim.api.nvim_get_proc_children(uv.os_getpid()) == 0 then
        vim.cmd.cquit { count = rc, bang = true }
      end
    end))
end

-- TODO: parse cli args
(FzfLua[_G.arg[#_G.arg] or vim.v.argv[#vim.v.argv] or "files"] or FzfLua.files)()

while true do
  vim.wait(0)
end
