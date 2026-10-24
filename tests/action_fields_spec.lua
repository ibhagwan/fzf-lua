local helpers = require("fzf-lua.test.helpers")
local assert = helpers.assert

describe("Testing action field capture", function()
  it("adds an execute-silent recorder for reuse actions with field_index", function()
    local actions = require("fzf-lua.actions")
    local opts = {
      __FZF_VERSION = { 0, 53, 0 },
      actions = {
        ["ctrl-d"] = {
          fn = function() end,
          field_index = "{} $FZF_POS",
          reuse = true,
        },
      },
    }
    local expect_keys, binds = actions.expect(opts.actions, opts)
    assert.is.True(expect_keys == nil)
    assert.is.True(type(binds) == "table" and #binds == 1)
    local bind = binds[1]
    assert.is.True(bind:find("^ctrl%-d:execute%-silent%(") ~= nil)
    assert.is.True(bind:find("%+print%(ctrl%-d%)%+accept$") ~= nil)
    assert.is.True(bind:find("FZF_POS", 1, true) ~= nil)
  end)

  it("passes captured fields to the action callback", function()
    local actions = require("fzf-lua.actions")
    local captured
    local opts = {
      __FZF_VERSION = { 0, 53, 0 },
      actions = {
        ["ctrl-d"] = {
          fn = function(s) captured = s end,
          field_index = "{} $FZF_POS",
          reuse = true,
        },
      },
      __action_fields = {
        ["ctrl-d"] = { "the-line", 7 },
      },
    }
    actions.act({ "ctrl-d", "the-line" }, opts)
    assert.are.same(captured, { "the-line", 7 })
  end)

  it("keeps passing the entries when no fields were captured", function()
    local actions = require("fzf-lua.actions")
    local captured
    local opts = {
      __FZF_VERSION = { 0, 53, 0 },
      actions = {
        ["ctrl-d"] = {
          fn = function(s) captured = s end,
          field_index = "{} $FZF_POS",
          reuse = true,
        },
      },
    }
    actions.act({ "ctrl-d", "the-line" }, opts)
    assert.are.same(captured, { "the-line" })
  end)

  it("generates the capture bind when building a picker cli", function()
    local core = require("fzf-lua.core")
    local config = require("fzf-lua.config")
    local defaults = require("fzf-lua.defaults").defaults
    local opts = config.normalize_opts({
      cwd = vim.fn.getcwd(),
      actions = {
        ["ctrl-d"] = {
          fn = function() end,
          field_index = "{} $FZF_POS",
          reuse = true,
        },
      },
    }, defaults.git.commits)
    core.build_fzf_cli(opts)
    local found
    for _, bind in ipairs(opts.fzf_opts["--bind"]) do
      if bind:find("ctrl%-d:", 1, false) then
        found = bind
      end
    end
    assert.is.True(found ~= nil)
    assert.is.True(found:find("execute%-silent") ~= nil)
    assert.is.True(found:find("FZF_POS", 1, true) ~= nil)
  end)

  it("declares position capture for all git navigation actions", function()
    local defaults = require("fzf-lua.defaults").defaults
    assert.are.same(defaults.git.commits.actions["ctrl-d"].field_index, "{} $FZF_POS")
    assert.are.same(defaults.git.diff.actions["ctrl-d"].field_index, "{} $FZF_POS")
    assert.are.same(defaults.git.diff.actions["ctrl-q"].field_index, "{} $FZF_POS")
  end)
end)
