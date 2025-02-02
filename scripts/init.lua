-- add temp path from scripts/mini.sh in case this is running locally
local tempdir = vim.trim(vim.fn.system([[sh -c "dirname $(mktemp -u)"]]))
local packpath = os.getenv("PACKPATH") or tempdir .. "/fzf-lua.tmp/nvim/site"
vim.cmd("set packpath+=" .. packpath)

vim.o.termguicolors = true

require "fzf-lua".setup { defaults = { git_icons = false } }

vim.api.nvim_set_keymap("n", "<C-\\>", [[<Cmd>lua require"fzf-lua".buffers()<CR>]], {})
vim.api.nvim_set_keymap("n", "<C-k>", [[<Cmd>lua require"fzf-lua".builtin()<CR>]], {})
vim.api.nvim_set_keymap("n", "<C-p>", [[<Cmd>lua require"fzf-lua".files()<CR>]], {})
vim.api.nvim_set_keymap("n", "<C-l>", [[<Cmd>lua require"fzf-lua".live_grep_glob()<CR>]], {})
vim.api.nvim_set_keymap("n", "<C-g>", [[<Cmd>lua require"fzf-lua".grep_project()<CR>]], {})
vim.api.nvim_set_keymap("n", "<F1>", [[<Cmd>lua require"fzf-lua".help_tags()<CR>]], {})

require("fzf-lua").utils.info(
  "|<C-\\> buffers|<C-p> files|<C-g> grep|<C-l> live grep|<C-k> builtin|<F1> help|")
