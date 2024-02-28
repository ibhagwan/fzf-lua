return {
  desc = "fzf-native with no git|files icons",
  winopts = { preview = { default = "bat" } },
  manpages = { previewer = "man_native" },
  helptags = { previewer = "help_native" },
  lsp = { code_actions = { previewer = "codeaction_native" } },
  tags = { previewer = "bat" },
  btags = { previewer = "bat" },
  files = { fzf_opts = { ["--ansi"] = false } },
  defaults = {
    git_icons = false,
    file_icons = false,
  },
}
