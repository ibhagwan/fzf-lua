local helpers = require("fzf-lua.test.helpers")
local assert = helpers.assert

local libuv = require("fzf-lua.libuv")

describe("Testing core cli construction", function()
  it("records unquoted raw values for pre-escaped fzf_opts", function()
    local core = require("fzf-lua.core")
    local config = require("fzf-lua.config")
    local defaults = require("fzf-lua.defaults").defaults
    local opts = config.normalize_opts({
      cwd = vim.fn.getcwd(),
      fzf_opts = { ["--header"] = '"foo bar"' },
    }, defaults.files)
    local cli_args, segments = core.build_fzf_cli(opts)
    -- cli_args keeps the user-escaped string unchanged
    local found_escaped = false
    for _, a in ipairs(cli_args) do
      if a == '"foo bar"' then found_escaped = true end
    end
    assert.is.True(found_escaped)
    -- segments record the unquoted value for native (PowerShell) handling
    local found_raw = false
    for _, elem in ipairs(segments) do
      if #elem == 1 and elem[1].text == "foo bar" and elem[1].escape == false then
        found_raw = true
      end
    end
    assert.is.True(found_raw)
  end)

  it("decodes pre-escaped fzf_opts values for the win raw argv", function()
    local core = require("fzf-lua.core")
    local config = require("fzf-lua.config")
    local utils = require("fzf-lua.utils")
    local defaults = require("fzf-lua.defaults").defaults
    -- a pre-escaped value with an inner escaped quote (recognized as escaped
    -- on all platforms), e.g. a user pre-escaping `--header "say \"hi\""`
    local escaped = [["say \"hi\""]]
    local opts = config.normalize_opts({
      cwd = vim.fn.getcwd(),
      fzf_opts = { ["--header"] = escaped },
    }, defaults.files)
    local old = utils.__IS_WINDOWS
    utils.__IS_WINDOWS = true
    local ok, cli_args, segments = pcall(core.build_fzf_cli, opts)
    utils.__IS_WINDOWS = old
    if not ok then error(cli_args) end
    -- cli_args keeps the user-escaped string unchanged
    local found_escaped = false
    for _, a in ipairs(cli_args) do
      if a == escaped then found_escaped = true end
    end
    assert.is.True(found_escaped)
    -- the shell-less raw argv must receive the decoded value: `cmd.exe` +
    -- argv parsing drops the quotes and collapses `\"` to a literal `"`,
    -- while stripping only the outer quotes leaves `say \"hi\"` behind
    local found_raw = false
    for _, elem in ipairs(segments) do
      if #elem == 1 and elem[1].text == 'say "hi"' and elem[1].escape == false then
        found_raw = true
      end
    end
    assert.is.True(found_raw)
  end)

  it("splits fzf_cli_args with spaces into separate segment elements", function()
    local core = require("fzf-lua.core")
    local config = require("fzf-lua.config")
    local defaults = require("fzf-lua.defaults").defaults
    local opts = config.normalize_opts({
      cwd = vim.fn.getcwd(),
      fzf_cli_args = { "--height 40%", "--reverse" },
    }, defaults.files)
    local cli_args, segments = core.build_fzf_cli(opts)
    -- cli_args keeps the original compound strings
    local found_compound = false
    for _, a in ipairs(cli_args) do
      if a == "--height 40%" then found_compound = true end
    end
    assert.is.True(found_compound)
    -- segments split into individual argv tokens
    local texts = {}
    for _, elem in ipairs(segments) do
      if #elem == 1 then table.insert(texts, elem[1].text) end
    end
    assert.is.True(vim.tbl_contains(texts, "--height"))
    assert.is.True(vim.tbl_contains(texts, "40%"))
    assert.is.True(vim.tbl_contains(texts, "--reverse"))
  end)

  it("splits __raw_cli compound prefixes into separate CliElements", function()
    local core = require("fzf-lua.core")
    local config = require("fzf-lua.config")
    local defaults = require("fzf-lua.defaults").defaults
    local opts = config.normalize_opts({
      cwd = vim.fn.getcwd(),
      _fzf_cli_args = {
        libuv.cli_raw_arg("--interactive --cmd ", "reload:cmd"),
      },
    }, defaults.files)
    local cli_args, segments = core.build_fzf_cli(opts)
    -- cli_args keeps the legacy escaped string form
    local found_escaped = false
    for _, a in ipairs(cli_args) do
      if a:match("^%-%-interactive %-%-cmd ") then found_escaped = true end
    end
    assert.is.True(found_escaped)
    -- each prefix token and the value are separate argument elements
    local function has_single(text, escape)
      for _, elem in ipairs(segments) do
        if #elem == 1 and elem[1].text == text and elem[1].escape == escape then
          return true
        end
      end
      return false
    end
    assert.is.True(has_single("--interactive", false))
    assert.is.True(has_single("--cmd", false))
    assert.is.True(has_single("reload:cmd", true))
  end)

  it("keeps simple fused __raw_cli prefixes joined to their value", function()
    local core = require("fzf-lua.core")
    local config = require("fzf-lua.config")
    local defaults = require("fzf-lua.defaults").defaults
    local opts = config.normalize_opts({
      cwd = vim.fn.getcwd(),
      _fzf_cli_args = {
        libuv.cli_raw_arg("--bind=", "ctrl-t:reload:cmd"),
      },
    }, defaults.files)
    local _cli_args, segments = core.build_fzf_cli(opts)
    local found = false
    for _, elem in ipairs(segments) do
      if #elem == 2
          and elem[1].text == "--bind=" and elem[1].escape == false
          and elem[2].text == "ctrl-t:reload:cmd" and elem[2].escape == true then
        found = true
        break
      end
    end
    assert.is.True(found)
  end)

  it("selects the resume fallback for skim and forced fallback", function()
    local core = require("fzf-lua.core")
    local actions = require("fzf-lua.actions")
    local assert_fallback = function(opts)
      opts.actions = { ["ctrl-x"] = { fn = function() end, reload = true } }
      opts.keymap = { fzf = {} }
      opts = core.convert_reload_actions("true", opts)
      -- old-style action: { <fn>, actions.resume } restarts the picker
      assert.is.True(type(opts.actions["ctrl-x"]) == "table")
      assert.is.True(type(opts.actions["ctrl-x"][1]) == "function")
      assert.is.True(opts.actions["ctrl-x"][2] == actions.resume)
    end
    -- skim supports `reload` but not `rebind`, so it must use the fallback
    assert_fallback({ __SK_VERSION = { 5, 6, 6 } })
    -- internal override used by tests to exercise the fallback on fzf
    assert_fallback({ __FZF_VERSION = { 0, 74, 5 }, _reload_fallback = true })
  end)
end)
