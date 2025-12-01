return {
  -- inherit window titles, will be converted to fzf border-label
  { "default-title" },
  desc = "fzf-native run inside a tmux popup",
  fzf_opts = {
    ["--gutter"] = " ",
    ["--border"] = "rounded",
    ["--border-label-pos"] = "4",
    ["--tmux"] = "center,80%,60%"
  },
  winopts = {
    preview = {
      default = "bat",
      border = function(_, m)
        assert(m.type == "fzf")
        if FzfLua.utils.has(m.opts, "fzf", { 0, 63 }) then
          return "border-line"
        else
          return "border-sharp"
        end
      end
    }
  },
  previewers = {
    bat = { args = "--color=always --style=full" },
    bat_native = { args = "--color=always --style=full" },
  },
  manpages = { previewer = "man_native" },
  helptags = { previewer = "help_native" },
  undotree = { previewer = "undo_native" },
  lsp = { code_actions = { previewer = "codeaction_native" } },
  tags = { previewer = "bat" },
  btags = { previewer = "bat" },
  lines = { _treesitter = false },
  blines = { _treesitter = false },
}
