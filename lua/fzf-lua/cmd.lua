local builtin = require "fzf-lua"
local path = require "fzf-lua.path"
local utils = require "fzf-lua.utils"
local defaults = require "fzf-lua.defaults".defaults
local serpent = require "fzf-lua.lib.serpent"

local M = {}

function M.run_command(cmd, ...)
  local args = { ... }
  cmd = cmd or "builtin"

  if not builtin[cmd] then
    utils.info(string.format("invalid command '%s'", cmd))
    return
  end

  local opts = {}

  for _, arg in ipairs(args) do
    local key = arg:match("^[^=]+")
    local val = arg:match("=") and arg:match("=(.*)$")
    if val and #val > 0 then
      local ok, loaded = serpent.load(val)
      -- Parsed string wasn't "nil"  but loaded as `nil`, use as is
      if val ~= "nil" and loaded == nil then ok = false end
      if ok and (type(loaded) ~= "table" or not utils.tbl_isempty(loaded)) then
        opts[key] = loaded
      else
        opts[key] = val
      end
    end
  end

  builtin[cmd](opts)
end

---@return table
function M.options_md()
  -- Only attempt to load from file once, if failed we ditch the docs
  if M._options_md ~= nil then return M._options_md end
  M._options_md = {}
  local filepath = path.join({ vim.g.fzf_lua_root, "OPTIONS.md" })
  local lines = vim.split(utils.read_file(filepath), "\n")
  local section
  for _, l in ipairs(lines or {}) do
    (function()
      -- Lua 5.1 goto compatiblity hack (function wrap)
      if l:match("^#") or l:match("<!%-%-") or l:match("%-%-%-") then
        -- Match markdown atx header levels 3-5 only
        section = l:match("^####?#?%s+(.*)")
        if section then
          -- Use only the non-spaced rightmost part of the line
          -- "Opts: files" will be translated to "files" section
          section = section:match("[^%s]+$")
          M._options_md[section] = {}
          return
        end
      end
      if section then
        table.insert(M._options_md[section], l)
      end
    end)()
  end
  -- Trim surrounding lines and replace newline with literal \n
  M._options_md = vim.tbl_map(function(v)
    while rawget(v, 1) == "" do
      table.remove(v, 1)
    end
    while rawget(v, #v) == "" do
      table.remove(v)
    end
    return table.concat(v, "\n")
  end, M._options_md)
  return M._options_md
end

function M._candidates(line, cmp_items)
  local function to_cmp_items(t, data)
    local cmp = require("cmp")
    return vim.tbl_map(function(v)
      return {
        label = v,
        filterText = v,
        insertText = v,
        kind = cmp.lsp.CompletionItemKind.Variable,
        data = data,
      }
    end, t)
  end
  local builtin_list = vim.tbl_filter(function(k)
    return builtin._excluded_metamap[k] == nil
  end, vim.tbl_keys(builtin))

  local l = vim.split(line, "%s+")
  local n = #l - 2

  -- We can reach here after on :FzfLua+<+Space>+<BS>
  if n < 0 then return end

  if n == 0 then
    local commands = utils.tbl_flatten({ builtin_list })
    table.sort(commands)

    commands = vim.tbl_filter(function(val)
      return vim.startswith(val, l[2])
    end, commands)

    return cmp_items and to_cmp_items(commands) or commands
  end

  -- Not all commands have their opts under the same key
  local function cmd2key(cmd)
    if not cmd then return end
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
      { patterns = { "^diagnostics_" },    transform = function(_) return "diagnostics" end },
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

  local cmd_cfg_key = cmd2key(l[2])
  local cmd_opts = utils.map_get(defaults, cmd_cfg_key) or {}
  local opts = vim.tbl_filter(function(k)
    -- Exclude options starting with "_"
    return not k:match("^_")
  end, vim.tbl_keys(utils.map_flatten(cmd_opts)))

  -- Add globals recursively, e.g. `winopts.fullscreen`
  -- will be later retrieved using `utils.map_get(...)`
  for k, v in pairs({
    winopts  = false,
    keymap   = false,
    fzf_opts = false,
    __HLS    = "hls", -- rename prefix
  }) do
    opts = utils.tbl_flatten({ opts, vim.tbl_filter(function(x)
        -- Exclude global options that can be specified only during `setup`,
        -- e.g.'`winopts.preview.default` as this might confuse the user
        return not M.options_md()["setup." .. x]
      end,
      vim.tbl_keys(utils.map_flatten(defaults[k] or {}, v or k))) })
  end

  -- Add options from docs, so we also have options defaulting to `nil`
  local opts_from_docs = vim.tbl_filter(function(o)
    return vim.startswith(o, cmd_cfg_key .. ".") or vim.startswith(o, "globals.")
  end, vim.tbl_keys(M.options_md()))
  vim.tbl_map(function(o)
    -- Cut the first part, e.g. "files.cwd" -> "cwd"
    o = o:match("%..*$"):sub(2)
    if not utils.tbl_contains(opts, o) then
      table.insert(opts, o)
    end
  end, opts_from_docs)

  table.sort(opts)

  opts = vim.tbl_filter(function(val)
    return vim.startswith(val, l[#l])
  end, opts)

  return cmp_items and to_cmp_items(opts, { cmd = cmd_cfg_key }) or opts
end

return M
