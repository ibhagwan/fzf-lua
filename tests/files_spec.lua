---@diagnostic disable: unused-local, unused-function
local MiniTest = require("mini.test")
local helpers = require("fzf-lua.test.helpers")
local child = helpers.new_child_neovim()
local expect, eq = helpers.expect, helpers.expect.equality
local new_set = MiniTest.new_set
local exec_lua = child.lua

-- Helpers with child processes
--stylua: ignore start
---@format disable-next
local reload = function(config) child.unload(); child.setup(config) end
local set_cursor = function(...) return child.set_cursor(...) end
local get_cursor = function(...) return child.get_cursor(...) end
local set_lines = function(...) return child.set_lines(...) end
local get_lines = function(...) return child.get_lines(...) end
local type_keys = function(...) return child.type_keys(...) end
local sleep = function(ms) helpers.sleep(ms, child) end
--stylua: ignore end

local T = helpers.new_set_with_child(child)

T["files"] = new_set({ n_retry = not helpers.IS_LINUX() and 5 or nil })

T["files"]["close|abort"] = new_set({ parametrize = { { "<esc>" }, { "<c-c>" } } }, {
  function(key)
    -- sort produces different output on Windows, ignore the mismatch
    helpers.FzfLua.files(child, {
      __abort_key = key,
      __expect_lines = true,
      debug = 1,
      hidden = false,
      previewer = false,
      cwd_prompt = false,
      multiprocess = true,
      cmd = "rg --files --sort=path -g !tests/**",
    })
  end,
})

T["files"]["multiprocess"] = new_set({ parametrize = { { false }, { true } } }, {
  function(multiprocess)
    helpers.FzfLua.files(child, {
      __expect_lines = true,
      __postprocess_wait = true,
      debug = 1,
      hidden = false,
      previewer = false,
      cwd_prompt = false,
      multiprocess = multiprocess,
      -- Test file_ignore_patterns instead of rg filter
      file_ignore_patterns = { "^tests" },
      cmd = "rg --files --sort=path",
      -- cmd = "rg --files --sort=path -g !tests/**",
    })
  end,
})

T["files"]["previewer"] = new_set({ parametrize = { { false }, { true } } })

T["files"]["previewer"]["builtin"] = new_set({ parametrize = { { "ci" }, { "builtin" } } }, {
  function(icons, previewer)
    if icons then
      local path = vim.fs.joinpath(vim.fn.stdpath("data"), "lazy", "mini.nvim")
      if not vim.uv.fs_stat(path) then
        path = vim.fs.joinpath("deps", "mini.nvim")
      end
      exec_lua("vim.opt.runtimepath:append(...)", { path })
      exec_lua([[require("mini.icons").setup({})]])
    end
    helpers.FzfLua.files(child, {
      __expect_lines = true,
      __screen_opts = helpers.IS_WIN()
          -- Ignore debug command due to ^! escape sequence on Win
          and { ignore_text = { 6, 28 }, normalize_paths = true } or nil,
      debug = 1,
      hidden = false,
      file_icons = icons,
      cwd_prompt = false,
      multiprocess = true,
      cmd = "rg --files --sort=path -g !tests/**",
      winopts = { preview = { scrollbar = false } },
      previewer = previewer == "builtin"
          and "builtin"
          or [[require('fzf-lua.test.previewer')]],
      __after_open = function()
        -- Verify previewer "last_entry" was set
        child.type_keys("<c-j>")
        child.wait_until(function()
          return exec_lua([[return FzfLua.utils.fzf_winobj()._previewer.last_entry]]) ==
              (icons and " LICENSE" or "LICENSE")
        end)
      end,
    })
  end,
})

T["files"]["icons"] = new_set({ parametrize = { { "devicons" }, { "mini" } } })

T["files"]["icons"]["defaults"] = new_set({ parametrize = { { "+attrs" }, { "-attrs" } } }, {
  function(icons, attrs)
    attrs = attrs == "+attrs" and true or false
    if attrs then helpers.SKIP_IF_WIN() end
    local plugin = icons == "mini" and "mini.nvim" or "nvim-web-devicons"
    local path = vim.fs.joinpath(vim.fn.stdpath("data"), "lazy", plugin)
    if not vim.uv.fs_stat(path) then
      path = vim.fs.joinpath("deps", plugin)
    end
    exec_lua("vim.opt.runtimepath:append(...)", { path })
    exec_lua(([[require("%s").setup({})]]):format(icons == "mini" and "mini.icons" or plugin))
    helpers.FzfLua.files(child, {
      __expect_lines = not attrs,
      hidden = false,
      previewer = false,
      cwd_prompt = false,
      file_icons = icons,
      -- Test file_ignore_patterns instead of rg filter
      file_ignore_patterns = { "^tests" },
      cmd = "rg --files --sort=path",
      -- cmd = "rg --files --sort=path -g !tests/**",
    })
  end,
})

T["files"]["executable"] = new_set({ parametrize = { { "fd" }, { "rg" }, { "find|dir" } } }, {
  function(exec)
    -- Ignore last "-- TERMINAL --" line and "[DEBUG]" line containing the cmd
    local screen_opts = { ignore_text = { 6, 28 }, normalize_paths = helpers.IS_WIN() }
    local opts, exclude
    if exec == "fd" then
      exclude = "{}"
      opts = {
        fd_opts = "--color=never --type f --type l --exclude .git --exclude tests | sort" }
    elseif exec == "rg" then
      exclude = [[{ "fd", "fdfind" }]]
      opts = { rg_opts = '--files -g "!.git" --sort=path -g !tests/**' }
    else
      exclude = [[{ "fd", "fdfind", "rg" }]]
      opts = {
        find_opts =
        [[-type f \! -path '*/.git/*' \! -path '*/doc/tags' \! -path '*/deps/*' ! -path '*/tests/*'| sort]],
        dir_opts =
        [[/s/b/a:-d | findstr -v "\.git\\" | findstr -v "doc\\tags" | findstr -v "deps" | findstr -v "tests" | sort]],
        strip_cwd_prefix = true
      }
    end
    -- sort produces different output on Windows, ignore the mismatch
    if exec ~= "rg" and helpers.IS_WIN() then
      for i = 18, 21 do
        table.insert(screen_opts.ignore_text, i)
      end
    end
    exec_lua(([[
      _G._exec = vim.fn.executable
      vim.fn.executable = function(x)
        if vim.tbl_contains(%s, x) then return 0 end
        return _G._exec(x)
      end
    ]]):format(exclude))
    helpers.FzfLua.files(child, vim.tbl_extend("keep", opts, {
      __expect_lines = true,
      __screen_opts = screen_opts,
      debug = 1,
      previewer = false,
      cwd_prompt = false,
      multiprocess = true, -- force mp for "[DEBUG]" line
    }))
  end,
})

T["files"]["preview should work after chdir #1864"] = function()
  -- Ignore last "-- TERMINAL --" line and "[DEBUG]" line containing the cmd
  local screen_opts = { ignore_text = { 6, 28 }, normalize_paths = helpers.IS_WIN() }
  helpers.FzfLua.files(child, {
    __expect_lines = true,
    __screen_opts = screen_opts,
    cmd = "rg --files --sort=path -g !tests/**",
    hidden = false,
    cwd_prompt = false,
    previewer = "builtin",
    winopts = { preview = { hidden = false } },
    __after_open = function()
      exec_lua([[vim.cmd.cd("./tests")]])
      child.type_keys([[<c-n>]])
      sleep(100)
    end
  })
end

T["files"]["nop on nothing match"] = function()
  reload({ "hide" })
  local ctx = exec_lua([[return FzfLua.utils.CTX()]])
  for _, key in ipairs({ "<cr>", "<c-t>" }) do
    exec_lua([[FzfLua.files { query = ("%s is nop on nothing match"):format(...) }]], { key })
    child.wait_until(function() return exec_lua([[return _G._fzf_load_called]]) == true end)
    child.type_keys(key)
    child.wait_until(function() return exec_lua([[return _G._fzf_lua_on_create]]) == vim.NIL end)
    eq(ctx, exec_lua([[return FzfLua.utils.CTX()]]))
  end
end

return T
