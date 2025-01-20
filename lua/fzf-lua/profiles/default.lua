return {
  desc = "fzf-lua default options",
  -- Defaults to picker info in win title if neovim version >= 0.9, prompt otherwise
  require("fzf-lua").utils.__HAS_NVIM_09 and "default-title" or "default-prompt"
}
