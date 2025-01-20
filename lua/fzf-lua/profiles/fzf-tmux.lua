return {
  { "default-prompt" }, -- base profile
  desc = "fzf-native run inside a tmux popup",
  fzf_opts = { ["--border"] = "rounded", ["--tmux"] = "center,80%,60%" },
  winopts = { preview = { default = "bat" } },
  manpages = { previewer = "man_native" },
  helptags = { previewer = "help_native" },
  lsp = { code_actions = { previewer = "codeaction_native" } },
  tags = { previewer = "bat" },
  btags = { previewer = "bat" },
  lines = { _treesitter = false },
  blines = { _treesitter = false },
}
