local Previewer = {}

Previewer.fzf = {}
Previewer.fzf.cmd = function() return require "fzf-lua.previewer.fzf".cmd end
Previewer.fzf.bat = function() return require "fzf-lua.previewer.fzf".bat end
Previewer.fzf.head = function() return require "fzf-lua.previewer.fzf".head end
Previewer.fzf.cmd_async = function() return require "fzf-lua.previewer.fzf".cmd_async end
Previewer.fzf.bat_async = function() return require "fzf-lua.previewer.fzf".bat_async end
Previewer.fzf.git_diff = function() return require "fzf-lua.previewer.fzf".git_diff end
Previewer.fzf.man_pages = function() return require "fzf-lua.previewer.fzf".man_pages end
Previewer.fzf.help_tags = function() return require "fzf-lua.previewer.fzf".help_tags end
Previewer.fzf.codeaction = function() return require "fzf-lua.previewer.codeaction".native end

Previewer.builtin = {}
Previewer.builtin.buffer_or_file = function()
  return require "fzf-lua.previewer.builtin".buffer_or_file
end
Previewer.builtin.help_tags = function() return require "fzf-lua.previewer.builtin".help_tags end
Previewer.builtin.man_pages = function() return require "fzf-lua.previewer.builtin".man_pages end
Previewer.builtin.marks = function() return require "fzf-lua.previewer.builtin".marks end
Previewer.builtin.jumps = function() return require "fzf-lua.previewer.builtin".jumps end
Previewer.builtin.tags = function() return require "fzf-lua.previewer.builtin".tags end
Previewer.builtin.quickfix = function() return require "fzf-lua.previewer.builtin".quickfix end
Previewer.builtin.highlights = function() return require "fzf-lua.previewer.builtin".highlights end
Previewer.builtin.autocmds = function() return require "fzf-lua.previewer.builtin".autocmds end
Previewer.builtin.keymaps = function() return require "fzf-lua.previewer.builtin".keymaps end
Previewer.builtin.nvim_options = function() return require "fzf-lua.previewer.builtin".nvim_options end
Previewer.builtin.codeaction = function() return require "fzf-lua.previewer.codeaction".builtin end

Previewer.swiper = {}
Previewer.swiper.default = function() return require "fzf-lua.previewer.swiper".default end


---Instantiate previewer from spec
---@param spec table
---@param opts table
---@return fzf-lua.previewer.Fzf|fzf-lua.previewer.Builtin?
Previewer.new = function(spec, opts)
  if not spec then return end
  local previewer, preview_opts = nil, nil
  if type(spec) == "string" then
    preview_opts = FzfLua.config.globals.previewers[spec]
    if not preview_opts then
      FzfLua.utils.warn(("invalid previewer '%s'"):format(spec))
    end
  elseif type(spec) == "table" then
    preview_opts = spec
  end
  -- Backward compat: can instantiate with `_ctor|new|_new`
  if preview_opts and type(preview_opts.new) == "function" then
    previewer = preview_opts:new(preview_opts, opts)
  elseif preview_opts and type(preview_opts._new) == "function" then
    previewer = preview_opts._new()(preview_opts, opts)
  elseif preview_opts and type(preview_opts._ctor) == "function" then
    previewer = preview_opts._ctor()(preview_opts, opts)
  end
  return previewer
end

---@alias fzf-lua.preview.Spec function|{[1]: function?, fn: function?, field_index: string?}
---convert preview action functions to strings using our shell wrapper
---@param preview fzf-lua.preview.Spec
---@param opts table
---@return string?
Previewer.normalize_spec = function(preview, opts)
  if type(preview) == "function" then
    return FzfLua.shell.stringify_data(preview, opts, "{}")
  elseif type(preview) == "table" then
    preview = vim.tbl_extend("keep", preview, {
      fn = preview.fn or preview[1],
      -- by default we use current item only "{}"
      -- using "{+}" will send multiple selected items
      field_index = "{}",
    })
    if preview.type == "cmd" then
      return FzfLua.shell.stringify_cmd(preview.fn, opts, preview.field_index)
    end
    return FzfLua.shell.stringify_data(preview.fn, opts, preview.field_index)
  else
    return preview
  end
end

return Previewer
