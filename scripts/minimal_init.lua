-- Add current directory to 'runtimepath' to be able to use 'lua' files
vim.opt.runtimepath:append(vim.uv.cwd())

-- Set up 'mini.test' only when calling headless Neovim (like with `make test`)
if #vim.api.nvim_list_uis() == 0 then
  -- Add 'mini.nvim' to 'runtimepath' to be able to use 'mini.test'
  -- Assumed that 'mini.nvim' is downloaded by 'lazy.nvim'
  vim.opt.runtimepath:append(vim.fs.joinpath("deps", "mini.nvim"))
  vim.opt.runtimepath:append(vim.fs.joinpath(vim.fn.stdpath("data"), "lazy", "mini.nvim"))

  -- Add fzf-lua (lazy)
  vim.opt.runtimepath:append(vim.fs.joinpath("deps", "fzf-lua"))
  vim.opt.runtimepath:append(vim.fs.joinpath(vim.fn.stdpath("data"), "lazy", "fzf-lua"))
end
