local helpers = require("fzf-lua.test.helpers")
local expect = helpers.assert
local config = require("fzf-lua.config")
local defaults = require("fzf-lua.defaults").defaults

---@param actions fzf-lua.config.Actions
---@return fzf-lua.config.Resolved
local function resolved_opts(actions)
  local opts = config.normalize_opts({}, defaults.git.commits)
  ---@cast opts fzf-lua.config.Resolved
  opts.actions = actions
  opts.__FZF_VERSION = { 0, 53, 0 }
  return opts
end

describe("Testing action field capture", function()
  it("adds an execute-silent recorder for reuse actions with field_index", function()
    local actions = require("fzf-lua.actions")
    local opts = resolved_opts({
      ["ctrl-d"] = {
        fn = function() end,
        field_index = "{} $FZF_POS",
        reuse = true,
      },
    })
    local expect_keys, binds = actions.expect(opts.actions, opts)
    expect.is.True(expect_keys == nil)
    expect.is.True(binds ~= nil and #binds == 1)
    ---@cast binds string[]
    local bind = assert(binds[1])
    expect.is.True(bind:find("^ctrl%-d:print%(ctrl%-d%)%+execute%-silent%(") ~= nil)
    expect.is.True(bind:find("%+accept$") ~= nil)
    expect.is.True(bind:find("FZF_POS", 1, true) ~= nil)
  end)

  it("runs selection-changing prefixes before recording fields", function()
    local actions = require("fzf-lua.actions")
    local opts = resolved_opts({
      ["ctrl-a"] = {
        fn = function() end,
        field_index = "{} $FZF_POS",
        prefix = "select-all",
        reuse = true,
      },
    })
    local _, binds = actions.expect(opts.actions, opts)
    expect.is.True(binds ~= nil and #binds == 1)
    ---@cast binds string[]
    local bind = assert(binds[1])
    local prefix_pos = assert(bind:find("select%-all"))
    local recorder_pos = assert(bind:find("execute%-silent"))
    expect.is.True(prefix_pos < recorder_pos)
  end)

  it("passes captured fields to the action callback", function()
    local actions = require("fzf-lua.actions")
    ---@type string[]?
    local captured
    local opts = resolved_opts({
      ["ctrl-d"] = {
        fn = function(s) captured = s end,
        field_index = "{} $FZF_POS",
        reuse = true,
      },
    })
    opts.__action_fields = {
      ["ctrl-d"] = { "the-line", "7" },
    }
    actions.act({ "ctrl-d", "the-line" }, opts)
    expect.are.same(captured, { "the-line", "7" })
  end)

  it("treats all-empty captured fields as absent", function()
    local actions = require("fzf-lua.actions")
    local shell = require("fzf-lua.shell")
    ---@type string[]?
    local captured
    ---@type function?
    local recorder
    local stringify_data2 = shell.stringify_data2
    ---@diagnostic disable-next-line: duplicate-set-field
    shell.stringify_data2 = function(fn)
      recorder = fn
      return "recorder"
    end
    local ok, err = pcall(function()
      local opts = resolved_opts({
        ["ctrl-d"] = {
          fn = function(s) captured = s end,
          field_index = "{} $FZF_POS",
          reuse = true,
        },
      })
      local _, binds = actions.expect(opts.actions, opts)
      expect.is.True(binds ~= nil and #binds == 1)
      expect.is.True(recorder ~= nil)
      ---@cast recorder function
      recorder({ "the-line", "7" })
      local action_fields = assert(opts.__action_fields)
      expect.are.same(action_fields["ctrl-d"], { "the-line", "7" })
      recorder({ "", "" })
      expect.are.same(action_fields["ctrl-d"], nil)
      actions.act({ "ctrl-d" }, opts)
      expect.are.same(captured, {})
    end)
    shell.stringify_data2 = stringify_data2
    if not ok then error(err) end
  end)

  it("keeps passing the entries when no fields were captured", function()
    local actions = require("fzf-lua.actions")
    ---@type string[]?
    local captured
    local opts = resolved_opts({
      ["ctrl-d"] = {
        fn = function(s) captured = s end,
        field_index = "{} $FZF_POS",
        reuse = true,
      },
    })
    actions.act({ "ctrl-d", "the-line" }, opts)
    expect.are.same(captured, { "the-line" })
  end)

  it("generates the capture bind when building a picker cli", function()
    local core = require("fzf-lua.core")
    local opts = resolved_opts({
      ["ctrl-d"] = {
        fn = function() end,
        field_index = "{} $FZF_POS",
        reuse = true,
      },
    })
    opts.cwd = vim.fn.getcwd()
    core.build_fzf_cli(opts)
    ---@type string[]
    local binds = opts.fzf_opts["--bind"]
    ---@cast binds string[]
    local found
    for _, bind in ipairs(binds) do
      if bind:find("ctrl%-d:") then
        found = bind
      end
    end
    expect.is.True(found ~= nil)
    ---@cast found string
    expect.is.True(found:find("execute%-silent") ~= nil)
    expect.is.True(found:find("FZF_POS", 1, true) ~= nil)
  end)

  it("declares position capture for all git navigation actions", function()
    local commits = defaults.git.commits.actions
    local diff = defaults.git.diff.actions
    local ctrl_d_commits = commits["ctrl-d"]
    local ctrl_d_diff = diff["ctrl-d"]
    local ctrl_q_diff = diff["ctrl-q"]
    ---@cast ctrl_d_commits fzf-lua.ActionSpec
    ---@cast ctrl_d_diff fzf-lua.ActionSpec
    ---@cast ctrl_q_diff fzf-lua.ActionSpec
    -- fzf runs bind commands through `cmd.exe` on Windows, which expands
    -- `%VAR%` (not `$VAR`) in the generated `execute-silent` recorder
    local pos = helpers.IS_WIN() and "%FZF_POS%" or "$FZF_POS"
    expect.are.same(ctrl_d_commits.field_index, "{} " .. pos)
    expect.are.same(ctrl_d_diff.field_index, "{} " .. pos)
    expect.are.same(ctrl_q_diff.field_index, "{} " .. pos)
  end)
end)
