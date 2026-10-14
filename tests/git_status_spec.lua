---@diagnostic disable: unused-local, unused-function, unused
local MiniTest = require("mini.test")
local helpers = require("fzf-lua.test.helpers")
local child = helpers.new_child_neovim()
local eq = helpers.expect.equality
local new_set = MiniTest.new_set
local exec_lua = child.lua
local sleep = function(ms) helpers.sleep(ms, child) end

local repo ---@type string?
local orig_cwd ---@type string?

local T = helpers.new_set_with_child(child, {
  hooks = {
    pre_case = function()
      orig_cwd = child.fn.getcwd()
      repo = exec_lua([[
        local dir = vim.fn.tempname()
        vim.fn.mkdir(dir, "p")
        -- Initialize repo and disable signing so commits work even when the
        -- environment has SSH signing configured and the key does not exist.
        vim.fn.system({ "git", "init", dir })
        vim.fn.system({ "git", "-C", dir, "config", "user.email", "test@fzf-lua" })
        vim.fn.system({ "git", "-C", dir, "config", "user.name", "fzf-lua test" })
        vim.fn.system({ "git", "-C", dir, "config", "commit.gpgsign", "false" })
        vim.fn.system({ "git", "-C", dir, "config", "gpg.format", "openpgp" })
        local file = dir .. "/tracked.txt"
        local fd = io.open(file, "w")
        fd:write("hello\n")
        fd:close()
        vim.fn.system({ "git", "-C", dir, "add", "tracked.txt" })
        vim.fn.system({ "git", "-C", dir, "commit", "--no-gpg-sign", "-m", "initial" })
        return dir
      ]])
      child.cmd("cd " .. vim.fn.fnameescape(assert(repo)))
    end,
    post_case = function()
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

T["git_status"] = new_set({ n_retry = not helpers.IS_LINUX() and 5 or nil })

T["git_status"]["stage unstage reset"] = function()
  -- Modify a tracked file so git_status shows an unstaged change.
  exec_lua([[
    local file = vim.fn.getcwd() .. "/tracked.txt"
    local fd = io.open(file, "a")
    fd:write("-- useless comment\n")
    fd:close()
  ]])

  -- Auto-confirm the reset dialog so the headless test does not block.
  exec_lua([[FzfLua.utils.confirm = function() return 1 end]])

  helpers.FzfLua.git_status(child, {
    __no_abort = true,
    __expect_lines = true,
    __screen_opts = { ignore_text = { 28 } },
    previewer = false,
    headers = false,
    multiprocess = false,
    __after_open = function()
      -- Screenshot: unstaged modification (M on the right)
      sleep(100)
      if helpers.IS_WIN() then sleep(250) end
      child.expect_screen_lines({ ignore_text = { 28 } })

      -- Stage with left: M should move to the staged (left) column.
      exec_lua([[_G._fzf_load_called = nil]])
      child.type_keys("<Left>")
      sleep(100)
      if helpers.IS_WIN() then sleep(250) end
      child.wait_until(function() return exec_lua([[return _G._fzf_load_called]]) == true end)
      child.expect_screen_lines({ ignore_text = { 28 } })

      -- Unstage with right: M should return to the unstaged (right) column.
      exec_lua([[_G._fzf_load_called = nil]])
      child.type_keys("<Right>")
      sleep(100)
      if helpers.IS_WIN() then sleep(250) end
      child.wait_until(function() return exec_lua([[return _G._fzf_load_called]]) == true end)
      child.expect_screen_lines({ ignore_text = { 28 } })

      -- Reset with ctrl-x: file is restored and the picker reloads empty.
      exec_lua([[_G._fzf_load_called = nil]])
      child.type_keys("<c-x>")
      sleep(100)
      if helpers.IS_WIN() then sleep(250) end
      child.wait_until(function() return exec_lua([[return _G._fzf_load_called]]) == true end)
    end,
  })

  -- Close the picker.
  child.type_keys("<c-c>")
  child.wait_until(function() return exec_lua([[return _G._fzf_lua_on_create]]) == vim.NIL end)

  -- Verify the working tree is clean after reset.
  eq("", exec_lua([[
    return vim.fn.system({ "git", "-C", vim.fn.getcwd(), "status", "--porcelain" })
      :gsub("%s+$", "")
  ]]))

  -- Commit the clean state, ignoring any SSH/GPG signing configuration.
  exec_lua([[
    vim.fn.system({
      "git", "-C", vim.fn.getcwd(), "commit", "--allow-empty", "--no-gpg-sign",
      "-m", "git_status test end",
    })
  ]])
end

return T
