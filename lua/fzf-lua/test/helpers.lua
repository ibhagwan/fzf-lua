-- lcd so we can run current file even if cwd isn't fzf-lua
local __FILE__ = debug.getinfo(1, "S").source:gsub("^@", "")
vim.cmd.lcd(vim.fn.fnamemodify(__FILE__, ":p:h:h:h:h"))

local MiniTest = require("mini.test")
local screenshot = require("fzf-lua.test.screenshot")

local M = {}

-- Busted like expectations
M.assert = {
  is = {
    same = MiniTest.expect.equality,
    True = function(b) return MiniTest.expect.equality(b, true) end,
    False = function(b) return MiniTest.expect.equality(b, false) end,
  },
  are = {
    same = MiniTest.expect.equality,
    equal = MiniTest.expect.equality,
  },
}

M.NVIM_VERSION = function()
  if M._NVIM_VERSION == nil then
    local output = vim.api.nvim_exec2("version", { output = true }).output
    M._NVIM_VERSION = output:match("NVIM v(%d+%.%d+%.%d+)")
  end
  return M._NVIM_VERSION
end

local os_detect = {
  WIN = {
    name = "Windows",
    fn = function() return vim.fn.has("win32") == 1 or vim.fn.has("win64") == 1 end
  },
  MAC = { name = "MacOS", fn = function() return vim.fn.has("mac") == 1 end },
  LINUX = { name = "Linux", fn = function() return vim.fn.has("linux") == 1 end },
  STABLE = { name = "Neovim stable", fn = function() return M.NVIM_VERSION() == "0.11.1" end },
  NIGHTLY = { name = "Neovim nightly", fn = function() return vim.fn.has("nvim-0.12") == 1 end },
}

-- Creates M.IS_WIN(), M.IS_NOT_WIN(), M.SKIP_IF_WIN(), etc
for k, v in pairs(os_detect) do
  M["IS_" .. k] = function()
    local var = "_IS_" .. k
    if M[var] == nil then
      M[var] = v.fn()
    end
    return M[var]
  end
  M["IS_NOT_" .. k] = function()
    return not M["IS_" .. k]
  end
  M["SKIP_IF_" .. k] = function(msg)
    if M["IS_" .. k]() then
      MiniTest.skip(msg or string.format("Skip test on %s", v.name))
    end
  end
  M["SKIP_IF_NOT_" .. k] = function(msg)
    if not M["IS_" .. k]() then
      MiniTest.skip(msg or string.format("Skip test: not %s", v.name))
    end
  end
end

-- Add extra expectations
M.expect = vim.deepcopy(MiniTest.expect)

M.expect.match = MiniTest.new_expectation(
  "string matching",
  function(str, pattern) return str:find(pattern) ~= nil end,
  function(str, pattern)
    return string.format("Pattern: %s\nObserved string: %s", vim.inspect(pattern), str)
  end
)

M.expect.no_match = MiniTest.new_expectation(
  "no string matching",
  function(str, pattern) return str:find(pattern) == nil end,
  function(str, pattern)
    return string.format("Pattern: %s\nObserved string: %s", vim.inspect(pattern), str)
  end
)

M.make_partial_tbl = function(tbl, ref)
  local res = {}
  for k, v in pairs(ref) do
    res[k] = (type(tbl[k]) == "table" and type(v) == "table") and M.make_partial_tbl(tbl[k], v) or
        tbl[k]
  end
  for i = 1, #tbl do
    if ref[i] == nil then res[i] = tbl[i] end
  end
  return res
end

M.expect.equality_partial_tbl = MiniTest.new_expectation(
  "equality of tables only in reference fields",
  function(x, y)
    if type(x) == "table" and type(y) == "table" then x = M.make_partial_tbl(x, y) end
    return vim.deep_equal(x, y)
  end,
  function(x, y)
    return string.format("Left: %s\nRight: %s", vim.inspect(M.make_partial_tbl(x, y)),
      vim.inspect(y))
  end
)

-- Monkey-patch `MiniTest.new_child_neovim` with helpful wrappers
M.new_child_neovim = function()
  local child = MiniTest.new_child_neovim()

  local prevent_hanging = function(method)
    if not child.is_blocked() then return end

    local msg = string.format("Can not use `child.%s` because child process is blocked.", method)
    error(msg)
  end

  child.init = function()
    child.restart({ "-u", "scripts/minimal_init.lua" })

    -- Change initial buffer to be readonly. This not only increases execution
    -- speed, but more closely resembles manually opened Neovim.
    child.bo.readonly = false
  end

  --- Setup fzf-lua
  ---@param config? table, config table
  child.setup = function(config)
    local lua_cmd = ([[
      require("fzf-lua").setup(vim.tbl_deep_extend("keep", ..., {
        %s
        winopts = {
          on_create = function() _G._fzf_lua_on_create = true end,
          on_close = function()
            _G._fzf_lua_on_create = nil
            _G._fzf_postprocess_called = nil
            _G._fzf_load_called = nil
          end,
        },
        keymap = { fzf = {
          true,
          load = function() _G._fzf_load_called = true end,
        } }
      }))
    ]])
        -- using "FZF_DEFAULT_OPTS" hangs the command on the
        -- child process and the loading indicator never stops
        :format(M.IS_WIN() and "defaults = { pipe_cmd = true }," or "")
    child.lua(lua_cmd, { config or {} })
  end

  --- Unload fzf-lua and side effects
  child.unload = function()
    -- Unload Lua module
    child.lua([[_G.FzfLua = nil]])
    child.lua([[
      for k, v in pairs(package.loaded) do
        if k:match("^fzf%-lua") then
          package.loaded[k] = nil
        end
      end
    ]])

    -- Remove global vars
    for _, var in ipairs({ "server", "directory", "root" }) do
      child.g["fzf_lua_" .. var] = nil
    end

    -- Remove autocmd groups
    for _, group in ipairs({ "VimResized", "WinClosed" }) do
      if child.fn.exists("#FzfLua" .. group) == 1 then
        child.api.nvim_del_augroup_by_name("FzfLua" .. group)
      end
    end
  end

  child.set_lines = function(arr, start, finish)
    prevent_hanging("set_lines")

    if type(arr) == "string" then arr = vim.split(arr, "\n") end

    child.api.nvim_buf_set_lines(0, start or 0, finish or -1, false, arr)
  end

  child.get_lines = function(start, finish)
    prevent_hanging("get_lines")

    return child.api.nvim_buf_get_lines(0, start or 0, finish or -1, false)
  end

  child.set_cursor = function(line, column, win_id)
    prevent_hanging("set_cursor")

    child.api.nvim_win_set_cursor(win_id or 0, { line, column })
  end

  child.get_cursor = function(win_id)
    prevent_hanging("get_cursor")

    return child.api.nvim_win_get_cursor(win_id or 0)
  end

  child.set_size = function(lines, columns)
    prevent_hanging("set_size")

    if type(lines) == "number" then child.o.lines = lines end

    if type(columns) == "number" then child.o.columns = columns end
  end

  child.get_size = function()
    prevent_hanging("get_size")

    return { child.o.lines, child.o.columns }
  end

  --- Assert visual marks
  ---
  --- Useful to validate visual selection
  ---
  ---@param first number|table Table with start position or number to check linewise.
  ---@param last number|table Table with finish position or number to check linewise.
  ---@private
  child.expect_visual_marks = function(first, last)
    child.ensure_normal_mode()

    first = type(first) == "number" and { first, 0 } or first
    last = type(last) == "number" and { last, 2147483647 } or last

    MiniTest.expect.equality(child.api.nvim_buf_get_mark(0, "<"), first)
    MiniTest.expect.equality(child.api.nvim_buf_get_mark(0, ">"), last)
  end

  child.expect_screenshot = function(opts, path)
    opts = opts or {}
    local screenshot_opts = { redraw = opts.redraw }
    opts.redraw = nil
    opts.force = not not vim.env["update_screenshots"]
    MiniTest.expect.reference_screenshot(child.get_screenshot(screenshot_opts), path, opts)
  end

  ---@alias test.ScreenOpts { start_line: integer?, end_line: integer?, no_ruler: boolean?,
  ---normalize_paths: boolean?, redraw: boolean? }
  ---@param opts test.ScreenOpts
  child.get_screen_lines = function(opts)
    return screenshot.fromChildScreen(child, opts)
  end

  -- Expect screenshot without the "attrs" (highlights)
  child.expect_screen_lines = function(opts, path)
    opts = opts or {}
    ---@type test.ScreenOpts
    local screenshot_opts = {
      redraw = opts.redraw,
      normalize_paths = opts.normalize_paths,
      start_line = opts.start_line,
      end_line = opts.end_line,
      no_ruler = opts.no_ruler,
    }
    opts.redraw = nil
    opts.force = not not vim.env["update_screenshots"]
    screenshot.reference_screenshot(child.get_screen_lines(screenshot_opts), path, opts)
  end

  ---@param opts test.ScreenOpts
  child.get_buf_lines = function(buf, opts)
    return screenshot.fromChildBufLines(child, buf, opts)
  end

  child.expect_buflines = function(buf, opts, path)
    opts = opts or {}
    ---@type test.ScreenOpts
    local screenshot_opts = {
      redraw = opts.redraw,
      normalize_paths = opts.normalize_paths,
      start_line = opts.start_line,
      end_line = opts.end_line,
      no_ruler = opts.no_ruler,
    }
    opts.redraw = nil
    opts.force = not not vim.env["update_screenshots"]
    screenshot.reference_screenshot(child.get_buf_lines(buf, screenshot_opts), path, opts)
  end

  ---@param str string
  ---@param opts test.ScreenOpts
  child.assert_screen_lines = function(str, opts)
    opts = opts or {}
    -- we don't need this if we compare inline
    opts.no_ruler = true
    local lines = str and vim.split(str, "\n") or { "" }
    if #lines > 1 then lines[#lines] = nil end
    local screen_ref = screenshot.from_lines(lines, opts)
    local screen_obs = child.get_screen_lines(opts)
    screenshot.compare(screen_ref, screen_obs, opts)
  end

  local wait_timeout = (M.IS_LINUX() and 2000 or 5000)
  --- waits until condition fn evals to true, checking every interval ms
  --- times out at timeout ms
  ---@param condition fun(): boolean
  ---@param timeout? integer, defaults to 2000
  ---@param interval? integer, defaults to 100
  child.wait_until = function(condition, timeout, interval)
    local max = timeout or wait_timeout
    local inc = interval or 100
    for _ = 0, max, inc do
      if condition() then
        return
      else
        vim.uv.sleep(inc)
      end
    end

    error(string.format("Timed out waiting for condition after %d ms\n\n%s\n\n%s", max,
      tostring(child.cmd_capture("messages")),
      tostring(child.get_screenshot())
    ))
  end

  --- waits until child screenshot contains text
  ---@param text string
  child.wait_until_screenshot_text_match = function(text)
    child.wait_until(function()
      local screenshotText = tostring(child.get_screenshot())
      return string.find(screenshotText, text, 1, true) ~= nil
    end)
  end

  -- Poke child's event loop to make it up to date
  child.poke_eventloop = function() child.api.nvim_eval("1") end

  child.sleep = function(ms)
    vim.uv.sleep(math.max(ms, 1))
    child.poke_eventloop()
  end

  return child
end

M.new_set_with_child = function(child, opts, setup_opts)
  opts = opts or {}
  opts.hooks = opts.hooks or {}
  return MiniTest.new_set({
    hooks = {
      pre_once = function()
        if opts.hooks.pre_once then
          opts.hooks.pre_once()
        end
      end,
      pre_case = function()
        child.init()
        child.setup(setup_opts)

        -- Reasonable screen size
        child.set_size(28, 64)

        -- So we can read `:messages`
        child.o.cmdheight = 4

        -- Caller's opts
        if opts.hooks.pre_case then
          opts.hooks.pre_case()
        end
      end,
      post_case = function()
        if opts.hooks.post_case then
          opts.hooks.post_case()
        end
        pcall(child.unload) -- job may already die
      end,
      post_once = function()
        if opts.hooks.post_once then
          opts.hooks.post_once()
        end
        pcall(child.stop) -- job may already die
      end,
    },
    -- n_retry = helpers.get_n_retry(2),
  })
end

M.sleep = function(ms, child)
  vim.uv.sleep(math.max(ms, 1))
  if child ~= nil then child.poke_eventloop() end
end

return M
