local M = {
  { "default-title" }, -- base profile
  desc = "UI at the bottom of the screen",
  winopts = {
    row       = 1,
    col       = 0,
    width     = 1,
    height    = 1,
    -- uncomment to supress cmdline
    -- zindex    = 200,
    -- title_pos = "left",
    toggle_behavior = "extend",
    border    = function(_, m)
      assert(m.type == "nvim" and m.name == "fzf")
      -- { "╭", "─", "╮", "│", "╯", "─", "╰", "│" }
      local b = { "", "", "", "", "", "", "", "" }
      if m.layout == "down" then
        -- b[2] = "─"
        b[6] = "─"
      elseif m.layout == "up" then
        b[2] = "─"
      elseif m.layout == "left" then
        b[8] = "│"
      else -- right
        b[4] = "│"
      end
      return b
    end,
    preview   = {
      layout    = "vertical",
      vertical  = "up:60%",
      -- title_pos = "right",
      winopts   = { signcolumn = "yes" },
      border    = function(_, m)
        if m.type == "fzf" then
          return "border-line"
        else
          if m.layout == "down" then
            -- uncomment for preview title
            -- return { "", "─", "", "", "", "", "", "" }
            return { "", "", "", "", "", "", "", "" }
          else
            return "none"
          end
        end
      end,
    }
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
M.grep_curbuf = swiper
M.treesitter = swiper
M.git = { blame = swiper }
M.lsp = { document_symbols = swiper }

return M
