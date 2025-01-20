local hls = {
  bg  = "PmenuSbar",
  sel = "PmenuSel",
}
return {
  { "default-prompt" }, -- base profile
  desc       = "borderless and minimalistic",
  fzf_opts   = {},
  winopts    = {
    border  = "none",
    preview = {
      border = "none",
      scrollbar = "border",
    },
  },
  hls        = {
    border         = hls.bg,
    preview_border = hls.bg,
    preview_title  = hls.sel,
    scrollfloat_f  = hls.sel,
    scrollborder_f = hls.bg,
  },
  fzf_colors = {
    ["gutter"] = { "bg", hls.bg },
    ["bg"]     = { "bg", hls.bg },
    ["bg+"]    = { "bg", hls.sel },
    ["fg+"]    = { "fg", hls.sel },
    -- ["fg+"]    = { "fg", "", "reverse:-1" },
  },
  defaults   = {
    git_icons = false,
    file_icons = false,
  },
}
