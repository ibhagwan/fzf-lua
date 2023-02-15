return {
  desc = "fzf-native run inside a tmux popup",
  fzf_bin = "fzf-tmux",
  fzf_opts = { ["--border"] = "rounded" },
  fzf_tmux_opts = { ["-p"] = "80%,90%" },
  winopts = { preview = { default = "bat", layout = "horizontal" } },
  manpages = { previewer = "man_native" },
  helptags = { previewer = "help_native" },
  tags = { previewer = "bat" },
  btags = { previewer = "bat" },
}
