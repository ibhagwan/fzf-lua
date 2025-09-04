return {
  desc = "fzf-lua defaults with `sk` as binary",
  fzf_bin = "zf",
  defaults = {
    pipe_cmd = true,
    compat_warn = false,
    fzf_cli_args = "--preview 'cat {}'",
  },
}
