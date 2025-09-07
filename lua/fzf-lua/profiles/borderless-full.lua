local hls = {
  bg    = "PmenuSbar",
  sel   = "PmenuSel",
  title = "IncSearch"
}
return {
  { "default-title" }, -- base profile
  desc       = "borderless and not so minimalistic",
  winopts    = {
    border  = function(_, m)
      if m.nwin == 1 then
        return { " ", " ", " ", " ", " ", " ", " ", " " }
      end
      if m.layout == "down" or m.layout == "up" then
        return { " ", " ", " ", " ", "", "", "", " " }
      end
      return { " ", " ", "", "", "", " ", " ", " " }
    end,
    preview = {
      border = "solid",
      scrollbar = "float",
      scrolloff = "-1",
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
