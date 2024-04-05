if vim.g.loaded_fzf_lua == 1 then return end
vim.g.loaded_fzf_lua = 1

-- Should never be called, below nvim 0.7 "plugin/fzf-lua.vim"
-- sets `vim.g.loaded_fzf_lua=1`
if vim.fn.has("nvim-0.7") ~= 1 then
  vim.api.nvim_err_writeln("Fzf-lua minimum requirement is Neovim versions 0.5")
  return
end

vim.api.nvim_create_user_command("FzfLua", function(opts)
  require("fzf-lua.cmd").run_command(unpack(opts.fargs))
end, {
  nargs = "*",
  range = true,
  complete = function(_, line)
    -- Workaround to trigger cmp completion at `keyword_length=0`
    -- doesn't work properly, causes the 2nd+ completion to not
    -- get called until an additional space is pressed
    -- https://github.com/hrsh7th/nvim-cmp/discussions/1885
    -- print("called", #line, line, line:match("%s+$") ~= nil)
    -- if require("fzf-lua.cmp_src")._registered then
    --   require("fzf-lua.cmp_src")._complete()
    -- end
    return require("fzf-lua.cmd")._candidates(line)
  end,
})

-- If available register as nvim-cmp source
local ok, _ = pcall(require, "cmp")
if ok then
  require("fzf-lua.cmp_src")._register_cmdline()
end
