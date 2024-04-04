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

    -- Not all commands have their opts under the same key
    local function cmd2key(cmd)
      local cmd2cfg = {
        {
          patterns = { "^git_", "^dap", "^tmux_" },
          transform = function(c) return c:gsub("_", ".") end
        },
        {
          patterns = { "^lsp_code_actions$" },
          transform = function(_) return "lsp.code_actions" end
        },
        { patterns = { "^lsp_.*_symbols$" }, transform = function(_) return "lsp.symbols" end },
        { patterns = { "^lsp_" },            transform = function(_) return "lsp" end },
        { patterns = { "^diagnostics_" },    transform = function(_) return "dianostics" end },
        { patterns = { "^tags" },            transform = function(_) return "tags" end },
        { patterns = { "grep" },             transform = function(_) return "grep" end },
        { patterns = { "^complete_bline$" }, transform = function(_) return "complete_line" end },
      }
      for _, v in pairs(cmd2cfg) do
        for _, p in ipairs(v.patterns) do
          if cmd:match(p) then return v.transform(cmd) end
        end
      end
      return cmd
    end

    local utils = require("fzf-lua.utils")
    local defaults = require("fzf-lua.defaults").defaults
    local cmd_opts = utils.map_get(defaults, cmd2key(l[2])) or {}
    local opts = vim.tbl_filter(function(k)
      return not k:match("^_")
    end, vim.tbl_keys(utils.map_flatten(cmd_opts)))

    -- Add globals recursively, e.g. `winopts.fullscreen`
    -- will be later retrieved using `utils.map_get(...)`
    for k, v in pairs({
      winopts       = false,
      keymap        = false,
      fzf_opts      = false,
      fzf_tmux_opts = false,
      __HLS         = "hls", -- rename prefix
    }) do
      opts = vim.tbl_flatten({ opts, vim.tbl_keys(utils.map_flatten(defaults[k] or {}, v or k)) })
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
