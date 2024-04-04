if vim.g.loaded_fzf_lua == 1 then
  return
end
vim.g.loaded_fzf_lua = 1

-- Should never be called, below nvim 0.7 "plugin/fzf-lua.vim"
-- sets `vim.g.loaded_fzf_lua=1`
if vim.fn.has("nvim-0.7") ~= 1 then
  vim.api.nvim_err_writeln("Fzf-lua minimum requirement is Neovim versions 0.5")
  return
end

vim.api.nvim_create_user_command("FzfLua", function(opts)
  require("fzf-lua.cmd").load_command(unpack(opts.fargs))
end, {
  nargs = "*",
  complete = function(_, line)
    local metatable = require("fzf-lua")
    local builtin_list = vim.tbl_filter(function(k)
      return metatable._excluded_metamap[k] == nil
    end, vim.tbl_keys(metatable))

    local l = vim.split(line, "%s+")
    local n = #l - 2

    if n == 0 then
      local commands = vim.tbl_flatten({ builtin_list })
      table.sort(commands)

      return vim.tbl_filter(function(val)
        return vim.startswith(val, l[2])
      end, commands)
    end

    local defaults = require("fzf-lua.defaults").defaults
    local cmd_opts = defaults[l[2]] or {}
    local opts = vim.tbl_filter(function(k)
      return not k:match("^_")
    end, vim.tbl_keys(cmd_opts))

    -- Flatten map's keys recursively
    --   { a = { a1 = ..., a2 = ... } }
    -- will be transformed to:
    --   {
    --     ["a.a1"] = ...,
    --     ["a.a2"] = ...,
    --   }
    local function map_flatten(t, prefix)
      if vim.tbl_isempty(t) then return {} end
      local ret = {}
      prefix = prefix and string.format("%s.", prefix) or ""
      for k, v in pairs(t) do
        if type(v) == "table" then
          local inner = map_flatten(v)
          for ki, vi in pairs(inner) do
            ret[prefix .. k .. "." .. ki] = vi
          end
        else
          ret[prefix .. k] = v
        end
      end
      return ret
    end

    -- Add globals recursively, e.g. `winopts.fullscreen`
    -- will be later retrieved using `utils.map_get(...)`
    for _, k in ipairs({ "winopts", "keymap", "fzf_opts", "fzf_tmux_opts", "hls" }) do
      opts = vim.tbl_flatten({ opts, vim.tbl_keys(map_flatten(defaults[k] or {}, k)) })
    end

    -- Add generic options that apply to all pickers
    for _, o in ipairs({ "query" }) do
      table.insert(opts, o)
    end

    table.sort(opts)

    return vim.tbl_filter(function(val)
      return vim.startswith(val, l[#l])
    end, opts)
  end,
})
