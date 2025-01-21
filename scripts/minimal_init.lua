-- Add current directory to 'runtimepath' to be able to use 'lua' files
vim.opt.runtimepath:append(vim.uv.cwd())

-- Set up 'mini.test' only when calling headless Neovim (like with `make test`)
if #vim.api.nvim_list_uis() == 0 then
  -- Add 'mini.nvim' to 'runtimepath' to be able to use 'mini.test'
  -- Assumed that 'mini.nvim' is downloaded by 'lazy.nvim'
  vim.opt.runtimepath:append(vim.fn.stdpath("data") .. "/lazy/mini.nvim")

  -- Add fzf-lua (local & lazy)
  vim.opt.runtimepath:append(vim.fn.stdpath("data") .. "/lazy/fzf-lua")
  vim.opt.runtimepath:append("../fzf-lua")

  -- Set up 'mini.test'
  require("mini.test").setup({
    collect = {
      find_files = function()
        return vim.fn.globpath("tests", "**/*_spec.lua", true, true)
      end,
    },
  })
end
