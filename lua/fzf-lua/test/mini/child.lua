--- Child Neovim process helper.
---
--- Fundamental piece of the test methodology: start/stop/restart a separate
--- headless Neovim process and interact with it over RPC. Interaction mirrors
--- `vim.*` tables (`child.api`, `child.fn`, `child.o`, ...) so specs read like
--- ordinary plugin code.

local H = require("fzf-lua.test.mini.util")

--- Create child Neovim process.
---@return MiniTest.child Object of |MiniTest-child-neovim|.
H.new_child_neovim = function()
  local child = {}
  local start_args, start_opts

  local ensure_running = function()
    if child.is_running() then return end
    H.error("Child process is not running. Did you call `child.start()`?")
  end

  local prevent_hanging = function(method)
    if not child.is_blocked() then return end

    local msg = string.format("Can not use `child.%s` because child process is blocked.", method)
    H.error_with_emphasis(msg)
  end

  -- Start headless Neovim instance
  child.start = function(args, opts)
    if child.is_running() then
      H.message("Child process is already running. Use `child.restart()`.")
      return
    end

    args = args or {}
    opts = vim.tbl_deep_extend("force", { nvim_executable = vim.v.progpath, connection_timeout = 5000 }, opts or {})

    -- Make unique name for `--listen` pipe
    local job = { address = vim.fn.tempname() }

    if vim.fn.has("win32") == 1 then
      -- Use special local pipe prefix on Windows with (hopefully) unique name
      -- Source: https://learn.microsoft.com/en-us/windows/win32/ipc/pipe-names
      job.address = [[\\.\pipe\mininvim]] .. vim.fn.fnamemodify(job.address, ":t")
    end

    --stylua: ignore
    local full_args = {
      opts.nvim_executable, "--clean", "-n", "--listen", job.address,
      -- Setting 'lines' and 'columns' makes headless process more like
      -- interactive for closer to reality testing
      "--headless", "--cmd", "set lines=24 columns=80"
    }
    vim.list_extend(full_args, args)

    -- Using 'jobstart' for creating a job is crucial for getting this to work
    -- in Github Actions. Other approaches:
    -- - Using `{ pty = true }` seems crucial to make this work on GitHub CI.
    -- - Using `vim.loop.spawn()` is doable, but has some issues:
    --     - https://github.com/neovim/neovim/issues/21630
    --     - https://github.com/neovim/neovim/issues/21886
    job.id = vim.fn.jobstart(full_args)

    local step = 10
    local connected, i, max_tries = nil, 0, math.floor(opts.connection_timeout / step)
    repeat
      i = i + 1
      vim.loop.sleep(step)
      connected, job.channel = pcall(vim.fn.sockconnect, "pipe", job.address, { rpc = true })
    until connected or i >= max_tries

    if not connected then
      local err = "  " .. job.channel:gsub("\n", "\n  ")
      H.error("Failed to make connection to child Neovim with the following error:\n" .. err)
      child.stop()
    end

    child.job = job
    start_args, start_opts = args, opts
  end

  child.stop = function()
    if not child.is_running() then return end

    -- Properly exit Neovim. `pcall` avoids `channel closed by client` error.
    -- Also wait for it to actually close. This reduces simultaneously opened
    -- Neovim instances and CPU load (overall reducing flacky tests).
    pcall(child.cmd, "silent! 0cquit")
    vim.fn.jobwait({ child.job.id }, 1000)

    -- Close all used channels. Prevents `too many open files` type of errors.
    pcall(vim.fn.chanclose, child.job.channel)
    pcall(vim.fn.chanclose, child.job.id)

    -- Remove file for address to reduce chance of "can't open file" errors, as
    -- address uses temporary unique files
    pcall(vim.fn.delete, child.job.address)

    child.job = nil
  end

  child.restart = function(args, opts)
    args = args or start_args
    opts = vim.tbl_deep_extend("force", start_opts or {}, opts or {})

    child.stop()
    child.start(args, opts)
  end

  -- Wrappers for common `vim.xxx` objects (will get executed inside child)
  child.api = setmetatable({}, {
    __index = function(_, key)
      ensure_running()
      return function(...) return vim.rpcrequest(child.job.channel, key, ...) end
    end,
  })

  -- Variant of `api` functions called with `vim.rpcnotify`. Useful for making
  -- blocking requests (like `getcharstr()`).
  child.api_notify = setmetatable({}, {
    __index = function(_, key)
      ensure_running()
      return function(...) return vim.rpcnotify(child.job.channel, key, ...) end
    end,
  })

  ---@param tbl_name string name of the `vim.xxx` table to redirect
  ---@return table Emulates `vim.xxx` table (like `vim.fn`)
  ---@private
  local redirect_to_child = function(tbl_name)
    -- TODO: try to figure out the best way to operate on tables with function
    -- values (needs "deep encode/decode" of function objects)
    return setmetatable({}, {
      __index = function(_, key)
        ensure_running()

        local short_name = ("%s.%s"):format(tbl_name, key)
        local obj_name = ("vim[%s][%s]"):format(vim.inspect(tbl_name), vim.inspect(key))

        prevent_hanging(short_name)
        local value_type = child.api.nvim_exec_lua(("return type(%s)"):format(obj_name), {})

        if value_type == "function" then
          -- This allows syntax like `child.fn.mode(1)`
          return function(...)
            prevent_hanging(short_name)
            return child.api.nvim_exec_lua(("return %s(...)"):format(obj_name), { ... })
          end
        end

        -- This allows syntax like `child.bo.buftype`
        prevent_hanging(short_name)
        return child.api.nvim_exec_lua(("return %s"):format(obj_name), {})
      end,
      __newindex = function(_, key, value)
        ensure_running()

        local short_name = ("%s.%s"):format(tbl_name, key)
        local obj_name = ("vim[%s][%s]"):format(vim.inspect(tbl_name), vim.inspect(key))

        -- This allows syntax like `child.b.aaa = function(x) return x + 1 end`
        -- (inherits limitations of `string.dump`: no upvalues, etc.)
        if type(value) == "function" then
          local dumped = vim.inspect(string.dump(value))
          value = ("loadstring(%s)"):format(dumped)
        else
          value = vim.inspect(value)
        end

        prevent_hanging(short_name)
        child.api.nvim_exec_lua(("%s = %s"):format(obj_name, value), {})
      end,
    })
  end

  --stylua: ignore
  local supported_vim_tables = {
    -- Collections
    "diagnostic", "fn", "highlight", "hl", "json", "loop", "lsp", "mpack", "spell", "treesitter", "ui", "fs",
    -- Variables
    "g", "b", "w", "t", "v", "env",
    -- Options (no 'opt' because not really useful due to use of metatables)
    "o", "go", "bo", "wo",
  }
  for _, v in ipairs(supported_vim_tables) do
    child[v] = redirect_to_child(v)
  end

  -- Convenience wrappers
  child.type_keys = function(wait, ...)
    ensure_running()

    local has_wait = type(wait) == "number"
    local keys = has_wait and { ... } or { wait, ... }
    keys = H.tbl_flatten(keys)

    -- From `nvim_input` docs: "On execution error: does not fail, but
    -- updates v:errmsg.". So capture it manually. NOTE: Have it global to
    -- allow sending keys which will block in the middle (like `[[<C-\>]]` and
    -- `<C-n>`). Otherwise, later check will assume that there was an error.
    local cur_errmsg
    for _, k in ipairs(keys) do
      if type(k) ~= "string" then
        error("In `type_keys()` each argument should be either string or array of strings.")
      end

      -- But do that only if Neovim is not "blocked". Otherwise, usage of
      -- `child.v` will block execution.
      if not child.is_blocked() then
        cur_errmsg = child.v.errmsg
        child.v.errmsg = ""
      end

      -- Need to escape bare `<` (see `:h nvim_input`)
      child.api.nvim_input(k == "<" and "<LT>" or k)

      -- Possibly throw error manually
      if not child.is_blocked() then
        if child.v.errmsg ~= "" then
          error(child.v.errmsg, 2)
        else
          child.v.errmsg = cur_errmsg or ""
        end
      end

      -- Possibly wait
      if has_wait and wait > 0 then vim.loop.sleep(wait) end
    end
  end

  child.cmd = function(str)
    ensure_running()
    prevent_hanging("cmd")
    return child.api.nvim_exec(str, false)
  end

  child.cmd_capture = function(str)
    ensure_running()
    prevent_hanging("cmd_capture")
    return child.api.nvim_exec(str, true)
  end

  child.lua = function(str, args)
    ensure_running()
    prevent_hanging("lua")
    return child.api.nvim_exec_lua(str, args or {})
  end

  child.lua_notify = function(str, args)
    ensure_running()
    return child.api_notify.nvim_exec_lua(str, args or {})
  end

  child.lua_get = function(str, args)
    ensure_running()
    prevent_hanging("lua_get")
    return child.api.nvim_exec_lua("return " .. str, args or {})
  end

  child.lua_func = function(f, ...)
    ensure_running()
    prevent_hanging("lua_func")
    return child.api.nvim_exec_lua(
      "local f = ...; return assert(loadstring(f))(select(2, ...))",
      { string.dump(f), ... }
    )
  end

  child.is_blocked = function()
    ensure_running()
    return child.api.nvim_get_mode()["blocking"]
  end

  child.is_running = function() return child.job ~= nil end

  -- Various wrappers
  child.ensure_normal_mode = function()
    ensure_running()
    child.type_keys([[<C-\>]], "<C-n>")
  end

  child.get_screenshot = function(opts)
    ensure_running()
    prevent_hanging("get_screenshot")

    opts = vim.tbl_deep_extend("force", { redraw = true }, opts or {})

    if opts.redraw then child.cmd("redraw") end

    local res = child.lua([[
      local text, attr = {}, {}
      for i = 1, vim.o.lines do
        local text_line, attr_line = {}, {}
        for j = 1, vim.o.columns do
          table.insert(text_line, vim.fn.screenstring(i, j))
          table.insert(attr_line, vim.fn.screenattr(i, j))
        end
        table.insert(text, text_line)
        table.insert(attr, attr_line)
      end
      return { text = text, attr = attr }
    ]])
    res.attr = H.screenshot_encode_attr(res.attr)

    return H.screenshot_new(res)
  end

  -- Register `child` for automatic stop in case of emergency
  table.insert(H.child_neovim_registry, child)

  return child
end

return H
