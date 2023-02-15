return {
  desc = "fzf-native with no git|files icons",
  winopts = { preview = { default = "bat" } },
  manpages = { previewer = "man_native" },
  helptags = { previewer = "help_native" },
  tags = { previewer = "bat" },
  btags = { previewer = "bat" },
  files = { fzf_opts = { ["--ansi"] = false } },
  global_git_icons = false,
  global_file_icons = false,
}
