local api, uv, fn = vim.api, vim.uv or vim.loop, vim.fn
assert(#api.nvim_list_uis() == 0)
_G._is_fzf_cli = true
local __FILE__ = debug.getinfo(1, "S").source:gsub("^@", "")
local dir = fn.fnamemodify(fn.resolve(__FILE__), ":h:h:p")
vim.opt.rtp:append(dir)
vim.opt.rtp:append(require("fzf-lua.path").join({ dir, "deps", "nvim-web-devicons" }))
vim.o.swapfile = false
vim.o.showmode = false
vim.o.showcmd = false

require("fzf-lua").setup({ vim.env.TMUX and "fzf-tmux" or "fzf-native" })

api.nvim_create_autocmd("Signal", {
  callback = function(ev)
    vim.tbl_map(function(pid)
      FzfLua.libuv.process_kill(pid, ev.match)
    end, api.nvim_get_proc_children(uv.os_getpid()))
  end
})

local quit = function()
  -- os.exit()
  if vim.v.servername and #vim.v.servername > 0 then
    pcall(fn.serverstop, vim.v.servername)
  end
  vim.cmd.quit()
end

(FzfLua[_G.arg[#_G.arg] or vim.v.argv[#vim.v.argv] or "files"] or FzfLua.files)({
      file_icons = true,
      fzf_opts = { ["--height"] = "50%" },
      -- winopts = { preview = { flip_columns = 100 } },
      keymap = { fzf = { ["ctrl-q"] = "toggle-all" } },
      actions = {
        esc = quit,
        ["ctrl-c"] = quit,
        -- nvim --headless -i NONE -nu scripts/cli.lua live_grep
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
    })

while true do
  vim.wait(0)
end
