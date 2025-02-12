local utils = require("fzf-lua").utils
local actions = require("fzf-lua").actions

local function hl_validate(hl)
  return not utils.is_hl_cleared(hl) and hl or nil
end

return {
  { "default-title" }, -- base profile
  desc       = "match telescope default highlights|keybinds",
  fzf_opts   = { ["--layout"] = "default", ["--marker"] = "+" },
  winopts    = {
    width   = 0.8,
    height  = 0.9,
    preview = {
      hidden       = false,
      vertical     = "up:45%",
      horizontal   = "right:50%",
      layout       = "flex",
      flip_columns = 120,
      delay        = 10,
      winopts      = { number = false },
    },
  },
  hls        = {
    normal         = hl_validate "TelescopeNormal",
    border         = hl_validate "TelescopeBorder",
    title          = hl_validate "TelescopePromptTitle",
    help_normal    = hl_validate "TelescopeNormal",
    help_border    = hl_validate "TelescopeBorder",
    preview_normal = hl_validate "TelescopeNormal",
    preview_border = hl_validate "TelescopeBorder",
    preview_title  = hl_validate "TelescopePreviewTitle",
    -- builtin preview only
    cursor         = hl_validate "Cursor",
    cursorline     = hl_validate "TelescopeSelection",
    cursorlinenr   = hl_validate "TelescopeSelection",
    search         = hl_validate "IncSearch",
  },
  fzf_colors = {
    ["fg"] = { "fg", "TelescopeNormal" },
    ["bg"] = { "bg", "TelescopeNormal" },
    ["hl"] = { "fg", "TelescopeMatching" },
    ["fg+"] = { "fg", "TelescopeSelection" },
    ["bg+"] = { "bg", "TelescopeSelection" },
    ["hl+"] = { "fg", "TelescopeMatching" },
    ["info"] = { "fg", "TelescopeMultiSelection" },
    ["border"] = { "fg", "TelescopeBorder" },
    ["gutter"] = "-1",
    ["query"] = { "fg", "TelescopePromptNormal" },
    ["prompt"] = { "fg", "TelescopePromptPrefix" },
    ["pointer"] = { "fg", "TelescopeSelectionCaret" },
    ["marker"] = { "fg", "TelescopeSelectionCaret" },
    ["header"] = { "fg", "TelescopeTitle" },
  },
  keymap     = {
    builtin = {
      true,
      ["<C-d>"] = "preview-page-down",
      ["<C-u>"] = "preview-page-up",
    },
    fzf = {
      true,
      ["ctrl-d"] = "preview-page-down",
      ["ctrl-u"] = "preview-page-up",
      ["ctrl-q"] = "select-all+accept",
    },
  },
  actions    = {
    files = {
      ["enter"]  = actions.file_edit_or_qf,
      ["ctrl-x"] = actions.file_split,
      ["ctrl-v"] = actions.file_vsplit,
      ["ctrl-t"] = actions.file_tabedit,
      ["alt-q"]  = actions.file_sel_to_qf,
    },
  },
  buffers    = {
    keymap = { builtin = { ["<C-d>"] = false } },
    actions = { ["ctrl-x"] = false, ["ctrl-d"] = { actions.buf_del, actions.resume } },
  },
  defaults   = { git_icons = false },
}
