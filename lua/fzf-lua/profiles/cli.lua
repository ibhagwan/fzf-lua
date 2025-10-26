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
        if ffi and #entries == 1 then
          posix_exec(fn.exepath("nvim"), entries[1].path,
            entries[1].line and ("+" .. entries[1].line) or nil,
            entries[1].col and ("+norm! %s|"):format(entries[1].col) or nil)
        elseif ffi and #entries > 1 then
          local file = fn.tempname()
          vim.fn.writefile(vim.tbl_map(function(e) -- Format: {filename}:{lnum}:{col}: {text}
            local text = e.stripped:match(":%d+:%d?%d?%d?%d?:?(.*)$") or ""
            return ("%s:%d:%d: %s"):format(e.path, e.line or 1, e.col or 1, text)
          end, entries), file)
          posix_exec(fn.exepath("nvim"), "-q", file)
        end
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
