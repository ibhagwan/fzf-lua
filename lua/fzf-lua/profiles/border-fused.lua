local _single  = { "┌", "─", "┐", "│", "┘", "─", "└", "│" }
local _rounded = { "╭", "─", "╮", "│", "╯", "─", "╰", "│" }
local _border  = true and _rounded or _single
local _preview_border
return {
  { "default-title" }, -- base profile
  desc = "Single border around the UI",
  -- previewers = { bat = { args = "--color=always --style=default" } },
  defaults = {
    enrich = function(opts)
      if not FzfLua.utils.has(opts, "fzf", { 0, 63 }) then
        _preview_border = "border-line"
      else
        _preview_border = "border-sharp"
      end
      return opts
    end
  },
  winopts = {
    border  = function(_, m)
      assert(m.type == "nvim" and m.name == "fzf")
      if m.nwin == 1 then
        -- No preview, return the border whole
        return _border
      else
        -- has preview `nwim==2`
        assert(type(m.layout) == "string")
        local b = vim.deepcopy(_border)
        if m.layout == "down" then
          b[5] = "┤" -- bottom right
          b[6] = "" -- remove bottom
          b[7] = "├" -- bottom left
        elseif m.layout == "up" then
          b[1] = "├" --top right
          b[3] = "┤" -- top left
        elseif m.layout == "left" then
          b[1] = "┬" -- top left
          b[8] = "" -- remove left
          b[7] = "┴" -- bottom right
        else -- right
          b[3] = "┬" -- top right
          b[4] = "" -- remove right
          b[5] = "┴" -- bottom right
        end
        return b
      end
    end,
    preview = {
      scrollbar = "border",
      border = function(_, m)
        if m.type == "fzf" then
          return _preview_border
        else
          assert(m.type == "nvim" and m.name == "prev" and type(m.layout) == "string")
          local b = vim.deepcopy(_border)
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
          else -- right
            b[1] = "┬" -- top left
            b[7] = "┴" -- bottom left
          end
          return b
        end
      end,
    },
  },
}
