return {
  desc = "fzf-native with no git|files icons",
  winopts = { preview = { default = "bat" } },
  manpages = { previewer = "man_native" },
  helptags = { previewer = "help_native" },
  defaults = { git_icons = false, file_icons = false },
  lsp = { code_actions = { previewer = "codeaction_native" } },
  tags = { previewer = "bat" },
  btags = { previewer = "bat" },
  files = { fzf_opts = { ["--ansi"] = false } },
  grep = {
    fzf_opts  = { ["--ansi"] = false },
    grep_opts = require("fzf-lua.utils").is_darwin()
        and "--color=never --binary-files=without-match --line-number --recursive --extended-regexp -e"
        or "--color=never --binary-files=without-match --line-number --recursive --perl-regexp -e",
    rg_opts   =
    " --color=never --column --line-number --no-heading --smart-case --max-columns=4096 -e",
  },
}
