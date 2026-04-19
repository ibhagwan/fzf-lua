local helpers = require("fzf-lua.test.helpers")
local assert = helpers.assert
local eq = assert.are.same

local binds = require("fzf-lua.binds")

-- Wrapper for normalize_binds
local function nb(opts)
  return binds.normalize_binds(opts)
end

describe("binds.normalize_binds", function()

  -- ================================================================
  -- key normalization
  -- ================================================================

  describe("key normalization", function()
    it("converts neovim format to fzf format", function()
      local m = nb({ keymap = { builtin = { ["<C-y>"] = "abort" } } })
      eq(m["ctrl-y"].fzf_action, "abort")
    end)

    it("preserves raw fzf format keys", function()
      local m = nb({ keymap = { fzf = { ["ctrl-y"] = "abort" } } })
      eq(m["ctrl-y"].fzf_action, "abort")
    end)

    it("normalizes <C-Enter> to ctrl-enter", function()
      local m = nb({ keymap = { builtin = { ["<C-Enter>"] = "hide" } } })
      eq(m["ctrl-enter"].builtin, "hide")
      eq(m["ctrl-enter"]._nvim_key, "<C-Enter>")
    end)

    it("normalizes raw ctrl-enter to ctrl-enter", function()
      local m = nb({ keymap = { fzf = { ["ctrl-enter"] = "abort" } } })
      eq(m["ctrl-enter"].fzf_action, "abort")
    end)

    it("collapses shift+letter to uppercase (alt-J)", function()
      local m = nb({ keymap = { builtin = { ["<M-S-j>"] = "preview-down" } } })
      eq(m["alt-J"].builtin, "preview-down")
    end)

    it("preserves shift+special as shift-down", function()
      local m = nb({ keymap = { builtin = { ["<S-Down>"] = "preview-page-down" } } })
      eq(m["shift-down"].builtin, "preview-page-down")
    end)

    it("normalizes <M-Esc> to alt-esc", function()
      local m = nb({ keymap = { builtin = { ["<M-Esc>"] = "hide" } } })
      eq(m["alt-esc"].builtin, "hide")
    end)

    it("handles ctrl-z (no transformation)", function()
      local m = nb({ keymap = { fzf = { ["ctrl-z"] = "abort" } } })
      eq(m["ctrl-z"].fzf_action, "abort")
    end)

    it("handles function keys (f1-f12)", function()
      local m = nb({ keymap = { builtin = { ["<F4>"] = "toggle-preview" } } })
      eq(m["f4"].builtin, "toggle-preview")
      eq(m["f4"]._nvim_key, "<F4>")
    end)

    it("handles alt keys", function()
      local m = nb({ keymap = { fzf = { ["alt-a"] = "toggle-all" } } })
      eq(m["alt-a"].fzf_action, "toggle-all")
    end)
  end)

  -- ================================================================
  -- value normalization
  -- ================================================================

  describe("value normalization: strings", function()
    it("fzf action string → fzf_action", function()
      local m = nb({ keymap = { fzf = { ["ctrl-z"] = "abort" } } })
      eq(m["ctrl-z"].fzf_action, "abort")
      eq(m["ctrl-z"]._source, "keymap.fzf")
    end)

    it("builtin action string → builtin", function()
      local m = nb({ keymap = { builtin = { ["<F4>"] = "toggle-preview" } } })
      eq(m["f4"].builtin, "toggle-preview")
    end)

    it("preview-* builtin action → builtin", function()
      local m = nb({ keymap = { builtin = { ["<S-Down>"] = "preview-page-down" } } })
      eq(m["shift-down"].builtin, "preview-page-down")
    end)

    it("hide builtin action → builtin", function()
      local m = nb({ keymap = { builtin = { ["<M-Esc>"] = "hide" } } })
      eq(m["alt-esc"].builtin, "hide")
    end)
  end)

  describe("value normalization: functions", function()
    it("function from actions → accept=true", function()
      local fn = function() end
      local m = nb({ actions = { enter = fn } })
      eq(m["enter"].accept, true)
      eq(type(m["enter"].fn), "function")
    end)

    it("function from keymap.fzf → exec_silent=true", function()
      local fn = function() end
      local m = nb({ keymap = { fzf = { enter = fn } } })
      eq(m["enter"].exec_silent, true)
      eq(type(m["enter"].fn), "function")
    end)

    it("function from keymap.builtin → accept=true", function()
      local fn = function() end
      local m = nb({ keymap = { builtin = { ["<C-j>"] = fn } } })
      eq(m["ctrl-j"].accept, true)
    end)

    it("function from binds → accept=true", function()
      local fn = function() end
      local m = nb({ binds = { enter = fn } })
      eq(m["enter"].accept, true)
    end)
  end)

  describe("value normalization: tables with fn", function()
    it("table with fn → metadata preserved", function()
      local fn = function() end
      local m = nb({ actions = { enter = { fn = fn, desc = "edit" } } })
      eq(type(m["enter"].fn), "function")
      eq(m["enter"].desc, "edit")
    end)

    it("table with fn and exec_silent → exec_silent preserved", function()
      local fn = function() end
      local m = nb({ actions = { enter = { fn = fn, exec_silent = true } } })
      eq(m["enter"].exec_silent, true)
      eq(m["enter"].accept, nil)
    end)

    it("table with fn and reload → reload preserved", function()
      local fn = function() end
      local m = nb({ actions = { enter = { fn = fn, reload = true } } })
      eq(m["enter"].reload, true)
    end)

    it("table with fn and reuse → reuse preserved", function()
      local fn = function() end
      local m = nb({ actions = { enter = { fn = fn, reuse = "test" } } })
      eq(m["enter"].reuse, "test")
    end)

    it("table with fn and prefix/postfix → preserved", function()
      local fn = function() end
      local m = nb({ actions = { enter = { fn = fn, reload = true, prefix = "sel+", postfix = "+acc" } } })
      eq(m["enter"].prefix, "sel+")
      eq(m["enter"].postfix, "+acc")
    end)

    it("table with fn and header/field_index → preserved", function()
      local fn = function() end
      local m = nb({ actions = { enter = { fn = fn, header = "files", field_index = "{+}" } } })
      eq(m["enter"].header, "files")
      eq(m["enter"].field_index, "{+}")
    end)
  end)

  describe("value normalization: table with string [1]", function()
    it("fzf action string [1] → fzf_action + desc", function()
      local m = nb({ keymap = { fzf = { ["alt-g"] = { "first", desc = "Go to first" } } } })
      eq(m["alt-g"].fzf_action, "first")
      eq(m["alt-g"].desc, "Go to first")
    end)

    it("builtin action string [1] → builtin + desc", function()
      local m = nb({ keymap = { builtin = { ["<F4>"] = { "toggle-preview", desc = "Toggle" } } } })
      eq(m["f4"].builtin, "toggle-preview")
      eq(m["f4"].desc, "Toggle")
    end)

    it("string [1] without desc → fzf_action", function()
      local m = nb({ keymap = { fzf = { ["alt-g"] = { "first" } } } })
      eq(m["alt-g"].fzf_action, "first")
      eq(m["alt-g"].desc, nil)
    end)
  end)

  describe("value normalization: function arrays (chain)", function()
    it("array of functions → accept + chain", function()
      local fn1 = function() end
      local fn2 = function() end
      local m = nb({ actions = { enter = { fn1, fn2 } } })
      eq(m["enter"].accept, true)
      eq(type(m["enter"].fn), "function")
      eq(#m["enter"].chain, 1)
    end)

    it("array of 3 functions → accept + chain of 2", function()
      local fn1, fn2, fn3 = function() end, function() end, function() end
      local m = nb({ actions = { enter = { fn1, fn2, fn3 } } })
      eq(#m["enter"].chain, 2)
    end)

    it("{ fn, actions.resume } → reload (backward compat)", function()
      local fn = function() end
      local resume = require("fzf-lua.actions").resume
      local m = nb({ actions = { enter = { fn, resume } } })
      eq(m["enter"].reload, true)
      eq(m["enter"].accept, nil)
    end)

    it("single function array → accept, no chain", function()
      local fn = function() end
      local m = nb({ actions = { enter = { fn } } })
      eq(m["enter"].accept, true)
      eq(m["enter"].chain, nil)
    end)
  end)

  describe("value normalization: removal", function()
    it("false value → nil (removed)", function()
      local m = nb({ keymap = { fzf = { enter = false } } })
      eq(m["enter"], nil)
    end)

    it("nil value → nil (removed)", function()
      local m = nb({ keymap = { fzf = { enter = nil } } })
      eq(m["enter"], nil)
    end)

    it("true in keymap.builtin → nil (skipped)", function()
      local m = nb({ keymap = { builtin = { ["<F4>"] = true } } })
      eq(m["f4"], nil)
    end)
  end)

  -- ================================================================
  -- merge precedence
  -- ================================================================

  describe("merge precedence", function()
    it("binds > actions", function()
      local m = nb({
        actions = { enter = function() end },
        binds = { enter = "abort" },
      })
      eq(m["enter"].fzf_action, "abort")
      eq(m["enter"]._source, "binds")
    end)

    it("binds > keymap.fzf", function()
      local m = nb({
        keymap = { fzf = { enter = "abort" } },
        binds = { enter = "first" },
      })
      eq(m["enter"].fzf_action, "first")
    end)

    it("binds > keymap.builtin", function()
      local m = nb({
        keymap = { builtin = { ["<F4>"] = "toggle-preview" } },
        binds = { f4 = "abort" },
      })
      eq(m["f4"].fzf_action, "abort")
    end)

    it("actions > keymap.fzf", function()
      local m = nb({
        keymap = { fzf = { enter = "abort" } },
        actions = { enter = function() end },
      })
      eq(m["enter"].accept, true)
      eq(m["enter"]._source, "actions")
    end)

    it("actions > keymap.builtin", function()
      local m = nb({
        keymap = { builtin = { ["<C-y>"] = "abort" } },
        actions = { ["ctrl-y"] = function() end },
      })
      eq(m["ctrl-y"].accept, true)
    end)

    it("keymap.fzf > keymap.builtin", function()
      local m = nb({
        keymap = {
          builtin = { ["<C-y>"] = "preview-page-down" },
          fzf = { ["ctrl-y"] = "half-page-down" },
        },
      })
      eq(m["ctrl-y"].fzf_action, "half-page-down")
      eq(m["ctrl-y"]._source, "keymap.fzf")
    end)

    it("only keymap.builtin → lowest precedence", function()
      local m = nb({
        keymap = { builtin = { ["<C-y>"] = "preview-page-down" } },
      })
      eq(m["ctrl-y"].builtin, "preview-page-down")
      eq(m["ctrl-y"]._source, "keymap.builtin")
    end)

    it("same key different format resolves to one entry", function()
      local m = nb({
        keymap = {
          builtin = { ["<C-y>"] = "preview-page-down" },
          fzf = { ["ctrl-y"] = "abort" },
        },
      })
      eq(m["ctrl-y"].fzf_action, "abort")
      eq(#vim.tbl_keys(m), 1)
    end)
  end)

  -- ================================================================
  -- unbind
  -- ================================================================

  describe("unbind (value=false)", function()
    it("removes key from merged", function()
      local m = nb({
        keymap = { fzf = { enter = "abort" } },
        binds = { enter = false },
      })
      eq(m["enter"], nil)
    end)

    it("removes even higher-precedence source", function()
      local m = nb({
        actions = { enter = function() end },
        binds = { enter = false },
      })
      eq(m["enter"], nil)
    end)

    it("removes with neovim format key", function()
      local m = nb({
        keymap = { builtin = { ["<C-Enter>"] = "hide" } },
        binds = { ["<C-Enter>"] = false },
      })
      eq(m["ctrl-enter"], nil)
    end)

    it("clears opts.actions for unbound key", function()
      local opts = {
        actions = { enter = function() end },
        binds = { enter = false },
      }
      nb(opts)
      eq(opts.actions.enter, nil)
    end)

    it("clears opts.keymap.fzf for unbound key", function()
      local opts = {
        keymap = { fzf = { enter = "abort" } },
        binds = { enter = false },
      }
      nb(opts)
      eq(opts.keymap.fzf.enter, nil)
    end)

    it("unbind does not affect other keys", function()
      local m = nb({
        keymap = { fzf = { enter = "abort", ["ctrl-z"] = "abort" } },
        binds = { enter = false },
      })
      eq(m["enter"], nil)
      eq(m["ctrl-z"].fzf_action, "abort")
    end)
  end)

  -- ================================================================
  -- source tracking
  -- ================================================================

  describe("source tracking", function()
    it("keymap.builtin: _source and _nvim_key", function()
      local m = nb({ keymap = { builtin = { ["<F4>"] = "toggle-preview" } } })
      eq(m["f4"]._source, "keymap.builtin")
      eq(m["f4"]._nvim_key, "<F4>")
    end)

    it("keymap.fzf: _source and _nvim_key", function()
      local m = nb({ keymap = { fzf = { ["ctrl-z"] = "abort" } } })
      eq(m["ctrl-z"]._source, "keymap.fzf")
      eq(m["ctrl-z"]._nvim_key, "ctrl-z")
    end)

    it("actions: _source and _nvim_key", function()
      local m = nb({ actions = { enter = function() end } })
      eq(m["enter"]._source, "actions")
      eq(m["enter"]._nvim_key, "enter")
    end)

    it("binds: _source and _nvim_key", function()
      local m = nb({ binds = { ["ctrl-z"] = "abort" } })
      eq(m["ctrl-z"]._source, "binds")
      eq(m["ctrl-z"]._nvim_key, "ctrl-z")
    end)

    it("override updates _source", function()
      local m = nb({
        keymap = { builtin = { ["<F4>"] = "toggle-preview" } },
        binds = { f4 = "abort" },
      })
      eq(m["f4"]._source, "binds")
    end)
  end)

  -- ================================================================
  -- empty / missing tables
  -- ================================================================

  describe("empty and missing tables", function()
    it("empty opts → empty merged", function()
      local m = nb({})
      eq(#vim.tbl_keys(m), 0)
    end)

    it("empty keymap tables → empty merged", function()
      local m = nb({ keymap = { fzf = {}, builtin = {} } })
      eq(#vim.tbl_keys(m), 0)
    end)

    it("empty actions → empty merged", function()
      local m = nb({ actions = {} })
      eq(#vim.tbl_keys(m), 0)
    end)

    it("empty binds → empty merged", function()
      local m = nb({ binds = {} })
      eq(#vim.tbl_keys(m), 0)
    end)

    it("nil keymap → empty merged", function()
      local m = nb({ keymap = nil })
      eq(#vim.tbl_keys(m), 0)
    end)
  end)

  -- ================================================================
  -- internal actions
  -- ================================================================

  describe("internal actions", function()
    it("underscore prefix → not merged", function()
      local m = nb({
        actions = { _internal = function() end, enter = function() end },
      })
      eq(m["_internal"], nil)
      eq(m["enter"].accept, true)
    end)

    it("underscore prefix with table → not merged", function()
      local m = nb({
        actions = { _resume = { fn = function() end, reload = true } },
      })
      eq(m["_resume"], nil)
    end)
  end)

  -- ================================================================
  -- fzf events
  -- ================================================================

  describe("fzf events", function()
    it("load event fn → event=true", function()
      local fn = function() end
      local m = nb({ binds = { load = fn } })
      eq(m["load"].event, true)
      eq(type(m["load"].fn), "function")
    end)

    it("resize event table → event=true + field_index", function()
      local fn = function() end
      local m = nb({ binds = { resize = { fn = fn, field_index = "$FZF_PROMPT" } } })
      eq(m["resize"].event, true)
      eq(m["resize"].field_index, "$FZF_PROMPT")
    end)

    it("start event with exec_silent → both flags", function()
      local fn = function() end
      local m = nb({ binds = { start = { fn = fn, exec_silent = true } } })
      eq(m["start"].event, true)
      eq(m["start"].exec_silent, true)
    end)

    it("non-event key → event=nil", function()
      local fn = function() end
      local m = nb({ binds = { enter = fn } })
      eq(m["enter"].event, nil)
      eq(m["enter"].accept, true)
    end)

    it("known fzf events: load, start, resize, change, focus, result", function()
      local fn = function() end
      local m = nb({
        binds = {
          load = fn, start = fn, resize = fn,
          change = fn, focus = fn, result = fn,
        },
      })
      eq(m["load"].event, true)
      eq(m["start"].event, true)
      eq(m["resize"].event, true)
      eq(m["change"].event, true)
      eq(m["focus"].event, true)
      eq(m["result"].event, true)
    end)
  end)

  -- ================================================================
  -- complex real-world scenarios
  -- ================================================================

  describe("complex scenarios", function()
    it("mixed sources coexist on different keys", function()
      local fn = function() end
      local opts = {
        keymap = { builtin = { ["<F1>"] = "toggle-help" } },
        actions = { enter = fn },
        binds = { ["ctrl-z"] = "abort" },
      }
      -- Add keymap.fzf separately since Lua tables can't have duplicate keys
      opts.keymap.fzf = { ["ctrl-f"] = "half-page-down" }
      local m = nb(opts)
      eq(m["f1"].builtin, "toggle-help")
      eq(m["ctrl-f"].fzf_action, "half-page-down")
      eq(m["enter"].accept, true)
      eq(m["ctrl-z"].fzf_action, "abort")
    end)

    it("unbind removes key across all layers", function()
      local opts = {
        keymap = { builtin = { ["<F1>"] = "toggle-help" } },
        actions = { f1 = function() end },
        binds = { f1 = false },
      }
      opts.keymap.fzf = { f1 = "abort" }
      local m = nb(opts)
      eq(m["f1"], nil)
      eq(opts.actions.f1, nil)
      eq(opts.keymap.fzf.f1, nil)
    end)

    it("mixed direct/accept/transform entries", function()
      local fn = function() end
      local m = nb({
        binds = {
          ["ctrl-z"] = "abort",  -- direct
          enter = fn,            -- accept
          load = fn,             -- transform (event)
        },
      })
      eq(m["ctrl-z"].fzf_action, "abort")
      eq(m["enter"].accept, true)
      eq(m["load"].event, true)
    end)
  end)
end)
