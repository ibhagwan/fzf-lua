---@diagnostic disable-next-line: deprecated
local uv = vim.uv or vim.loop
local utils = require("fzf-lua.utils")
local shell = require("fzf-lua.shell")
local config = require("fzf-lua.config")
local actions = require("fzf-lua.actions")
local libuv = require("fzf-lua.libuv")

local M = {}

-- Known fzf events (not keys) — used to distinguish event binds
-- from key binds during classification
local FZF_EVENTS = {
  ["load"]         = true,
  ["start"]        = true,
  ["resize"]       = true,
  ["change"]       = true,
  ["zero"]         = true,
  ["one"]          = true,
  ["focus"]        = true,
  ["result"]       = true,
  ["multi"]        = true,
  ["click-header"] = true,
  ["click-footer"] = true,
  ["backward-eof"] = true,
  ["jump"]         = true,
  ["jump-cancel"]  = true,
}

-- Known builtin actions that are handled neovim-side (from win.lua)
-- These go through the transform handler instead of direct fzf binds
local BUILTIN_ACTIONS = {
  ["hide"]                    = true,
  ["toggle-help"]             = true,
  ["toggle-fullscreen"]       = true,
  ["toggle-preview"]          = true,
  ["toggle-preview-cw"]       = true,
  ["toggle-preview-ccw"]      = true,
  ["toggle-preview-behavior"] = true,
  ["toggle-preview-wrap"]     = true,
  ["toggle-preview-ts-ctx"]   = true,
  ["toggle-preview-undo"]     = true,
  ["preview-ts-ctx-dec"]      = true,
  ["preview-ts-ctx-inc"]      = true,
  ["preview-reset"]           = true,
  ["preview-page-down"]       = true,
  ["preview-page-up"]         = true,
  ["preview-half-page-up"]    = true,
  ["preview-half-page-down"]  = true,
  ["preview-down"]            = true,
  ["preview-up"]              = true,
  ["preview-top"]             = true,
  ["preview-bottom"]          = true,
  ["focus-preview"]           = true,
}

-- Keys with modifier+special combos that fzf doesn't support.
-- Used by normalize_key to route these through the SIGWINCH bridge.
local SPECIAL_NEOVIM_ONLY = {
  ["ctrl-cr"]     = true,
  ["ctrl-enter"]  = true,
  ["ctrl-bs"]     = true,
  ["shift-cr"]    = true,
  ["shift-enter"] = true,
  ["alt-esc"]     = true,
}

-- Bind categories
M.DIRECT = "direct"
M.ACCEPT = "accept"
M.TRANSFORM = "transform"
M.SIGWINCH = "sigwinch"
M.DROPPED = "dropped"

--- Normalize a key from neovim format to fzf format if needed.
--- Accepts both styles: `<C-y>` -> `ctrl-y`, `ctrl-y` stays as-is.
--- Both paths check SPECIAL_NEOVIM_ONLY so raw fzf-style unsupported
--- keys (e.g. "ctrl-enter") are treated the same as "<C-Enter>".
---@param key string
---@return string fzf_key
---@return boolean is_neovim_only true if key has no fzf equivalent
local function normalize_key(key)
  local fzf_key
  if key:match("^<.*>$") then
    fzf_key = utils.neovim_bind_to_fzf(key)
    -- Collapse shift-<letter> to uppercase letter in fzf key format.
    -- neovim_bind_to_fzf produces e.g. "alt-shift-j" from "<M-S-j>"
    -- but fzf expects "alt-J" (shift+letter = uppercase letter).
    -- Only applies to single ASCII letters, not special keys like
    -- shift-down, shift-tab, etc.
    fzf_key = fzf_key:gsub("shift%-(%a)$", function(letter)
      return letter:upper()
    end)
  else
    fzf_key = key
  end
  return fzf_key, SPECIAL_NEOVIM_ONLY[fzf_key] or false
end

--- Normalize a single bind value into the canonical table form.
--- Handles all accepted value types (function, string, table).
---@param key string the fzf-format key
---@param value any the bind value
---@param is_event boolean whether the key is an fzf event name
---@param source string? which table the value came from (e.g. "keymap.fzf")
---@return table? normalized bind entry or nil to skip
local function normalize_value(key, value, is_event, source)
  if value == false or value == nil then
    return nil
  end

  -- Bare function — behavior depends on source
  if type(value) == "function" then
    if is_event then
      return { fn = value, event = true }
    elseif source == "keymap.fzf" then
      -- Legacy: bare functions in keymap.fzf are execute-silent
      -- (core.lua create_fzf_binds converts them to execute-silent:...)
      return { fn = value, exec_silent = true }
    else
      return { fn = value, accept = true }
    end
  end

  -- String value
  if type(value) == "string" then
    if BUILTIN_ACTIONS[value] then
      return { builtin = value }
    else
      -- fzf-native action string (e.g. "abort", "half-page-down")
      return { fzf_action = value }
    end
  end

  -- Table with `fn` property — complex action definition
  if type(value) == "table" and value.fn then
    local entry = vim.tbl_extend("keep", {}, value)
    if is_event then
      entry.event = true
    end
    return entry
  end

  -- Table with string [1] (help string support: {"first", desc = "Go to first"})
  if type(value) == "table" and type(value[1]) == "string" then
    if BUILTIN_ACTIONS[value[1]] then
      return { builtin = value[1], desc = value.desc }
    end
    return { fzf_action = value[1], desc = value.desc }
  end

  -- Array of functions — chained action (from actions table)
  if type(value) == "table" and type(value[1]) == "function" then
    -- Check for backward compat pattern: { fn, actions.resume }
    if value[2] == actions.resume then
      return { fn = value[1], reload = true }
    end
    -- Chained accept action
    local entry = { fn = value[1], accept = true }
    if #value > 1 then
      local chain = {}
      for i = 2, #value do
        table.insert(chain, value[i])
      end
      entry.chain = chain
    end
    return entry
  end

  return nil
end

--- Merge all bind sources into a single normalized table.
--- Precedence: binds > actions > keymap.fzf > keymap.builtin
---@param opts table
---@return table<string, table> merged table of normalized bind entries keyed by fzf-format key
function M.normalize_binds(opts)
  local merged = {}

  -- 4. keymap.builtin (lowest precedence)
  if type(opts.keymap) == "table" and type(opts.keymap.builtin) == "table" then
    for key, value in pairs(opts.keymap.builtin) do
      if type(key) == "string" and value and value ~= true then
        local fzf_key = normalize_key(key)
        local entry = normalize_value(fzf_key, value, FZF_EVENTS[fzf_key], "keymap.builtin")
        if entry then
          entry._source = "keymap.builtin"
          entry._nvim_key = key
          merged[fzf_key] = entry
        end
      end
    end
  end

  -- 3. keymap.fzf
  if type(opts.keymap) == "table" and type(opts.keymap.fzf) == "table" then
    for key, value in pairs(opts.keymap.fzf) do
      local fzf_key = normalize_key(key)
      local entry = normalize_value(fzf_key, value, FZF_EVENTS[fzf_key], "keymap.fzf")
      if entry then
        entry._source = "keymap.fzf"
        entry._nvim_key = key
        merged[fzf_key] = entry
      end
    end
  end

  -- 2. actions
  if type(opts.actions) == "table" then
    for key, value in pairs(opts.actions) do
      -- Internal actions (underscore prefix) are not merged
      if type(key) == "string" and not key:match("^_") then
        local fzf_key = normalize_key(key)
        local entry = normalize_value(fzf_key, value, FZF_EVENTS[fzf_key], "actions")
        if entry then
          entry._source = "actions"
          entry._nvim_key = key
          merged[fzf_key] = entry
        end
      end
    end
  end

  -- 1. binds (highest precedence)
  if type(opts.binds) == "table" then
    for key, value in pairs(opts.binds) do
      local fzf_key = normalize_key(key)
      local entry = normalize_value(fzf_key, value, FZF_EVENTS[fzf_key], "binds")
      if entry then
        entry._source = "binds"
        entry._nvim_key = key
        merged[fzf_key] = entry
      elseif value == false then
        -- Explicit false removes the bind and clears legacy tables
        -- so actions.expect()/create_fzf_binds() can't resurrect it
        merged[fzf_key] = nil
        if type(opts.actions) == "table" then
          opts.actions[key] = nil
        end
        if type(opts.keymap) == "table" and type(opts.keymap.fzf) == "table" then
          opts.keymap.fzf[key] = nil
        end
      end
    end
  end

  return merged
end

--- Classify a normalized bind entry into one of the 5 categories.
---@param key string fzf-format key
---@param entry table normalized bind entry
---@param opts table
---@return string category one of M.DIRECT, M.ACCEPT, M.TRANSFORM, M.SIGWINCH, M.DROPPED
local function classify_bind(key, entry, opts)
  local is_event = FZF_EVENTS[key]
  local _, is_neovim_only = normalize_key(entry._nvim_key or key)

  -- Neovim-only keys (e.g. <C-Enter>, <M-Esc>) cannot be sent to fzf as --bind
  -- entries. Route through SIGWINCH bridge (neovim terminal) or DROP (tmux/CLI).
  if is_neovim_only and not is_event then
    if opts._is_fzf_tmux or _G.fzf_jobstart or utils.__IS_WINDOWS then
      return M.DROPPED
    end
    return M.SIGWINCH
  end

  -- Direct: string fzf-native action (not a builtin)
  if entry.fzf_action then
    return M.DIRECT
  end

  -- Builtin action → transform
  if entry.builtin then
    return M.TRANSFORM
  end

  -- Event → always transform
  if is_event then
    return M.TRANSFORM
  end

  -- Accept: bare function, accept=true, or reuse=true
  if entry.accept then
    return M.ACCEPT
  end

  -- Reuse: goes through accept path (print+accept, but reopens)
  if entry.reuse then
    return M.ACCEPT
  end

  -- Reload/exec_silent → transform
  if entry.reload or entry.exec_silent then
    return M.TRANSFORM
  end

  -- Function with no explicit property → accept
  if entry.fn and type(entry.fn) == "function" then
    return M.ACCEPT
  end

  return M.DIRECT
end

--- Build the consolidated transform handler and all --bind entries.
--- This replaces `convert_reload_actions`, `convert_exec_silent_actions`,
--- and much of `create_fzf_binds` for fzf >= 0.59.
---@param opts table
---@return table opts with modified fzf_opts and _fzf_cli_args
function M.build_transform_binds(opts)
  local merged = M.normalize_binds(opts)

  -- Classify all binds
  local direct = {}    -- key -> fzf action string
  local accept = {}    -- key -> bind entry (for actions.expect)
  local transform = {} -- key -> bind entry (keys for consolidated handler)
  local events = {}    -- event_name -> bind entry
  local sigwinch = {}  -- key -> bind entry

  for key, entry in pairs(merged) do
    local category = classify_bind(key, entry, opts)
    if category == M.DIRECT then
      direct[key] = entry
    elseif category == M.ACCEPT then
      accept[key] = entry
    elseif category == M.TRANSFORM then
      if FZF_EVENTS[key] then
        events[key] = entry
      else
        transform[key] = entry
      end
    elseif category == M.SIGWINCH then
      sigwinch[key] = entry
    end
    -- DROPPED: silently skipped
  end

  -- ============================================================
  -- 1. ACCEPT binds: write into opts.actions for actions.expect
  -- ============================================================
  -- We populate opts.actions so that the existing actions.expect()
  -- and actions.act() machinery handles accept actions unchanged.
  opts.actions = opts.actions or {}
  for key, entry in pairs(accept) do
    -- Reconstruct the action table that actions.expect understands
    local action_entry
    if entry.chain then
      -- Chained actions: array of functions
      action_entry = { entry.fn }
      for _, f in ipairs(entry.chain) do
        table.insert(action_entry, f)
      end
    elseif entry.reuse then
      action_entry = {
        fn = entry.fn,
        reuse = entry.reuse,
        prefix = entry.prefix,
        postfix = entry.postfix,
        desc = entry.desc,
        header = entry.header,
        field_index = entry.field_index,
      }
    else
      action_entry = {
        fn = entry.fn or entry,
        prefix = entry.prefix,
        postfix = entry.postfix,
        desc = entry.desc,
        header = entry.header,
        field_index = entry.field_index,
      }
    end
    opts.actions[key] = action_entry
  end

  -- ============================================================
  -- 2. TRANSFORM binds: consolidated handler
  -- ============================================================
  local transform_keys = vim.tbl_keys(transform)
  local event_keys = vim.tbl_keys(events)
  local has_transform = #transform_keys > 0 or #event_keys > 0

  if has_transform then
    -- Build the handler dispatch table on opts
    opts.__transform_handlers = {}

    -- Register key handlers
    for key, entry in pairs(transform) do
      opts.__transform_handlers[key] = M._make_handler(key, entry, opts)
    end

    -- Register event handlers
    for evname, entry in pairs(events) do
      opts.__transform_handlers[evname] = M._make_handler(evname, entry, opts)
    end

    -- Build the unbind/rebind strings for reload actions
    local reload_keys = {}
    for key, entry in pairs(transform) do
      if entry.reload then
        table.insert(reload_keys, key)
      end
    end

    local unbind_str, rebind_str
    if #reload_keys > 0 then
      unbind_str = table.concat(vim.tbl_map(function(k)
        return string.format("unbind(%s)", k)
      end, reload_keys), "+")
      rebind_str = table.concat(vim.tbl_map(function(k)
        return string.format("rebind(%s)", k)
      end, reload_keys), "+")
    end

    -- Store for handler use
    opts.__transform_unbind = unbind_str
    opts.__transform_rebind = rebind_str
    opts.__transform_reload_cmd = type(opts._contents) == "string" and opts._contents or nil

    -- Register the single RPC function via pipe_wrap_fn (empty field index)
    local base_cmd = shell.pipe_wrap_fn(
      M._create_dispatch_handler(opts),
      "", -- empty field index, caller appends per-bind
      opts.debug
    )

    -- Build the consolidated --bind entries
    local bind_entries = {}

    -- Key transform: --bind=key1,key2,...:transform:BASE_CMD {+} {q} {n}
    if #transform_keys > 0 then
      table.sort(transform_keys)
      table.insert(bind_entries,
        string.format("%s:transform:%s {+} {q} {n}",
          table.concat(transform_keys, ","),
          base_cmd))
    end

    -- Event transforms: --bind=<event>:+transform:BASE_CMD __evt__<event> <field_index>
    for _, evname in ipairs(event_keys) do
      local entry = events[evname]
      local field_index
      if entry.field_index then
        -- Custom field_index: use as-is, mark handler to not strip {q}/{n}
        field_index = entry.field_index
        opts.__transform_custom_fi = opts.__transform_custom_fi or {}
        opts.__transform_custom_fi[evname] = true
      else
        field_index = "{+} {q} {n}"
      end
      -- Use "+transform" for events to be additive (don't override other event binds)
      table.insert(bind_entries,
        string.format("%s:+transform:%s __evt__%s %s",
          evname, base_cmd, evname, field_index))
    end

    -- Add rebind on load event if we have reload keys
    if rebind_str then
      table.insert(bind_entries,
        string.format("load:+%s", rebind_str))
    end

    -- Add to _fzf_cli_args as separate --bind entries
    opts._fzf_cli_args = opts._fzf_cli_args or {}
    for _, bind in ipairs(bind_entries) do
      table.insert(opts._fzf_cli_args, "--bind=" .. libuv.shellescape(bind))
    end
  end

  -- ============================================================
  -- 3. SIGWINCH binds: register neovim terminal keymaps + resize
  -- ============================================================
  -- SIGWINCH bridge: for neovim-only keys (e.g. <C-Enter>) that have no fzf
  -- equivalent. A terminal keymap in neovim pushes the handler name into
  -- `opts.__sigwinches` and sends POSIX SIGWINCH (signal 28) to fzf.
  -- Fzf fires `resize` event, which triggers the `on_SIGWINCH` callback,
  -- which processes the queued handler names via `opts.__sigwinch_cb`.
  if not utils.tbl_isempty(sigwinch) then
    local win = require("fzf-lua.win")
    opts.__sigwinch_triggers = opts.__sigwinch_triggers or {}
    for key, entry in pairs(sigwinch) do
      local nvim_key = entry._nvim_key or utils.fzf_bind_to_neovim(key)
      local handler_key = "__sigwinch__" .. key
      local handler = M._make_handler(key, entry, opts)

      -- Register as on_SIGWINCH callback — runs when handler_key is in __sigwinches
      win.on_SIGWINCH(opts, handler_key, function(_args)
        -- Ignore args (preview lines), call our handler with empty items
        return handler({}, {})
      end)

      -- Store the neovim key → handler_key mapping for the terminal keymap
      -- setup in win.lua:setup_keybinds()
      opts.__sigwinch_triggers[nvim_key] = handler_key
    end
  end

  -- ============================================================
  -- 4. Write direct binds to opts.fzf_opts["--bind"]
  -- ============================================================
  opts.keymap = opts.keymap or {}
  opts.keymap.fzf = opts.keymap.fzf or {}
  -- Clear keymap.fzf entries that we've already handled to prevent
  -- create_fzf_binds from double-processing them
  for key, _ in pairs(merged) do
    if not direct[key] then
      opts.keymap.fzf[key] = nil
    end
  end
  -- Write direct binds into keymap.fzf for create_fzf_binds to pick up
  for key, entry in pairs(direct) do
    local action = entry.fzf_action
    if entry.desc then
      opts.keymap.fzf[key] = { action, desc = entry.desc }
    else
      opts.keymap.fzf[key] = action
    end
    -- Also mark action with _ignore so actions.expect() doesn't generate
    -- a competing print(key)+accept for DIRECT entries (e.g. Windows
    -- toggle-preview which is classified DIRECT instead of TRANSFORM)
    if opts.actions[key] then
      if type(opts.actions[key]) == "table" then
        opts.actions[key]._ignore = true
      else
        opts.actions[key] = { fn = opts.actions[key], _ignore = true }
      end
    end
  end

  -- Mark actions that were routed to transform as _ignore
  -- so actions.expect() doesn't double-process them
  for key, entry in pairs(transform) do
    if opts.actions[key] then
      if type(opts.actions[key]) == "table" then
        opts.actions[key]._ignore = true
      else
        opts.actions[key] = { fn = opts.actions[key], _ignore = true }
      end
    end
  end
  for key, _ in pairs(events) do
    if opts.actions[key] then
      if type(opts.actions[key]) == "table" then
        opts.actions[key]._ignore = true
      else
        opts.actions[key] = { fn = opts.actions[key], _ignore = true }
      end
    end
  end

  return opts
end

--- Create a handler function for a single bind entry.
--- Returns a function(items, ctx) -> fzf_action_string
---@param key string
---@param entry table normalized bind entry
---@param opts table
---@return function
function M._make_handler(key, entry, opts)
  -- Direct fzf action routed through SIGWINCH bridge (neovim-only key)
  if entry.fzf_action then
    return function(_items, _ctx)
      return entry.fzf_action
    end
  end

  if entry.builtin then
    -- Builtin action: call neovim-side function, return fzf action
    return function(items, ctx)
      return M._execute_builtin(entry.builtin, opts)
    end
  end

  if entry.reload then
    -- Reload action: execute fn, then reload
    return function(items, ctx)
      local reload_cmd = opts.__transform_reload_cmd
      local unbind = opts.__transform_unbind

      -- Execute the function
      if type(entry.fn) == "function" then
        entry.fn(items, opts)
      end

      -- Build the fzf action string: unbind+reload(cmd)+postfix
      local parts = {}
      if type(entry.prefix) == "string" then
        table.insert(parts, entry.prefix:gsub("%+$", ""))
      end
      if unbind then
        table.insert(parts, unbind)
      end
      if reload_cmd then
        table.insert(parts, string.format("reload(%s)", reload_cmd))
      end
      if type(entry.postfix) == "string" then
        table.insert(parts, entry.postfix:gsub("^%+", ""))
      end
      return table.concat(parts, "+")
    end
  end

  if entry.exec_silent then
    -- Exec-silent action: execute fn, return empty (no fzf action)
    return function(items, ctx)
      if type(entry.fn) == "function" then
        entry.fn(items, opts)
      end
      -- Preserve prefix/postfix wrappers (e.g. "select-all+...")
      local parts = {}
      if type(entry.prefix) == "string" then
        table.insert(parts, entry.prefix:gsub("%+$", ""))
      end
      if type(entry.postfix) == "string" then
        table.insert(parts, entry.postfix:gsub("^%+", ""))
      end
      return #parts > 0 and table.concat(parts, "+") or ""
    end
  end

  if entry.event then
    -- Event handler: call fn, return result as fzf action
    return function(items, ctx)
      if type(entry.fn) == "function" then
        local result = entry.fn(items, opts)
        return type(result) == "string" and result or ""
      end
      return ""
    end
  end

  -- Generic function handler (shouldn't normally reach here for transform)
  return function(items, ctx)
    if type(entry.fn) == "function" then
      local result = entry.fn(items, opts)
      return type(result) == "string" and result or ""
    end
    return ""
  end
end

--- Execute a builtin action (e.g. toggle-preview) on the neovim side.
--- Returns the appropriate fzf action string.
---@param builtin_name string
---@param opts table
---@return string fzf action string
function M._execute_builtin(builtin_name, opts)
  local win = require("fzf-lua.win")

  -- Helper: get the FzfWin singleton for layout queries
  local function winobj()
    return win.__SELF()
  end

  -- Helper: get fzf change-preview-window action with current layout
  local function change_preview_window()
    local self = winobj()
    if self then
      return string.format("change-preview-window(%s)", self:normalize_preview_layout().str)
    end
    return ""
  end

  -- Map builtin names to their win.lua implementations
  local builtin_map = {
    ["hide"]                    = function()
      win.hide()
    end,
    ["toggle-help"]             = function()
      win.toggle_help()
    end,
    ["toggle-fullscreen"]       = function()
      win.toggle_fullscreen()
    end,
    ["toggle-preview"]          = function()
      win.toggle_preview()
      local self = winobj()
      if not self then return "" end
      -- For builtin previewer without split, fzf's preview pane is zero-width
      -- (--preview-window=nohidden:right:0). Don't send toggle-preview to fzf
      -- or the zero-width pane gets toggled visible, creating an unwanted box.
      -- The neovim preview is managed entirely by win.toggle_preview().
      if self.previewer_is_builtin and not self.winopts.split then
        return ""
      end
      -- For split layouts or fzf-native previewers, sync fzf's preview state:
      if self.preview_hidden then
        return "toggle-preview"
      else
        return string.format("toggle-preview+change-preview-window(%s)",
          self:normalize_preview_layout().str)
      end
    end,
    ["toggle-preview-cw"]       = function()
      win.toggle_preview_cw(1)
      return change_preview_window()
    end,
    ["toggle-preview-ccw"]      = function()
      win.toggle_preview_cw(-1)
      return change_preview_window()
    end,
    ["toggle-preview-behavior"] = function()
      win.toggle_preview_behavior()
    end,
    ["toggle-preview-wrap"]     = function() win.toggle_preview_wrap() end,
    ["toggle-preview-ts-ctx"]   = function() win.toggle_preview_ts_ctx() end,
    ["toggle-preview-undo"]     = function() win.toggle_preview_undo_diff() end,
    ["preview-ts-ctx-dec"]      = function() win.preview_ts_ctx_inc_dec(-1) end,
    ["preview-ts-ctx-inc"]      = function() win.preview_ts_ctx_inc_dec(1) end,
    ["preview-reset"]           = function() win.preview_scroll("reset") end,
    ["preview-page-down"]       = function() win.preview_scroll("page-down") end,
    ["preview-page-up"]         = function() win.preview_scroll("page-up") end,
    ["preview-half-page-up"]    = function() win.preview_scroll("half-page-up") end,
    ["preview-half-page-down"]  = function() win.preview_scroll("half-page-down") end,
    ["preview-down"]            = function() win.preview_scroll("line-down") end,
    ["preview-up"]              = function() win.preview_scroll("line-up") end,
    ["preview-top"]             = function() win.preview_scroll("top") end,
    ["preview-bottom"]          = function() win.preview_scroll("bottom") end,
    ["focus-preview"]           = function() win.focus_preview() end,
  }

  local handler = builtin_map[builtin_name]
  if handler then
    local result = handler()
    return type(result) == "string" and result or ""
  end
  return ""
end

--- Create the single dispatch handler that all transform binds share.
--- This is the function registered with pipe_wrap_fn.
---@param opts table
---@return function the pipe handler function(pipe, items, preview_lines, preview_cols, ctx)
function M._create_dispatch_handler(opts)
  return function(pipe, items, preview_lines, preview_cols, ctx)
    -- Determine trigger: event prefix or $FZF_KEY
    local key
    local is_event = false
    if items[1] and type(items[1]) == "string" and items[1]:match("^__evt__") then
      key = items[1]:sub(8) -- strip "__evt__" prefix
      table.remove(items, 1)
      is_event = true
    else
      key = ctx.env.FZF_KEY or ""
    end

    -- Strip trailing {q} and {n} from items (appended by field index)
    -- unless event has custom field_index
    local custom_fi = is_event and opts.__transform_custom_fi
        and opts.__transform_custom_fi[key]
    if not custom_fi then
      local match_count = table.remove(items) -- {n}
      local query = table.remove(items)       -- {q}

      -- Update resume query
      if query then
        config.resume_set("query", query, opts)
      end

      -- Zero-match/zero-selected fixup (same logic as stringify_data2)
      local zero_matched = not tonumber(match_count)
      local zero_selected = #items == 0 or (#items == 1 and #items[1] == 0)
      if zero_matched and zero_selected then items = {} end
    end

    local handler = opts.__transform_handlers and opts.__transform_handlers[key]
    if not handler then
      -- No handler found, return empty (no-op)
      uv.write(pipe, "")
      uv.close(pipe)
      return
    end

    -- pcall to ensure the pipe is always closed and fzf doesn't hang.
    -- Mirrors the resilience of the legacy execute-silent path where
    -- errors in the headless nvim process don't freeze the parent.
    local ok, result = pcall(handler, items, ctx)
    if not ok then
      utils.warn(string.format("transform handler error [%s]: %s", key, result))
      result = ""
    end
    uv.write(pipe, result or "")
    uv.close(pipe)
  end
end

--- Check if unified binds should be used (fzf >= 0.59, not skim, not Windows)
--- On Windows the consolidated transform shell command doesn't work with
--- cmd.exe; fall back to legacy path which uses execute-silent binds.
---@param opts table
---@return boolean
function M.can_unified(opts)
  return utils.has(opts, "fzf", { 0, 59 })
      and not utils.has(opts, "sk")
      and not utils.__IS_WINDOWS
end

return M
