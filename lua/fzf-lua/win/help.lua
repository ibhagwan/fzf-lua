local api = vim.api
local utils = require("fzf-lua.utils")
local config = require("fzf-lua.config")

---@class fzf-lua.HelpWin
---@field win? integer
---@field buf? integer
local M = {}

---@param keymap table
---@param actions fzf-lua.config.Actions|{}
---@param hls fzf-lua.config.HLS
---@param zindex integer
---@param preview_keymaps table
---@param preview_mode "builtin"|"fzf"
---@param help_open_win? fun(buffer: integer, enter: boolean, config: vim.api.keyset.win_config): integer
---@return function? -- close function
function M.toggle(keymap, actions, hls, zindex, preview_keymaps, preview_mode, help_open_win)
  if M.win then
    M.close()
    return
  end

  local opts = {}
  opts.max_height = math.floor(0.4 * vim.o.lines)
  opts.mode_width = 10
  opts.name_width = 28
  opts.keybind_width = 14
  opts.normal_hl = hls.help_normal
  opts.border_hl = hls.help_border
  opts.winblend = 0
  opts.column_padding = "  "
  opts.column_width = opts.keybind_width + opts.name_width + #opts.column_padding + 2

  local function format_bind(m, k, v, ml, kl, vl)
    return ("%s%%-%ds %%-%ds %%-%ds")
        :format(opts.column_padding, ml, kl, vl)
        :format("`" .. m .. "`", "|" .. k .. "|", "*" .. v .. "*")
  end

  local keymaps = {}

  -- ignore fzf event bind as they aren't valid keymaps
  local keymap_ignore = { ["load"] = true, ["zero"] = true }

  -- fzf and neovim (builtin) keymaps
  for _, m in ipairs({ "builtin", "fzf" }) do
    for k, v in pairs(keymap[m]) do
      if not keymap_ignore[k] then
        -- value can be defined as a table with addl properties (help string)
        if type(v) == "table" then
          v = v.desc or v[1]
        end
        -- only add preview keybinds respective of
        -- the current preview mode
        if v and (not preview_keymaps[v] or m == preview_mode) then
          if m == "builtin" then
            k = utils.neovim_bind_to_fzf(k)
          end
          v = type(v) == "function" and config.get_action_helpstr(v) or tostring(v)
          table.insert(keymaps,
            format_bind(m, k, v, opts.mode_width, opts.keybind_width, opts.name_width))
        end
      end
    end
  end

  ---TODO: we can always parse the action into table to avoid this duplicated logic
  ---(e.g. profile/hide.lua, config.lua)
  ---@param v fzf-lua.ActionSpec
  ---@return string?
  local get_desc = function(v)
    if type(v) == "table" then
      return v.desc or config.get_action_helpstr(v[1]) or config.get_action_helpstr(v.fn) or
          tostring(v)
    elseif v then
      return config.get_action_helpstr(v) or tostring(v)
    end
  end

  -- action keymaps
  if actions then
    for k, v in pairs(actions) do
      if v then -- skips 'v == false'
        if k == "default" then k = "enter" end
        local desc = get_desc(v)
        table.insert(keymaps,
          format_bind("action", k,
            ("%s"):format(desc):gsub(" ", ""),
            opts.mode_width, opts.keybind_width, opts.name_width))
      end
    end
  end

  -- sort alphabetically
  table.sort(keymaps, function(x, y)
    if x < y then
      return true
    else
      return false
    end
  end)

  -- append to existing line based on
  -- available columns
  local function table_append(tbl, s)
    local last = #tbl > 0 and tbl[#tbl]
    if not last or #last + #s > vim.o.columns then
      table.insert(tbl, s)
    else
      tbl[#tbl] = last .. s
    end
  end

  local lines = {}
  for _, km in ipairs(keymaps) do
    table_append(lines, km)
  end

  -- calc popup height based on no. of lines
  local height = #lines < opts.max_height and #lines or opts.max_height

  -- rearrange lines so keymaps appear
  -- sequential within the same column
  lines = {}
  for c = 0, math.floor(vim.o.columns / (opts.column_width + #opts.column_padding)) do
    for i = 1, height do
      local idx = height * c + i
      lines[i] = c == 0 and keymaps[idx] or
          lines[i] .. (keymaps[idx] or "")
    end
  end

  local ch = zindex >= 200 and 0 or vim.o.cmdheight
  ---@type vim.api.keyset.win_config
  local win_opts = {
    relative = "editor",
    style = "minimal",
    width = vim.o.columns,
    height = height,
    row = vim.o.lines - height - ch - 1,
    col = 1,
    -- top border only
    border = { "─", "─", "─", " ", " ", " ", " ", " " },
    -- topmost popup (+2 for float border empty/full)
    zindex = zindex,
  }

  -- "border chars mustbe one cell" (#874)
  if vim.o.ambiwidth == "double" then
    -- "single" looks better
    -- win_opts.border[2] = "-"
    win_opts.border = "single"
  end

  local nvim_open_win = help_open_win or api.nvim_open_win

  M.buf = api.nvim_create_buf(false, true)
  vim.bo[M.buf].modifiable = true
  vim.bo[M.buf].bufhidden = "wipe"
  vim.bo[M.buf].filetype = "help"
  api.nvim_buf_set_name(M.buf, "_FzfLuaHelp")

  M.win = nvim_open_win(M.buf, false, win_opts)
  local wo = utils.wo[M.win][0]
  wo.winhl = string.format("Normal:%s,FloatBorder:%s", opts.normal_hl, opts.border_hl)
  wo.winblend = opts.winblend
  wo.foldenable = false
  wo.wrap = false
  wo.spell = false

  api.nvim_buf_set_lines(M.buf, 0, -1, false, lines)
  return function() M.close() end
end

function M.close()
  if M.win and api.nvim_win_is_valid(M.win) then
    utils.nvim_win_close(M.win, true)
  end
  if M.buf and api.nvim_buf_is_valid(M.buf) then
    api.nvim_buf_delete(M.buf, { force = true })
  end
  M.win = nil
  M.buf = nil
end

return M
