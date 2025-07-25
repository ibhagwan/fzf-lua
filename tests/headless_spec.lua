---@diagnostic disable: unused-local, unused-function
local MiniTest = require("mini.test")
local helpers = require("fzf-lua.test.helpers")
local child = helpers.new_child_neovim()
local expect, eq = helpers.expect, helpers.expect.equality
local new_set = MiniTest.new_set
local exec_lua = child.lua

local _mini_path = vim.fs.joinpath(vim.fn.stdpath("data"), "lazy", "mini.nvim")
if not vim.uv.fs_stat(_mini_path) then
  _mini_path = vim.fs.joinpath("deps", "mini.nvim")
end

local _devicons_path = vim.fs.joinpath(vim.fn.stdpath("data"), "lazy", "nvim-web-devicons")
if not vim.uv.fs_stat(_devicons_path) then
  _devicons_path = vim.fs.joinpath("deps", "nvim-web-devicons")
end

local T = helpers.new_set_with_child(child, {
  hooks = {
    pre_case = function()
      child.o.shell = "/bin/sh"
      child.o.termguicolors = true
      child.o.background = "dark"
      exec_lua([[M = { devicons = require("fzf-lua.devicons") }]])
    end,
  },
})

T["headless"] = new_set({})

T["headless"]["file_icons"] = new_set()

local exec_term = function(c, cmd, args)
  cmd = cmd or {}
  args = args or {}
  args.term = true
  local serpent = require "fzf-lua.lib.serpent"
  cmd = serpent.block(cmd, { comment = false, sortkeys = false })
  args = serpent.block(args, { comment = false, sortkeys = false })
  local id = c.lua_get(string.format("vim.fn.jobstart(%s, %s)", cmd, args))
  eq(tonumber(id) > 0, true)
  c.lua(string.format("vim.fn.jobwait({%s})", tostring(id)))
  c.wait_until(function()
    local lines = c.get_lines()
    for i = #lines, 1, -1 do
      if lines[i] == "" then
        table.remove(lines, i)
      end
    end
    return lines[#lines] == "[Process exited 0]"
  end)
end

T["headless"]["file_icons"]["devicons - manual"] = new_set({ parametrize = { { false }, { true } } },
  {
    function(icons)
      helpers.SKIP_IF_WIN()
      -- helpers.SKIP_IF_NOT_LINUX()
      exec_term(child,
        { "./scripts/headless_fd.sh", "-x", "rg --files --sort=path", "-f", tostring(icons) })
      child.expect_screenshot({ ignore_text = { 24 }, ignore_attr = { 25 } })
    end,
  })

T["headless"]["file_icons"]["server"] = new_set({ parametrize = { { "devicons" }, { "mini" } } }, {
  function(icons)
    helpers.SKIP_IF_WIN()
    -- helpers.SKIP_IF_NOT_LINUX()
    if icons == "mini" then
      exec_lua("vim.opt.runtimepath:append(...)", { _mini_path })
      exec_lua([[require("mini.icons").setup({})]])
    else
      exec_lua("vim.opt.runtimepath:append(...)", { _devicons_path })
      exec_lua([[ require("nvim-web-devicons").setup({})]])
    end
    exec_lua([[M.devicons.load()]])
    eq(child.lua_get([[M.devicons.plugin_name()]]), icons)
    local fzf_lua_server = child.lua_get("vim.g.fzf_lua_server")
    eq(#fzf_lua_server > 0, true)
    local new_child = helpers.new_child_neovim()
    new_child.start()
    exec_term(new_child,
      { "./scripts/headless_fd.sh", "-x", "rg --files --sort=path", "-f", icons },
      { env = { ["FZF_LUA_SERVER"] = fzf_lua_server } })
    -- Ignore script path and attr the next line
    new_child.expect_screenshot({ ignore_text = { 23 }, ignore_attr = { 24 } })
  end,
})

return T
