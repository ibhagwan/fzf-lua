---@diagnostic disable: param-type-mismatch
local __FILE__ = assert(debug.getinfo(1, "S")).source:gsub("^@", "")
local dir = vim.fn.fnamemodify(vim.fn.resolve(__FILE__), ":h:h:p")
-- Add current directory to 'runtimepath' to be able to use 'lua' files
vim.opt.runtimepath:append(dir)

-- 'mini.nvim' is still cloned into `deps/mini.nvim` by `make deps`. We append
-- it to runtimepath purely to make `mini.icons` available for the icons-aware
-- specs (`files_spec`, `headless_spec`, `minicons_spec`). The harness's own
-- test framework lives under `lua/fzf-lua/test/mini/` and is loaded from
-- fzf-lua's own runtimepath, which is searched before the deps clone.
vim.opt.runtimepath:append(vim.fs.joinpath(dir, "deps", "mini.nvim"))
vim.opt.runtimepath:append(vim.fs.joinpath(vim.fn.stdpath("data"), "lazy", "mini.nvim"))

vim.env.FZF_DEFAULT_OPTS = nil
vim.env.FZF_DEFAULT_OPTS_FILE = nil
vim.env.FZF_DEFAULT_COMMAND = nil
vim.env.FZF_API_KEY = nil
vim.env.LC_ALL = "C"

-- make _G.FzfLua usable in test (e.g. headless_spec.lua)
require("fzf-lua")
