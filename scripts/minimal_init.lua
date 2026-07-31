---@diagnostic disable: param-type-mismatch
local __FILE__ = assert(debug.getinfo(1, "S")).source:gsub("^@", "")
local dir = vim.fn.fnamemodify(vim.fn.resolve(__FILE__), ":h:h:p")
-- Add current directory to 'runtimepath' to be able to use 'lua' files
vim.opt.runtimepath:append(dir)

-- Vendored 'mini.test' lives under fzf-lua's own source tree. Prepend its
-- root to runtimepath AND `package.path` so that `require('mini.test')` resolves
-- to the copy we ship in-tree instead of any external installation. Both
-- channels are needed because a `-u` script cannot trigger Neovim's startup
-- `runtimepath` -> `package.path` rebuild.
local vendor_root = vim.fs.joinpath(dir, "lua", "fzf-lua", "test", "vendor")
vim.opt.runtimepath:prepend(vendor_root)
package.path = vendor_root .. "/?.lua;" .. vendor_root .. "/?/init.lua;" .. package.path

-- 'mini.nvim' is still cloned into `deps/mini.nvim` by `make deps`. We append
-- (rather than prepend) so the vendored 'mini.test' above still wins for
-- `require('mini.test')`. The clone exists to provide `mini.icons` for the
-- icons-aware specs (`files_spec`, `headless_spec`, `minicons_spec`).
vim.opt.runtimepath:append(vim.fs.joinpath(dir, "deps", "mini.nvim"))
vim.opt.runtimepath:append(vim.fs.joinpath(vim.fn.stdpath("data"), "lazy", "mini.nvim"))

vim.env.FZF_DEFAULT_OPTS = nil
vim.env.FZF_DEFAULT_OPTS_FILE = nil
vim.env.FZF_DEFAULT_COMMAND = nil
vim.env.FZF_API_KEY = nil
vim.env.LC_ALL = "C"

-- make _G.FzfLua usable in test (e.g. headless_spec.lua)
require("fzf-lua")
