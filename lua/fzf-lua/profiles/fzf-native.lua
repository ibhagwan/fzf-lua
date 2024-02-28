return {
  desc = "fzf with `bat` as native previewer",
  winopts = { preview = { default = "bat" } },
  manpages = { previewer = "man_native" },
  helptags = { previewer = "help_native" },
  lsp = { code_actions = { previewer = "codeaction_native" } },
  tags = { previewer = "bat" },
  btags = { previewer = "bat" },
}
