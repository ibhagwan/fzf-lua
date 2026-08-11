---@diagnostic disable: unused-local, unused-function, unused
local MiniTest = require("mini.test")
local helpers = require("fzf-lua.test.helpers")
local child = helpers.new_child_neovim()
local eq = helpers.expect.equality
local new_set = MiniTest.new_set
local exec_lua = child.lua

--stylua: ignore start
---@format disable-next
local reload = function(config) child.unload(); child.setup(config) end
local type_keys = function(...) return child.type_keys(...) end
local sleep = function(ms) helpers.sleep(ms, child) end
--stylua: ignore end

local T = helpers.new_set_with_child(child, {
  hooks = {
    pre_case = function()
      child.o.shell = "/bin/sh"
      child.o.termguicolors = true
      child.o.background = "dark"
      child.o.statusline = "fzf://"
    end,
  },
})

T["ui_select"] = new_set()

local register = function(opts)
  local literal = vim.inspect(opts or {}):gsub("\n", " ")
  exec_lua(([[FzfLua.register_ui_select(%s)]]):format(literal))
end

-- Wipe any stale /tmp/fzf-lua-ui-select-*.tmp files left by previous
-- (possibly crashed) test runs. The tmpfile name uses `os.time()`
-- which has 1-second resolution, so concurrent runs in the same
-- second would otherwise race on the same path.
local function cleanup_stale_tmpfiles()
  for _, f in ipairs(vim.fn.glob("/tmp/fzf-lua-ui-select-*.tmp", true, true)) do
    pcall(os.remove, f)
  end
  exec_lua(([[
    for _, f in ipairs(vim.fn.glob("/tmp/fzf-lua-ui-select-*.tmp", true, true)) do
      pcall(os.remove, f)
    end
  ]]))
end

-- Open the picker via `vim.ui.select` and wait for it to appear.
-- The buffer is created in the child nvim (buffers don't cross the rpc
-- boundary). `pcall` traps any synchronous crash from the native
-- preview fn (#2743).
local function open_picker(items, preview_lines, ui_opts)
  ---@diagnostic disable-next-line: redefined-local
  exec_lua(function(items, preview_lines, ui_opts)
    _G._ui_select_choice = nil
    _G._ui_select_errors = nil
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, preview_lines)
    local opts = vim.tbl_extend("keep", ui_opts, {
      format_item = function(item) return tostring(item) end,
      preview_item = function() return { buf = buf } end,
    })
    local ok, err = pcall(vim.ui.select, items, opts, function(item, idx)
      _G._ui_select_choice = { item = item, idx = idx }
    end)
    if not ok then
      _G._ui_select_errors = tostring(err); error(err)
    end
  end, { items, preview_lines, ui_opts or {} })
  child.wait_until(function()
    return child.lua_get([[_G._fzf_lua_on_create]]) == true
        or child.lua_get([[_G._ui_select_errors]]) ~= nil
  end, 5000)
  local errs = child.lua_get([[_G._ui_select_errors]])
  eq(errs, vim.NIL, { fail_reason = "vim.ui.select errored: " .. tostring(errs) })
  eq(child.lua_get([[_G._fzf_lua_on_create]]), true)
end

local function close_picker(key)
  type_keys(key or "<c-c>")
  child.wait_until(function()
    return child.lua_get([[_G._fzf_lua_on_create]]) == vim.NIL
  end, 5000)
  eq(child.lua_get([[_G._fzf_lua_on_create]]), vim.NIL)
end

-- Wait until the picker's previewer reports having rendered the
-- first entry. `last_entry` is the full fzf line (with the `<n>. `
-- prefix produced by ui_select).
local function wait_preview_rendered(expected_entry)
  child.wait_until(function()
    local last = child.lua_get([[
      (FzfLua.utils.fzf_winobj() or {})._previewer
        and FzfLua.utils.fzf_winobj()._previewer.last_entry or nil
    ]])
    return last == expected_entry
  end, 5000)
end

T["ui_select"]["buffer preview (default)"] = function()
  reload({ "default" })
  register()
  open_picker({ "alpha", "beta" }, { "preview-line-1", "preview-line-2" },
    { prompt = "Pick (buffer):" })
  wait_preview_rendered("1. alpha")
  local screen = tostring(child.get_screenshot({ redraw = true }))
  eq(screen:find("alpha", 1, true) ~= nil, true,
    { fail_reason = "alpha not in screen:\n" .. screen })
  eq(screen:find("preview-line-1", 1, true) ~= nil, true,
    { fail_reason = "preview line 1 not in screen:\n" .. screen })
  close_picker()
end

T["ui_select"]["native via fzf-tmux profile #2743"] = function()
  -- The fzf-tmux profile declares `ui_select = { preview_type = "native" }`
  -- so the picker should use the native backend even without an
  -- explicit opt (in real tmux the picker runs in a tmux popup; here
  -- without tmux it degrades to a regular fzf run with the same opts).
  cleanup_stale_tmpfiles()
  reload({ "fzf-tmux" })
  register()
  open_picker({ "alpha", "beta" }, { "tmux-line" })
  sleep(300)
  close_picker()
end

T["ui_select"]["async preview_item opens without crash"] = function()
  reload({ "default" })
  register()
  exec_lua(function()
    vim.ui.select({ "alpha", "beta" }, {
      prompt = "Pick (async):",
      preview_item = function(_) return {} end,
      format_item = function(item) return tostring(item) end,
    }, function() end)
  end)
  child.wait_until(function()
    return child.lua_get([[_G._fzf_lua_on_create]]) == true
  end, 5000)
  eq(child.lua_get([[_G._fzf_lua_on_create]]), true)
  close_picker("<esc>")
end

T["ui_select"]["abort via esc"] = function()
  reload({ "default" })
  register()
  open_picker({ "alpha" }, { "esc-preview" })
  close_picker("<esc>")
  eq(child.lua_get([[_G._ui_select_choice]]), vim.NIL)
end

-- #2795: opts sent once from `lsp_code_actions` (`_OPTS_ONCE`) must be
-- merged into the picker opts *before* `config.normalize_opts` runs so
-- that the "hide" profile's `enrich` sees `no_resume`/`no_hide` and does
-- not set `<Esc>` (and all other actions) to hide instead of close.
T["ui_select"]["lsp_code_actions no_resume honored #2795"] = function()
  -- "default" profile includes "hide"
  reload({ "default" })
  register()
  exec_lua(function()
    -- emulate `FzfLua.lsp_code_actions({ no_resume = true })` sending
    -- "once" opts to ui_select (normalized, as done by `normalize_lsp_opts`)
    local ui_select = require("fzf-lua.providers.ui_select")
    local opts_once = require("fzf-lua.config").normalize_opts(
      { no_resume = true, previewer = false }, "lsp.code_actions")
    ui_select.register(nil, true, opts_once)
    -- capture the final opts passed to `fzf_exec`
    local core = require("fzf-lua.core")
    local orig_fzf_exec = core.fzf_exec
    core.fzf_exec = function(contents, opts)
      ---@cast opts table
      _G._fzf_exec_opts = {
        no_resume = opts.no_resume,
        no_hide = opts.no_hide,
        esc_action_type = type(vim.tbl_get(opts, "actions", "esc")),
      }
      return orig_fzf_exec(contents, opts)
    end
    vim.ui.select({ "alpha", "beta" }, {
      prompt = "Code actions:",
      kind = "codeaction",
      format_item = function(item) return tostring(item) end,
    }, function() end)
  end)
  child.wait_until(function()
    return child.lua_get([[_G._fzf_lua_on_create]]) == true
  end, 5000)
  local captured = child.lua_get([[_G._fzf_exec_opts]])
  eq(captured.no_resume, true)
  eq(captured.no_hide, true)
  -- "hide" profile must not have enriched the esc action
  eq(captured.esc_action_type, "nil")
  close_picker("<esc>")
  -- picker must not have been stored as resume data
  eq(child.lua_get(
    [[(require("fzf-lua.config").__resume_data or {}).contents]]), vim.NIL)
  -- explicit `no_hide = false` sent via once-opts must be respected
  -- (not replaced by the implicit code-action `no_hide = true` default)
  exec_lua(function()
    local ui_select = require("fzf-lua.providers.ui_select")
    local opts_once = require("fzf-lua.config").normalize_opts(
      { no_hide = false, previewer = false }, "lsp.code_actions")
    ui_select.register(nil, true, opts_once)
    vim.ui.select({ "alpha", "beta" }, {
      prompt = "Code actions:",
      kind = "codeaction",
      format_item = function(item) return tostring(item) end,
    }, function() end)
  end)
  child.wait_until(function()
    return child.lua_get([[_G._fzf_lua_on_create]]) == true
  end, 5000)
  eq(child.lua_get([[_G._fzf_exec_opts.no_hide]]), false)
  close_picker("<esc>")
end

T["ui_select"]["once opts merged with preview_item #2795"] = function()
  -- "default" profile includes "hide"
  reload({ "default" })
  register()
  exec_lua(function()
    local ui_select = require("fzf-lua.providers.ui_select")
    local opts_once = require("fzf-lua.config").normalize_opts(
      { no_resume = true, previewer = false }, "lsp.code_actions")
    ui_select.register(nil, true, opts_once)
    local core = require("fzf-lua.core")
    local orig_fzf_exec = core.fzf_exec
    core.fzf_exec = function(contents, opts)
      ---@cast opts table
      _G._fzf_exec_opts = {
        no_resume = opts.no_resume,
        no_hide = opts.no_hide,
        esc_action_type = type(vim.tbl_get(opts, "actions", "esc")),
      }
      return orig_fzf_exec(contents, opts)
    end
    -- nvim >= 0.12 code_action sends `preview_item` which used to skip
    -- the `_OPTS_ONCE` merge entirely (`elseif`), dropping `no_resume`
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "preview" })
    vim.ui.select({ "alpha", "beta" }, {
      prompt = "Code actions:",
      kind = "codeaction",
      format_item = function(item) return tostring(item) end,
      preview_item = function(_) return { buf = buf } end,
    }, function() end)
  end)
  child.wait_until(function()
    return child.lua_get([[_G._fzf_lua_on_create]]) == true
  end, 5000)
  local captured = child.lua_get([[_G._fzf_exec_opts]])
  eq(captured.no_resume, true)
  eq(captured.no_hide, true)
  eq(captured.esc_action_type, "nil")
  close_picker("<esc>")
  eq(child.lua_get(
    [[(require("fzf-lua.config").__resume_data or {}).contents]]), vim.NIL)
end

T["ui_select"]["registered function opts receive (ui_opts, items) #2770"] = function()
  reload({ "default" })
  -- `config.normalize_opts` calls function opts with no args; the wrapper
  -- in `M.ui_select` must resolve the function with `(ui_opts, items)`
  -- before normalizing, preserving the documented interface (#755).
  exec_lua([[
    FzfLua.register_ui_select(function(fzf_opts, items)
      _G._ui_select_args = {
        kind = fzf_opts.kind,
        prompt = fzf_opts.prompt,
        nitems = #items,
      }
      return {}
    end)
  ]])
  open_picker({ "alpha", "beta" }, { "preview-line-1", "preview-line-2" },
    { prompt = "Pick (fn):", kind = "codeaction" })
  close_picker("<esc>")
  eq(child.lua_get([[_G._ui_select_args]]),
    { kind = "codeaction", prompt = "Pick (fn):", nitems = 2 })
end

return T
