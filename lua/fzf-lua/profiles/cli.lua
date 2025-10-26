local function quit() vim.cmd.quit() end

return {
  { os.getenv("TMUX") and "fzf-tmux" or "fzf-native", },
  desc = "run in shell cmdline",
  fzf_opts = { ["--height"] = "50%" },
  actions = {
    files = {
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
    }
  },
}
