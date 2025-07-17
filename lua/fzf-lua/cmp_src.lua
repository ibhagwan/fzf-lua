local Src = {}

Src.new = function(_)
  local self = setmetatable({}, {
    __index = Src,
  })
  return self
end

---Return whether this source is available in the current context or not (optional).
---@return boolean
function Src:is_available()
  local mode = vim.api.nvim_get_mode().mode:sub(1, 1)
  return mode == "c" and vim.fn.getcmdtype() == ":"
end

---Return the debug name of this source (optional).
---@return string
function Src:get_debug_name()
  return "fzf-lua"
end

---Invoke completion (required).
---@param params cmp.SourceCompletionApiParams
---@param callback fun(response: lsp.CompletionResponse|nil)
---@return nil
function Src:complete(params, callback)
  if not params.context.cursor_before_line:match("FzfLua") then
    return callback()
  end
  return callback(require("fzf-lua.cmd")._candidates(params.context.cursor_before_line, true))
end

---@param completion_item lsp.CompletionItem
---@return lsp.MarkupContent?
function Src:_get_documentation(completion_item)
  local options_md = require("fzf-lua.cmd").options_md()
  if not options_md or not next(options_md) then return end
  -- Test for `label:lower()` to match both `grep_c{word|WORD}`
  local markdown = options_md[completion_item.label] or options_md[completion_item.label:lower()]
  if not markdown and completion_item.data then
    -- didn't find matching the label directly, search globals
    -- this will match "winopts.row" as "globals.winopts.row"
    markdown = options_md["globals." .. completion_item.label]
  end
  if not markdown and completion_item.data and completion_item.data.cmd then
    -- didn't find matching the label or globals, search provider specific
    -- e.g. for "cwd_prompt" option we search the dict for "files.cwd_prompt"
    markdown = options_md[completion_item.data.cmd .. "." .. completion_item.label]
  end
  return markdown and { kind = "markdown", value = markdown } or nil
end

---Resolve completion item (optional).
-- This is called right before the completion is about to be displayed.
---Useful for setting the text shown in the documentation window (`completion_item.documentation`).
---@param completion_item lsp.CompletionItem
---@param callback fun(completion_item: lsp.CompletionItem|nil)
function Src:resolve(completion_item, callback)
  completion_item.documentation = self:_get_documentation(completion_item)
  callback(completion_item)
end

function Src._register_cmdline()
  local ok, cmp, config
  ok, cmp = pcall(require, "cmp")
  if not ok then return end
  -- Using blink.cmp in nvim-cmp compat mode doesn't have config (#1522)
  ok, config = pcall(require, "cmp.config")
  if not ok then return end
  cmp.register_source("FzfLua", Src)
  Src._registered = true
  local cmdline_cfg = config.cmdline
  if not cmdline_cfg or not cmdline_cfg[":"] then return end
  local has_fzf_lua = false
  for _, s in ipairs(cmdline_cfg[":"].sources or {}) do
    if s.name == "FzfLua" then
      has_fzf_lua = true
    end
  end
  if not has_fzf_lua then
    if cmdline_cfg[":"] then
      table.insert(cmdline_cfg[":"].sources or {}, {
        -- nvim-cmp doesn't support keyword_length=0
        -- https://github.com/hrsh7th/nvim-cmp/issues/1197#issuecomment-1264605106
        keyword_length = 1,
        group_index = 1,
        name = "FzfLua",
        option = {}
      })
    end
  end
end

function Src._complete()
  if Src._registered then
    vim.schedule(function()
      require("cmp").complete({
        config = {
          sources = {
            { name = "FzfLua" }
          }
        }
      })
    end)
  end
end

return Src
