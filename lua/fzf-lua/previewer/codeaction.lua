local utils = require "fzf-lua.utils"
local shell = require "fzf-lua.shell"
local native = require("fzf-lua.previewer.fzf")
local builtin = require("fzf-lua.previewer.builtin")

local M = {}

-- Thanks to @aznhe21's `actions-preview.nvim` for the diff generation code
-- https://github.com/aznhe21/actions-preview.nvim/blob/master/lua/actions-preview/action.lua
local function get_lines(bufnr)
  vim.fn.bufload(bufnr)
  return vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
end

local function get_eol(bufnr)
  local ff = vim.bo[bufnr].fileformat
  if ff == "dos" then
    return "\r\n"
  elseif ff == "unix" then
    return "\n"
  elseif ff == "mac" then
    return "\r"
  else
    error("invalid fileformat")
  end
end

local function diff_text_edits(text_edits, bufnr, offset_encoding, diff_opts)
  local eol = get_eol(bufnr)
  local orig_lines = get_lines(bufnr)
  local tmpbuf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(tmpbuf, 0, -1, false, orig_lines)
  vim.lsp.util.apply_text_edits(text_edits, tmpbuf, offset_encoding)
  local new_lines = get_lines(tmpbuf)
  vim.api.nvim_buf_delete(tmpbuf, { force = true })
  ---@diagnostic disable-next-line: deprecated
  local diff = (vim.diff or vim.text.diff)(
    table.concat(orig_lines, eol) .. eol,
    table.concat(new_lines, eol) .. eol,
    diff_opts)
  -- Windows: some LSPs use "\n" for EOL (e.g clangd)
  -- remove both "\n" and "\r\n" (#1172)
  return utils.strsplit(vim.trim(diff), "\r?\n")
end

-- based on `vim.lsp.util.apply_text_document_edit`
-- https://github.com/neovim/neovim/blob/v0.9.2/runtime/lua/vim/lsp/util.lua#L576
local function diff_text_document_edit(text_document_edit, offset_encoding, diff_opts)
  local text_document = text_document_edit.textDocument
  local bufnr = vim.uri_to_bufnr(text_document.uri)

  return diff_text_edits(text_document_edit.edits, bufnr, offset_encoding, diff_opts)
end

-- based on `vim.lsp.util.apply_workspace_edit`
-- https://github.com/neovim/neovim/blob/v0.9.4/runtime/lua/vim/lsp/util.lua#L848
local function diff_workspace_edit(workspace_edit, offset_encoding, diff_opts)
  local diff = {}
  if workspace_edit.documentChanges then
    for _, change in ipairs(workspace_edit.documentChanges) do
      -- imitate git diff
      if change.kind == "rename" then
        local old_path = vim.fn.fnamemodify(vim.uri_to_fname(change.oldUri), ":.")
        local new_path = vim.fn.fnamemodify(vim.uri_to_fname(change.newUri), ":.")

        table.insert(diff, string.format("diff --code-actions a/%s b/%s", old_path, new_path))
        table.insert(diff, string.format("rename from %s", old_path))
        table.insert(diff, string.format("rename to %s", new_path))
        table.insert(diff, "")
      elseif change.kind == "create" then
        local path = vim.fn.fnamemodify(vim.uri_to_fname(change.uri), ":.")

        table.insert(diff, string.format("diff --code-actions a/%s b/%s", path, path))
        -- delta needs file mode
        table.insert(diff, "new file mode 100644")
        -- diff-so-fancy needs index
        table.insert(diff, "index 0000000..fffffff")
        table.insert(diff, "")
      elseif change.kind == "delete" then
        local path = vim.fn.fnamemodify(vim.uri_to_fname(change.uri), ":.")

        table.insert(diff, string.format("diff --code-actions a/%s b/%s", path, path))
        table.insert(diff, string.format("--- a/%s", path))
        table.insert(diff, "+++ /dev/null")
        table.insert(diff, "")
      elseif change.kind then
        -- do nothing
      else
        local path = vim.fn.fnamemodify(vim.uri_to_fname(change.textDocument.uri), ":.")

        table.insert(diff, string.format("diff --code-actions a/%s b/%s", path, path))
        table.insert(diff, string.format("--- a/%s", path))
        table.insert(diff, string.format("+++ b/%s", path))
        for _, l in ipairs(diff_text_document_edit(change, offset_encoding, diff_opts) or {}) do
          table.insert(diff, l)
        end
        table.insert(diff, "")
        table.insert(diff, "")
      end
    end

    return diff
  end

  local all_changes = workspace_edit.changes
  if all_changes and not utils.tbl_isempty(all_changes) then
    for uri, changes in pairs(all_changes) do
      local path = vim.fn.fnamemodify(vim.uri_to_fname(uri), ":.")
      local bufnr = vim.uri_to_bufnr(uri)

      table.insert(diff, string.format("diff --code-actions a/%s b/%s", path, path))
      table.insert(diff, string.format("--- a/%s", path))
      table.insert(diff, string.format("+++ b/%s", path))
      for _, l in ipairs(diff_text_edits(changes, bufnr, offset_encoding, diff_opts) or {}) do
        table.insert(diff, l)
      end
      table.insert(diff, "")
      table.insert(diff, "")
    end
  end

  return diff
end

local function diff_tuple(err, tuple, diff_opts)
  if err then
    return {
      string.format('"codeAction/resolve" failed with error %d: %s', err.code, err.message)
    }
  end
  local action = tuple[2]
  if action.edit then
    local client = utils.lsp_get_clients({ id = tuple[1] })[1]
    return diff_workspace_edit(action.edit, client.offset_encoding, diff_opts)
  else
    local command = type(action.command) == "table" and action.command or action
    return {
      string.format(
        "Code action preview is only available for document/workspace edits (%s).",
        command and type(command.command) == "string"
        and string.format("command:%s", command.command)
        or string.format("kind:%s", action.kind))
    }
  end
end

-- https://github.com/neovim/neovim/blob/v0.9.4/runtime/lua/vim/lsp/buf.lua#L666
local function preview_action_tuple(self, idx, callback)
  local tuple = self.opts._items[idx]
  -- neovim changed the ui.select params with 0.10.0 (#947)
  -- { client_id, action } ==> { ctx = <LSP context>, action = <action> }
  if tuple.ctx then
    tuple = { tuple.ctx.client_id, tuple.action }
  end
  -- First check our resolved action cache, if "codeAction/resolve" failed, ignore
  -- the error (we already alerted the user about it in `handle_resolved_response`)
  -- and display the default "unsupported" message from the original action
  if self._resolved_actions[idx] then
    local resolved = self._resolved_actions[idx]
    return diff_tuple(nil, not resolved.err and resolved.tuple or tuple, self.diff_opts)
  end
  -- Not found in cache, check if the client supports code action resolving
  local client_id = tuple[1]
  local client = assert(utils.lsp_get_clients({ id = client_id })[1])
  local action = tuple[2]
  local supports_resolve = utils.__HAS_NVIM_010
      -- runtime/lua/lsp/buf.lua:on_user_choice
      and (function()
        ---@var choice {action: lsp.Command|lsp.CodeAction, ctx: lsp.HandlerContext}
        local ms = require("vim.lsp.protocol").Methods
        local choice = self.opts._items[idx]
        local bufnr = assert(choice.ctx.bufnr, "Must have buffer number")
        local reg = client.dynamic_capabilities:get(ms.textDocument_codeAction, { bufnr = bufnr })
        return utils.tbl_get(reg or {}, "registerOptions", "resolveProvider")
            or client:supports_method(ms.codeAction_resolve)
      end)()
      -- prior to nvim 0.10 we could check `client.server_capabilities`
      or utils.tbl_get(client.server_capabilities, "codeActionProvider", "resolveProvider")
  if not action.edit and client and supports_resolve then
    -- Action is not a workspace edit, attempt to resolve the code action
    -- in case it resolves to a workspace edit
    local function handle_resolved_response(err, resolved_action)
      if err then
        -- alert the user "codeAction/resolve" request  failed
        utils.warn(diff_tuple(err, nil, self.diff_opts)[1])
      end
      local resolved = {
        err = err,
        -- Due to a bug in `typescript-tools.nvim` only the first call to `codeAction/resolve`
        -- returns a valid action (non-nil), return nil tuple if the action is nil (#949)
        tuple = resolved_action and { client_id, resolved_action } or nil
      }
      self._resolved_actions[idx] = resolved
      -- HACK: due to upstream bug with jdtls calling resolve messes
      -- errs the workspace edit with "-32603: Internal error." (#1007)
      if not err and client.name == "jdtls" then
        if utils.__HAS_NVIM_010 then
          self.opts._items[idx].action = resolved_action
        else
          self.opts._items[idx][2] = resolved_action
        end
      end
      return resolved.tuple
    end
    if callback then
      client:request("codeAction/resolve", action, function(err, resolved_action)
        local resolved_tuple = handle_resolved_response(err, resolved_action)
        callback(nil, not err and resolved_tuple or tuple)
      end)
      return { string.format("Resolving action (%s)...", action.kind) }
    else
      local res = client:request_sync("codeAction/resolve", action)
      local err, resolved_action = res and res.err, res and res.result
      local resolved_tuple = handle_resolved_response(err, resolved_action)
      return diff_tuple(nil, not err and resolved_tuple or tuple, self.diff_opts)
    end
  else
    return diff_tuple(nil, tuple, self.diff_opts)
  end
end


M.builtin = builtin.base:extend()
M.builtin.preview_action_tuple = preview_action_tuple

function M.builtin:new(o, opts, fzf_win)
  assert(opts._ui_select and opts._ui_select.kind == "codeaction")
  M.builtin.super.new(self, o, opts, fzf_win)
  setmetatable(self, M.builtin)
  self.diff_opts = o.diff_opts
  self._resolved_actions = {}
  for i, _ in ipairs(self.opts._items) do
    self._resolved_actions[i] = false
  end
  return self
end

function M.builtin:gen_winopts()
  local winopts = {
    wrap       = false,
    cursorline = false,
    number     = false
  }
  return vim.tbl_extend("keep", winopts, self.winopts)
end

function M.builtin:populate_preview_buf(entry_str)
  if not self.win or not self.win:validate_preview() then return end
  local idx = tonumber(entry_str:match("^%s*(%d+)%."))
  assert(type(idx) == "number")
  local lines = self:preview_action_tuple(idx,
    -- use the async version for "codeAction/resolve"
    function(err, resolved_tuple)
      if vim.api.nvim_buf_is_valid(self.tmpbuf) then
        vim.api.nvim_buf_set_lines(self.tmpbuf, 0, -1, false,
          diff_tuple(err, resolved_tuple, self.diff_opts))
      end
    end)
  self.tmpbuf = self:get_tmp_buffer()
  vim.api.nvim_buf_set_lines(self.tmpbuf, 0, -1, false, lines)
  vim.bo[self.tmpbuf].filetype = "git"
  self:set_preview_buf(self.tmpbuf)
  self.win:update_preview_title(string.format(" Action #%d ", idx))
  self.win:update_preview_scrollbar()
end

M.native = native.base:extend()
M.native.preview_action_tuple = preview_action_tuple

function M.native:new(o, opts, fzf_win)
  assert(opts._ui_select and opts._ui_select.kind == "codeaction")
  M.native.super.new(self, o, opts, fzf_win)
  setmetatable(self, M.native)
  self.pager = opts.preview_pager == nil and o.pager or opts.preview_pager
  if type(self.pager) == "function" then
    self.pager = self.pager()
  end
  self.diff_opts = o.diff_opts
  self._resolved_actions = {}
  for i, _ in ipairs(self.opts._items) do
    self._resolved_actions[i] = false
  end
  return self
end

function M.native:cmdline(o)
  o = o or {}
  local act = shell.stringify_data(function(entries, _, _)
    local idx = tonumber(entries[1]:match("^%s*%d+%."))
    assert(type(idx) == "number")
    local lines = self:preview_action_tuple(idx)
    return table.concat(lines, "\r\n")
  end, self.opts, "{}")
  if self.pager and #self.pager > 0 and vim.fn.executable(self.pager:match("[^%s]+")) == 1 then
    act = act .. " | " .. utils._if_win_normalize_vars(self.pager)
  end
  return act
end

return M
