# Unified Binds with Consolidated Transform Entry Point

## Overview

Refactor fzf-lua's bind system to unify `keymap.fzf`, `keymap.builtin`, and
`actions` into a single `binds` table, and consolidate all complex fzf binds
into a single `--bind=...:transform:SHELL_CMD` entry point using
`shell.stringify_data`. Gated to fzf >= 0.59.

## Motivation

The current bind system is fragmented across multiple tables and code paths:

- `keymap.fzf` — fzf-native key bindings
- `keymap.builtin` — neovim terminal-mode keymaps for built-in actions
- `actions` — accept/reload/exec_silent functions, processed by separate
  conversion functions for built-in actions

Bind construction is scattered across `create_fzf_binds`,
`convert_reload_actions`, `convert_exec_silent_actions`, `setup_keybinds`,
`setup_fzf_live_flags`, and `on_SIGWINCH`, producing many `--bind` arguments
that inflate the fzf command line.

This refactor consolidates everything into:
1. A single user-facing `binds` table
2. A single `--bind=...:transform:SHELL_CMD` for all complex operations
3. Cleaner internal architecture with fewer code paths

## User-Facing API

### The Unified `binds` Table

```lua
require("fzf-lua").setup({
  -- New unified format
  binds = {
    -- Simple fzf actions (direct --bind, no RPC overhead)
    ["ctrl-z"]     = "abort",
    ["ctrl-u"]     = "unix-line-discard",
    ["ctrl-f"]     = "half-page-down",
    ["alt-a"]      = "toggle-all",

    -- Builtin neovim actions (routed through transform)
    ["<F1>"]       = "toggle-help",
    ["<F4>"]       = "toggle-preview",
    ["<F5>"]       = "toggle-preview-cw",
    ["<M-Esc>"]    = "hide",
    ["<S-down>"]   = "preview-page-down",

    -- Accept actions (print+accept, run in neovim after fzf exits)
    ["enter"]      = { fn = actions.file_edit_or_qf, accept = true },
    ["ctrl-s"]     = { fn = actions.file_split, accept = true },
    ["ctrl-v"]     = { fn = actions.file_vsplit, accept = true },

    -- Bare lua functions default to accept = true
    ["ctrl-t"]     = actions.file_tabedit,

    -- Reload actions (execute in transform, reload list)
    ["ctrl-x"]     = { fn = actions.buf_del, reload = true },
    ["left"]       = { fn = actions.git_stage, reload = true },

    -- Exec-silent actions (execute in transform, no reload)
    ["ctrl-y"]     = { fn = actions.git_yank_commit, exec_silent = true },

    -- Reuse actions (accept but don't close window)
    ["alt-i"]      = { fn = actions.toggle_ignore, reuse = true, header = false },

    -- Events
    ["load"]       = function() return "rebind(...)" end,
    ["start"]      = function() return "change-header(...)" end,
    ["resize"]     = function(args) ... end,

    -- Help string support
    ["ctrl-g"]     = { "first", desc = "Go to first" },
  },

  -- Old format still works (merge strategy, no deprecation)
  keymap = {
    fzf     = { ... },
    builtin = { ... },
  },
  actions = { ... },
})
```

### Key Format

Both fzf-style (`ctrl-y`, `alt-a`, `f4`) and neovim-style (`<C-y>`, `<M-a>`,
`<F4>`) keys are accepted. Keys are normalized internally using
`utils.neovim_bind_to_fzf()` and `utils.fzf_bind_to_neovim()`.

### Value Auto-Detection

1. `type(v) == "function"` — bare lua function, treated as `{ fn = v, accept = true }`
2. `type(v) == "table"` with `.fn` — complex action, properties preserved
   (`accept`, `reload`, `exec_silent`, `reuse`, `noclose`, `desc`, `prefix`,
   `postfix`, `field_index`, `header`)
3. `type(v) == "string"` matching a known builtin action name — routed through
   transform (calls neovim-side function, returns fzf action)
4. `type(v) == "string"` not matching builtins — fzf-native action (direct bind)
5. Key matching a known event name (including but not limited to: `load`,
   `start`, `resize`, `change`, `zero`, `one`, `focus`, `result`, `multi`,
   `click-header`, `click-footer`, `backward-eof`) — event bind

Known builtin actions (from `keymap_tbl` and `_preview_keymaps` in win.lua):
`toggle-help`, `toggle-fullscreen`, `toggle-preview`, `toggle-preview-cw`,
`toggle-preview-ccw`, `toggle-preview-behavior`, `toggle-preview-wrap`,
`toggle-preview-ts-ctx`, `toggle-preview-undo`, `preview-ts-ctx-dec`,
`preview-ts-ctx-inc`, `preview-reset`, `preview-page-down`, `preview-page-up`,
`preview-half-page-up`, `preview-half-page-down`, `preview-down`, `preview-up`,
`preview-top`, `preview-bottom`, `focus-preview`, `hide`.

### Precedence Order

When the same key appears in multiple tables (highest wins):

1. `binds`
2. `actions`
3. `keymap.fzf`
4. `keymap.builtin`

### Backward Compatibility

All three old tables (`keymap.fzf`, `keymap.builtin`, `actions`) continue to
work indefinitely. No deprecation. The `binds` table is additive — it takes
precedence over the old tables for the same key, but doesn't require migrating
existing configs.

## Architecture

### Consolidated Transform Entry Point (fzf >= 0.59)

All complex binds share a **single RPC function registration** via
`shell.pipe_wrap_fn` (called with an empty field index; the caller appends field
expressions when constructing `--bind` entries). The generated base command
(`BASE_CMD`) is reused across multiple `--bind` entries:

- **Keys** share one `--bind` with comma-separated triggers, dispatched by
  `$FZF_KEY`:
  ```text
  --bind=ctrl-r,ctrl-g,f4,f1:transform:BASE_CMD {+} {q} {n}
  ```
- **Events** get individual `--bind` entries with the event name baked in as a
  literal argument:
  ```text
  --bind=load:transform:BASE_CMD __evt__load {+} {q} {n}
  --bind=resize:transform:BASE_CMD __evt__resize {+} {q} {n}
  --bind=start:transform:BASE_CMD __evt__start {+} {q} {n}
  ```

**Field index `{+} {q} {n}`:** All transform binds use the same field index
pattern. `{+}` expands to the selected item(s), `{q}` to the current query,
and `{n}` to the match count. This follows the pattern established by
`stringify_data2` (shell.lua) which appends `{q} {n}` for query preservation
on resume and zero-selected/zero-match disambiguation. The handler strips `{q}`
and `{n}` from the tail of `items` before dispatching, and updates the resume
query via `FzfLua.config.resume_set("query", query, opts)`.

**Why separate `--bind` for events?** `$FZF_KEY` is only set for actual
keypresses (fzf 0.50+). For events like `load`, `resize`, `start`, `$FZF_KEY`
is empty (`""`). Rather than relying on `$FZF_ACTION` (which is unreliable —
it reflects the last *action* executed, not the triggering event), we pass the
event identity as a literal prefix argument (`__evt__<name>`) in the fzf field
index. The handler checks `items[1]` for this prefix.

The dispatch handler (one registration, shared by all binds):

```lua
-- Registered once via shell.pipe_wrap_fn (with empty field index)
local function transform_handler(pipe, items, fzf_lines, fzf_columns, ctx)
  -- Strip trailing {q} and {n} from items (appended by field index)
  local match_count = table.remove(items)  -- {n}
  local query = table.remove(items)         -- {q}
  FzfLua.config.resume_set("query", query, opts)

  -- Determine trigger: event prefix or $FZF_KEY
  local key
  if items[1] and items[1]:match("^__evt__") then
    key = items[1]:sub(8)  -- strip "__evt__" prefix
    table.remove(items, 1)
  else
    key = ctx.env.FZF_KEY
  end

  -- Zero-match/zero-selected fixup (same logic as stringify_data2)
  local zero_matched = not tonumber(match_count)
  local zero_selected = #items == 0 or (#items == 1 and #items[1] == 0)
  if zero_matched and zero_selected then items = {} end

  local handlers = opts.__transform_handlers[key]
  if not handlers then
    -- return empty string (no-op)
    uv.write(pipe, ""); uv.close(pipe); return
  end
  local results = {}
  for _, handler in ipairs(handlers) do
    local act = handler(items, ctx)
    if act and #act > 0 then table.insert(results, act) end
  end
  local result = table.concat(results, "+")
  uv.write(pipe, result)
  uv.close(pipe)
end
```

**Note on `pipe_wrap_fn`:** The current implementation defaults `nil` field
index to `"{+}"`. The consolidated handler needs `pipe_wrap_fn` called with
`""` (empty string) so that no field index is baked into `BASE_CMD`. The field
index is instead appended by the caller when constructing each `--bind` entry.
This requires a minor adjustment: either pass `""` and accept a trailing space,
or add a small guard in `pipe_wrap_fn` to omit the trailing space when field
index is empty.

The resulting fzf CLI has these `--bind` groups:

1. **Direct binds:** `--bind=ctrl-z:abort,ctrl-u:unix-line-discard,...`
   (simple fzf actions, combined into one)
2. **Accept binds:** `--bind=enter:print(enter)+accept,...`
   (accept actions via `actions.expect` or equivalent)
3. **Key transform:** `--bind=ctrl-r,ctrl-g,f4,...:transform:BASE_CMD {+} {q} {n}`
   (consolidated transform for all complex key binds)
4. **Event transforms:** `--bind=load:transform:BASE_CMD __evt__load {+} {q} {n}`, etc.
   (one per registered event, same RPC function)

Plus any provider-specific binds from `_fzf_cli_args` (e.g.,
`change:+transform:CMD` from `setup_fzf_live_flags` for live pickers).

### Bind Classification (5 Categories)

| Category | Condition | Routing |
|----------|-----------|---------|
| **Direct** | String value, not a known builtin | `--bind=key:action` (combined) |
| **Accept** | `accept = true`, `reuse = true`, or bare function | `print(key)+accept` via `--bind` |
| **Transform** | `reload`, `exec_silent`, builtin name, event, lua fn with explicit non-accept/non-reuse property | Consolidated `--bind=...:transform:BASE_CMD` |
| **SIGWINCH** | Neovim-only key (no fzf equivalent), neovim terminal mode | `vim.keymap.set("t",...)` + SIGWINCH signal → transform's resize handler |
| **Dropped** | Neovim-only key in tmux/CLI/Windows | Silently skipped (no terminal buffer) |

### Three Operating Modes

| Mode | Condition | Transform | SIGWINCH | Neovim-only keys |
|------|-----------|-----------|----------|-----------------|
| **Full** | fzf >= 0.59, neovim terminal | Yes | Yes | Yes (via SIGWINCH bridge) |
| **Partial** | fzf >= 0.59, fzf-tmux or CLI profile | Yes | No | Dropped (no terminal buffer) |
| **Legacy** | fzf < 0.59 | No (current paths) | Partial (>= 0.46) | Only via `keymap.builtin` |

**Full mode:** All features available. Neovim-only keys (e.g., `<C-Enter>`,
`<C-BS>`) use the SIGWINCH bridge: a neovim terminal keymap captures the
keypress, sets a trigger scope on `opts.__sigwinch_triggers`, sends POSIX signal
28 to fzf children, which fires the `resize` event in the consolidated
transform. The handler checks `opts.__sigwinch_triggers` and dispatches to the
registered handler.

**Partial mode (fzf-tmux / CLI profile):** The consolidated transform works
(headless nvim RPC is independent of where fzf runs) but SIGWINCH is unavailable
because there is no neovim terminal buffer to capture keypresses or send signals
from. Keys without fzf equivalents are silently dropped.

**Legacy mode (fzf < 0.59):** The `binds` table is internally split into
`keymap.fzf` and `keymap.builtin` during normalization, and existing code paths
(`create_fzf_binds`, `convert_reload_actions`, `convert_exec_silent_actions`,
`setup_keybinds`, `on_SIGWINCH`) handle them unchanged.

### Builtin Actions in Transform

When a builtin action (e.g., `toggle-preview`) is bound and the key has an fzf
equivalent, it goes through the consolidated transform. The transform handler:

1. Receives `$FZF_KEY` (e.g., `"f4"`)
2. Calls the neovim-side function via RPC (e.g., `win.toggle_preview()`)
3. Returns the appropriate fzf action string (e.g.,
   `"change-preview-window(right,50%)"`)

This is simpler than the current SIGWINCH approach for fzf-supported keys —
the transform IS the RPC bridge, so no signal roundtrip is needed.

### SIGWINCH Bridge (Neovim-Only Keys)

For keys that have no fzf equivalent (e.g., `<C-Enter>`, `<C-BS>`):

1. `vim.keymap.set("t", key, function() ... end)` captures the keypress
2. Handler sets `opts.__sigwinch_triggers = { key_id }`
3. Calls `self:SIGWINCH(...)` — sends signal 28 to fzf child processes
4. Fzf fires the `resize` event → hits the consolidated transform
5. Transform handler checks `opts.__sigwinch_triggers`, dispatches to the
   registered handler for `key_id`
6. Returns fzf action string

The `resize` event is always included in the consolidated transform's key/event
list when there are any SIGWINCH-bridged keys.

## Actions Table Integration

### Auto-Merge into Binds

During `normalize_binds(opts)`, entries from `opts.actions` are converted and
merged into the internal bind representation:

| Actions entry | Converted to |
|---------------|-------------|
| `actions["ctrl-s"] = fn` | `{ fn = fn, accept = true }` |
| `actions["ctrl-s"] = { fn1, fn2 }` | `{ fn = fn1, accept = true, chain = { fn2 } }` |
| `actions["ctrl-x"] = { fn, actions.resume }` | `{ fn = fn, reload = true }` (backward compat pattern) |

The `chain` field preserves the current behavior where `actions.act` iterates
over an array of functions. In the normalized representation, `fn` is the
primary function and `chain` holds additional functions to call sequentially
with the same `(entries, opts)` arguments. `actions.act` continues to handle
chained dispatch — no change to the post-exit accept flow.

**Note:** The `{ fn, actions.resume }` array pattern is detected during
normalization as a backward-compatible reload shorthand (`actions.resume`
triggers fzf restart). This conversion happens before `chain` processing.

| `actions["ctrl-x"] = { fn = fn, reload = true }` | `{ fn = fn, reload = true }` (preserved) |
| `actions["alt-i"] = { fn = fn, reuse = true }` | `{ fn = fn, reuse = true }` (preserved) |
| `actions["_internal"] = fn` | Not merged (underscore prefix = internal) |

### Accept Actions

Accept actions use fzf's `print(key)+accept` mechanism. They do NOT go through
the consolidated transform because:
- They need fzf to print the triggering key and exit
- The post-exit `actions.act` dispatch reads the printed key to select the
  handler
- This is fundamentally different from in-flight actions

### Hide Profile Support

The hide profile's `enrich` function converts `accept = true` actions to
`exec_silent = true`, wrapping the original function with `fzf.hide()`:

```lua
-- Hide profile enrich (adapted):
for k, bind in pairs(merged_binds) do
  if type(bind) == "table"
      and bind.accept
      and not bind.exec_silent
      and not bind.reload
      and not bind.noclose
      and not bind.reuse
      and not k:match("^_")
  then
    local original_fn = bind.fn
    bind.accept = nil
    bind.exec_silent = true
    bind.fn = function(...)
      fzf.hide()
      if original_fn then original_fn(...) end
      -- append to fzf history file if needed...
    end
  end
end
```

The explicit `accept = true` property makes this introspection cleaner than the
current approach (which infers accept by absence of other properties).

**Timing:** `enrich` runs during `config.normalize_opts`, before
`normalize_binds` generates the final `--bind` arguments. So `accept →
exec_silent` conversion happens before bind routing classification, and the
converted actions naturally end up in the transform handler instead of the
accept path.

## Normalization Flow

```text
User Config                         normalize_binds()                    Build Phase
───────────                         ─────────────────                    ───────────

binds = { ... }     ─┐                                                  create_fzf_binds()
                     │                                                       │
actions = { ... }   ─┤─► merge by precedence ─► classify each entry ─►  ┌───┴────┐
                     │   (binds > actions >      into 5 categories      │        │
keymap.fzf = { ... }─┤    keymap.fzf >                                  │  fzf   │
                     │    keymap.builtin)     ┌─ direct ──────────► direct --bind │
keymap.builtin={..} ─┘                       ├─ accept ──────────► print+accept  │
                                             ├─ transform ────────► consolidated │
                                             ├─ sigwinch ─────────► vim.keymap + │
                                             │                      resize event │
                                             └─ dropped ──────────► (skipped)    │
                                                                    └────────────┘
```

## What Changes From Current Code

| Current | New (fzf >= 0.59) |
|---------|-------------------|
| `create_fzf_binds` generates many `--bind` args | Generates few groups: direct, accept, key transform, event transforms |
| `convert_reload_actions` adds per-key binds + `load:+rebind(...)` | Reload logic inside transform handler (atomic) |
| `convert_exec_silent_actions` adds per-key binds | exec_silent logic inside transform handler |
| `setup_keybinds` cross-registers builtin↔fzf + `vim.keymap.set("t",...)` | Builtins in transform; SIGWINCH bridge only for neovim-only keys |
| `on_SIGWINCH` creates separate `resize:+transform:` | Resize is part of the consolidated transform |
| Multiple `pipe_wrap_fn` / `stringify_data` calls | Single `pipe_wrap_fn` registration for all complex binds |
| `actions.expect` generates `--expect` / `print(key)+accept` binds | Same mechanism, but sourced from unified bind representation |

## What Stays The Same

- **`setup_fzf_live_flags`**: `change:+transform:CMD` and `start:+transform:CMD`
  for live pickers stay separate (they use the reload command directly, not the
  dispatch handler)
- **`FZF_DEFAULT_COMMAND`**: Stays as environment variable for string commands
- **`actions.expect` / `actions.act`**: Continue to handle accept action
  post-exit dispatch
- **All code paths for fzf < 0.59**: Legacy mode is unchanged
- **`--expect` generation**: Accept actions still produce appropriate `--bind`
  entries via `actions.expect` or equivalent logic

## Edge Cases

1. **Duplicate keys across tables:** Resolved by precedence
   (binds > actions > keymap.fzf > keymap.builtin)
2. **Same key in different formats:** `ctrl-y` and `<C-y>` normalize to the same
   key via `normalize_key`; within the same table, last-write-wins (iteration
   order of Lua tables is non-deterministic, so users should avoid defining the
   same key in two formats in one table). Across tables, precedence
   (binds > actions > keymap.fzf > keymap.builtin) determines the winner.
3. **Provider overrides:** Provider-specific `binds`/`actions` merge with globals
   via `vim.tbl_deep_extend` (same as current behavior for `keymap`)
4. **Help/which-key:** `desc` field preserved on all bind types for the help
   window (`toggle-help` / `<F1>`)
5. **Live pickers:** `change:+transform:CMD` stays separate; if user also binds
   `change` event in `binds`, both coexist (fzf supports additive `+` prefix)
6. **Windows:** SIGWINCH (signal 28) unavailable; neovim-only keys dropped
   (same as current behavior)
7. **Internal actions:** `_underscore`-prefixed actions in `opts.actions` are not
   merged into binds (preserved for internal use)

## Version Requirements

- **fzf >= 0.59**: Full unified transform path (comma-separated key/event lists
  in `--bind`, which is the highest version dependency for the core feature)
- **fzf >= 0.53**: `print(key)+accept` for accept actions
- **fzf >= 0.50**: `$FZF_KEY` environment variable for dispatch
- **fzf >= 0.46**: `resize` event and `transform` action (SIGWINCH bridge)
- **fzf >= 0.45**: `transform` action
- **fzf >= 0.36**: Minimum supported version (current)

The unified transform path gates on **fzf >= 0.59** which implies all lower
version requirements are met. Individual features from newer fzf versions
(e.g., `change-header-lines` from 0.70, `bg-transform-*` from 0.63) can be
used opportunistically when the user's fzf version supports them.
