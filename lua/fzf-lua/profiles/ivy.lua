local M       = {
  { "default-title" }, -- base profile
  desc = "UI at the bottom of the screen",
  winopts = {
    row = 1,
    col = 0,
    width = 1,
    height = 0.4,
    title_pos = "left",
    border = { "", "─", "", "", "", "", "", "" },
    preview = {
      layout = "horizontal",
      title_pos = "right",
      border = function(_, m)
        if m.type == "fzf" then
          return "single"
        else
          assert(m.type == "nvim" and m.name == "prev" and type(m.layout) == "string")
          local b = { "┌", "─", "┐", "│", "┘", "─", "└", "│" }
          if m.layout == "down" then
            b[1] = "├" --top right
            b[3] = "┤" -- top left
          elseif m.layout == "up" then
            b[7] = "├" -- bottom left
            b[6] = "" -- remove bottom
            b[5] = "┤" -- bottom right
          elseif m.layout == "left" then
            b[3] = "┬" -- top right
            b[5] = "┴" -- bottom right
            b[6] = "" -- remove bottom
          else -- right
            b[1] = "┬" -- top left
            b[7] = "┴" -- bottom left
            b[6] = "" -- remove bottom
          end
          return b
        end
      end,
    }
  },
}

local up      = {
  row = 1,
  col = 0,
  width = 1,
  height = 1,
  preview = {
    layout = "vertical",
    vertical = "up:60%",
    border = "none",
  },
}

M.blines      = { winopts = up, previewer = { toggle_behavior = "extend" } }
M.lines       = M.blines
M.grep        = M.blines
M.grep_curbuf = M.blines
M.git         = { blame = { winopts = up } }

return M
