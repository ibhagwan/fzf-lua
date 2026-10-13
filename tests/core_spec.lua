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
end)
