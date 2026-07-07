---@diagnostic disable: unused-local
local MiniTest = require("mini.test")
local helpers = require("fzf-lua.test.helpers")
local eq = helpers.expect.equality
local new_set = MiniTest.new_set

local T = new_set()

T["codeaction"] = new_set()

T["codeaction"]["preview does not mutate same-position text edits"] = function()
  local utils = require("fzf-lua.utils")
  local codeaction = require("fzf-lua.previewer.codeaction")
  local original_lsp_get_clients = utils.lsp_get_clients
  local bufnr = vim.api.nvim_create_buf(true, true)
  local text_edits = {
    {
      range = {
        start = { line = 0, character = 7 },
        ["end"] = { line = 0, character = 24 },
      },
      newText = "strings.CutSuffix",
    },
    {
      range = {
        start = { line = 0, character = 7 },
        ["end"] = { line = 0, character = 24 },
      },
      newText = "strings.TrimSuffix",
    },
  }
  local before = vim.deepcopy(text_edits)

  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
    "if strings.HasSuffix(name, suffix) {",
    "\treturn strings.TrimSuffix(name, suffix)",
    "}",
  })

  ---duplication is caused by the stubbign logic.
  ---@diagnostic disable-next-line: duplicate-set-field
  utils.lsp_get_clients = function(opts)
    if opts.id == 1 then
      return {
        {
          offset_encoding = "utf-16",
          dynamic_capabilities = { get = function() end },
          supports_method = function() return false end,
          server_capabilities = {},
        },
      }
    end
    return original_lsp_get_clients(opts)
  end

  local ok, err = pcall(function()
    local uri = vim.uri_from_bufnr(bufnr)
    ---@diagnostic disable-next-line: missing-fields, param-type-mismatch
    codeaction.builtin.preview_action_tuple({
      opts = {
        _items = {
          {
            ctx = { client_id = 1, bufnr = bufnr },
            action = { edit = { changes = { [uri] = text_edits } } },
          },
        },
      },
      diff_opts = { ctxlen = 3 },
      _resolved_actions = { false },
    }, 1)
  end)
  utils.lsp_get_clients = original_lsp_get_clients
  vim.api.nvim_buf_delete(bufnr, { force = true })

  if not ok then error(err) end
  eq(text_edits, before)
end

return T
