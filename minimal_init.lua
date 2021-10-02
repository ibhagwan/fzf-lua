if vim.api.nvim_call_function('has', {'nvim-0.5'}) ~= 1 then
  vim.api.nvim_command('echohl WarningMsg | echom "Fzf-lua requires neovim > v0.5 | echohl None"')
  return
end

local res, packer = pcall(require, "packer")
local install_suffix = "/site/pack/packer/%s/packer.nvim"
local install_path = vim.fn.stdpath("data") .. string.format(install_suffix, "opt")
local is_installed = vim.loop.fs_stat(install_path) ~= nil

if not res and is_installed then
  vim.cmd("packadd packer.nvim")
  res, packer = pcall(require, "packer")
end

if not res then
  print("Downloading packer.nvim...\n")
  vim.fn.system({
    "git", "clone", '--depth', '1',
    "https://github.com/wbthomason/packer.nvim",
    install_path,
  })
  vim.cmd("packadd packer.nvim")
  res, packer = pcall(require, "packer")
  if res then
    vim.fn.delete(packer.config.compile_path, "rf")
    print("Successfully installed packer.nvim.")
  else
    print(("Error installing packer.nvim\nPath: %s"):format(install_path))
    return
  end
end

packer.startup({function(use)
  use { 'wbthomason/packer.nvim', opt = true }
  use { 'ibhagwan/fzf-lua',
    requires = { 'vijaymarupudi/nvim-fzf' },
    config = function()
      vim.api.nvim_set_keymap('n', '<C-p>',
        '<Esc>:lua require"fzf-lua".files()<CR>', {})
      require'fzf-lua'.setup({})
    end,
  }
end})

if not vim.loop.fs_stat(packer.config.compile_path) then
  packer.sync()
else
  packer.compile()
end
