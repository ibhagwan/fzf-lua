local hls = {
  bg    = "PmenuSbar",
  sel   = "PmenuSel",
  title = "IncSearch"
}
return {
  { "default-title" }, -- base profile
  desc       = "borderless and not so minimalistic",
  winopts    = {
    border  = "empty",
    preview = {
      scrollbar = "float",
      scrolloff = "-2",
      title_pos = "center",
    },
  },
  hls        = {
    title          = hls.title,
    border         = hls.bg,
    preview_title  = hls.title,
    preview_border = hls.bg,
    scrollfloat_e  = "",
    scrollfloat_f  = hls.sel,
  },
  fzf_colors = {
    ["gutter"] = { "bg", hls.bg },
    ["bg"]     = { "bg", hls.bg },
    ["bg+"]    = { "bg", hls.sel },
    ["fg+"]    = { "fg", hls.sel },
  },
  grep       = { rg_glob = true },
}
