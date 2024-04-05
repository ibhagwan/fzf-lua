local hls = {
  bg  = "PmenuSbar",
  sel = "PmenuSel",
}
return {
  desc       = "borderless and minimalistic",
  fzf_opts   = {},
  winopts    = {
    border  = "none",
    preview = {
      scrollbar = "float",
      scrolloff = "-2",
      title_pos = "center",
    },
  },
  hls        = {
    border         = hls.bg,
    preview_border = hls.bg,
    preview_title  = hls.sel,
    scrollfloat_e  = "",
    scrollfloat_f  = hls.sel,
    -- TODO: not working with `scrollbar = "border"` when `border = "none"
    -- scrollborder_f = "@function",
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
