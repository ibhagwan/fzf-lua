-- add temp path from scripts/mini.sh in case this is running locally
local tempdir = vim.fn.system('sh -c "dirname $(mktemp -u)"')
local packpath = os.getenv("PACKPATH") or tempdir .. "/fzf-lua.tmp/nvim/site"
vim.cmd("set packpath=" .. packpath)

require'fzf-lua'.setup {
  grep = { git_icons = false },
  files = { git_icons = false },
}

vim.api.nvim_set_keymap('n', '<C-k>', '<Cmd>lua require"fzf-lua".builtin()<CR>', {})
vim.api.nvim_set_keymap('n', '<C-p>', '<Cmd>lua require"fzf-lua".files()<CR>', {})
vim.api.nvim_set_keymap('n', '<F1>',  '<Cmd>lua require"fzf-lua".help_tags()<CR>', {})
