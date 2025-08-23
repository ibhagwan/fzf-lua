local M = {
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
      winopts = { signcolumn = "yes" },
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

local up = {
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

local swiper = {
  previewer = "swiper",
  winopts = function()
    local height = math.ceil(vim.o.lines / 3)
    return { split = ("botright %snew +set\\ nobl"):format(height) }
  end,
}

M.blines = swiper
M.treesitter = swiper
M.git = { blame = swiper }
M.lsp = { document_symbols = swiper }
M.lines = { winopts = up, previewer = { toggle_behavior = "extend" } }
M.grep = { winopts = up, previewer = { toggle_behavior = "extend" } }
M.grep_curbuf = { winopts = up, previewer = { toggle_behavior = "extend" } }

return M
