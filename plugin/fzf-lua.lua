if vim.g.loaded_fzf_lua == 1 then return end
vim.g.loaded_fzf_lua = 1

if vim.fn.has("nvim-0.9") ~= 1 then
  vim.notify("Fzf-lua requires neovim >= v0.9", vim.log.levels.ERROR, { title = "fzf-lua" })
  return
end

vim.api.nvim_create_user_command("FzfLua", function(opts)
  require("fzf-lua.cmd").run_command(unpack(opts.fargs))
end, {
  nargs = "*",
  range = true,
  complete = function(_, line)
    local cmp_src = require("fzf-lua.cmp_src")
    if package.loaded.cmp and not cmp_src._registered then
      cmp_src._register_cmdline()
    end
    -- Workaround to trigger cmp completion at `keyword_length=0`
    -- doesn't work properly, causes the 2nd+ completion to not
    -- get called until an additional space is pressed
    -- https://github.com/hrsh7th/nvim-cmp/discussions/1885
    -- print("called", #line, line, line:match("%s+$") ~= nil)
    -- if cmp_src._registered then
    --   cmp_src._complete()
    -- end
    return require("fzf-lua.cmd")._candidates(line)
  end,
})
