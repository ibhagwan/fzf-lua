---@diagnostic disable: param-type-mismatch
local __FILE__ = assert(debug.getinfo(1, "S")).source:gsub("^@", "")
local dir = vim.fn.fnamemodify(vim.fn.resolve(__FILE__), ":h:h:p")
-- Add current directory to 'runtimepath' to be able to use 'lua' files
vim.opt.runtimepath:append(dir)

-- Set up 'mini.test' only when calling headless Neovim (like with `make test`)
if #vim.api.nvim_list_uis() == 0 then
  -- Add 'mini.nvim' to 'runtimepath' to be able to use 'mini.test'
  -- Assumed that 'mini.nvim' is downloaded by 'lazy.nvim'
  vim.opt.runtimepath:append(vim.fs.joinpath(dir, "deps", "mini.nvim"))
  vim.opt.runtimepath:append(vim.fs.joinpath(vim.fn.stdpath("data"), "lazy", "mini.nvim"))
end

vim.env.FZF_DEFAULT_OPTS = nil
vim.env.FZF_DEFAULT_OPTS_FILE = nil
vim.env.FZF_DEFAULT_COMMAND = nil
vim.env.FZF_API_KEY = nil
vim.env.LC_ALL = "C"
