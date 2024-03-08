vim.opt.hidden = true
vim.opt.swapfile = false

vim.opt.runtimepath:append("../plenary.nvim")
vim.opt.runtimepath:append("../fzf-lua")
vim.cmd("runtime! plugin/plenary.vim")
