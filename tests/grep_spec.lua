---@diagnostic disable: unused-local, unused-function
local MiniTest = require("mini.test")
local helpers = require("fzf-lua.test.helpers")
local child = helpers.new_child_neovim()
local expect, eq = helpers.expect, helpers.expect.equality
local new_set = MiniTest.new_set
local exec_lua = child.lua

local T = helpers.new_set_with_child(child)

T["grep"] = new_set({ n_retry = not helpers.IS_LINUX() and 5 or nil })

T["grep"]["search"] = new_set()

T["grep"]["search"]["regex"] = new_set({ parametrize = { { false }, { true } } }, {
  function(multiprocess)
    local screen_opts = {
      -- Ignore prompt containing our search string (different on win)
      -- Debug output command is different on Windows due to ^ escapes
      ignore_text = helpers.IS_WIN() and { 4, 6, 9, 10, 12, 18, 28 } or { 28 },
      normalize_paths = helpers.IS_WIN()
    }
    local path = vim.fs.joinpath(vim.fn.stdpath("data"), "lazy", "nvim-web-devicons")
    if not vim.uv.fs_stat(path) then
      path = vim.fs.joinpath("deps", "nvim-web-devicons")
    end
    exec_lua("vim.opt.runtimepath:append(...)", { path })
    exec_lua([[require("nvim-web-devicons").setup({})]])
    helpers.FzfLua.grep(child, {
      __expect_lines = true,
      __screen_opts = screen_opts,
      search = [===[(~'"\/$?'`*&&||;[]<>) --tests/grep*]===],
      debug = 1,
      silent = true,
      hidden = false,
      file_icons = true,
      multiprocess = multiprocess,
      fzf_opts = { ["--wrap"] = true },
      winopts = { preview = { scrollbar = false } },
      previewer = "builtin",
      __after_open = function()
        -- Verify previewer "last_entry" was set
        child.type_keys("<c-j>")
        child.wait_until(function()
          return child.lua_get([[FzfLua.utils.fzf_winobj()._previewer.last_entry]])
              :match(string.format(" tests%sgrep_spec.lua:32:21:",
                helpers.IS_WIN() and [[\]] or [[/]])) ~= nil
        end)
      end,
    })
  end,
})

return T
