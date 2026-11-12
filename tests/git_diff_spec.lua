---@diagnostic disable: unused-local, unused-function, unused
local MiniTest = require("mini.test")
local helpers = require("fzf-lua.test.helpers")
local child = helpers.new_child_neovim()
local eq = helpers.expect.equality
local new_set = MiniTest.new_set
local exec_lua = child.lua

local repo ---@type string?
local orig_cwd ---@type string?
local orig_shell ---@type string?
local orig_env_shell ---@type string?

local T = helpers.new_set_with_child(child, {
  hooks = {
    pre_case = function()
      orig_cwd = child.fn.getcwd()
      orig_shell = child.o.shell
      orig_env_shell = child.env.SHELL
      repo = exec_lua(
        [[
        local dir = vim.fn.tempname()
        vim.fn.mkdir(dir .. "/(dir)", "p")
        -- Initialize repo and disable signing so commits work even when the
        -- environment has SSH signing configured and the key does not exist.
        vim.fn.system({ "git", "init", dir })
        vim.fn.system({ "git", "-C", dir, "config", "user.email", "test@fzf-lua" })
        vim.fn.system({ "git", "-C", dir, "config", "user.name", "fzf-lua test" })
        vim.fn.system({ "git", "-C", dir, "config", "commit.gpgsign", "false" })
        vim.fn.system({ "git", "-C", dir, "config", "gpg.format", "openpgp" })
        local file = dir .. "/(dir)/file.tsx"
        local fd = io.open(file, "w")
        fd:write("one\n")
        fd:close()
        vim.fn.system({ "git", "-C", dir, "add", "." })
        vim.fn.system({ "git", "-C", dir, "commit", "--no-gpg-sign", "-m", "initial" })
        -- Modify the tracked file so git_diff shows a preview.
        fd = io.open(file, "a")
        fd:write("two\n")
        fd:close()
        return dir
      ]]
      )
      child.cmd("cd " .. vim.fn.fnameescape(assert(repo)))
    end,
    post_case = function()
      child.o.shell = orig_shell
      child.env.SHELL = orig_env_shell
      if repo then
        -- Return child to the original working directory before deleting repo.
        child.cmd("cd " .. vim.fn.fnameescape(assert(orig_cwd)))
        -- Only clear the reference if deletion succeeded.
        eq(0, vim.fn.delete(repo, "rf"))
        repo = nil
        orig_cwd = nil
      end
    end,
  },
})

T["git_diff"] = new_set({ n_retry = not helpers.IS_LINUX() and 5 or nil })

-- Regression test for #2846: preview commands for paths with shell special
-- characters (e.g. parentheses) must not break when the shell is fish.
T["git_diff"]["preview with special chars in fish"] = function()
  helpers.SKIP_IF_WIN()

  -- Prefer a real fish shell, but CI images do not install fish. A POSIX sh
  -- symlink named "fish" still exercises the fish-only preview wrapping path.
  local fish = child.fn.executable("fish") == 1 and child.fn.exepath("fish")
    or exec_lua(
      [[
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, "p")
    local link = dir .. "/fish"
    assert(vim.uv.fs_symlink(vim.fn.exepath("sh"), link))
    return link
  ]]
    )

  child.o.shell = fish
  child.env.SHELL = fish

  helpers.FzfLua.git_diff(child, {
    -- Keep the preview output deterministic (raw git diff, no delta pager).
    preview_pager = false,
    __no_abort = true,
    __expect_lines = false,
    __after_open = function()
      child.wait_until_screenshot_text_match("diff --git a/(dir)/file.tsx")
      local screen = tostring(child.get_screenshot())
      helpers.expect.no_match(screen, "[Ss]yntax error")
    end,
  })

  -- Close the picker.
  child.type_keys("<c-c>")
  child.wait_until(function() return exec_lua([[return _G._fzf_lua_on_create]]) == vim.NIL end)
end

return T
