local M              = {
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

local up             = {
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

---Extract lnum, col from blines/git_blame entries
---@param sel string[]
---@param opts table
---@return integer?, integer?
local parse_lnum_col = function(sel, opts)
  if not sel[1] then return end
  local lnum = sel[1]:match("^%w+ %(.-(%d+)%)") -- git_blame
  if tonumber(lnum) then return tonumber(lnum), 1 end
  local entry = FzfLua.path.entry_to_file(sel[1], opts)
  return entry.line, entry.col
end

-- Credit to phanen@GitHub:
-- https://github.com/ibhagwan/fzf-lua/issues/1754#issuecomment-2944053022
local focused_win    = {
  -- _treesitter = function(line) return "foo.lua", nil, line:sub(2) end,
  -- fzf_opts = { ["--nth"] = "1.." },
  fzf_args = "--pointer=",
  winopts = function()
    local off = vim.o.cmdheight + (vim.o.laststatus and 1 or 0)
    local height = math.ceil(vim.o.lines / 4)
    local ns = vim.api.nvim_create_namespace("fzf-lua.preview.swiper")
    local buf = vim.api.nvim_get_current_buf()
    local hl = function(start_row, start_col, end_row, end_col)
      assert(start_col >= 0 and end_col >= 0, "start_col and end_col must be non-negative")
      vim.hl.range(buf, ns, "IncSearch", { start_row, start_col }, { end_row, end_col }, {})
    end
    local on_buf_change = function()
      vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
      local lines = vim.o.lines
      local l_s = lines - height - off + 1
      local l_e = lines - off - 1
      local max_columns = vim.o.columns
      for r = l_s, l_e do
        local state = {}
        for c = 1, max_columns do
          local ok, ret = pcall(vim.api.nvim__inspect_cell, 1, r, c)
          if not ok or not ret[1] then break end
          (function()
            if not state.lnum then -- parsing lnum
              local d = tonumber(ret[1])
              if not state.parsing_lnum and not d then return end
              if not state.parsing_lnum then
                state.parsing_lnum = d
                return
              end
              if d then
                state.parsing_lnum = state.parsing_lnum * 10 + d
                return
              end
              state.lnum, state.parsing_lnum = assert(state.parsing_lnum), nil
              return
            end
            local in_matched = ret[2] and ret[2].reverse
            if in_matched and not state.in_matched then
              state.start_col = math.max(c - 8, 0)
              state.text = { ret[1] }
              state.in_matched = in_matched
              return
            end
            if in_matched then
              state.text[#state.text + 1] = ret[1]
              return
            end
            if state.in_matched then
              hl(state.lnum - 1, state.start_col, state.lnum - 1, c - 8)
              state.in_matched = nil
            end
          end)()
        end
      end
    end
    return {
      preview = { hidden = true },
      split = ("botright %snew +set\\ nobl"):format(height),
      on_create = function(e)
        vim.api.nvim_create_autocmd("TextChangedT", { buffer = e.bufnr, callback = on_buf_change })
      end,
      on_close = function()
        vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
        -- on hide + change picker ctx will be nil
        local ctx = FzfLua.utils.__CTX()
        if ctx then
          vim.api.nvim_win_set_cursor(0, ctx.cursor)
          FzfLua.utils.zz()
        end
      end,
    }
  end,
  actions = {
    enter = function(sel, opts)
      local lnum, col = parse_lnum_col(sel, opts)
      pcall(vim.api.nvim_win_set_cursor, 0, { lnum, col })
    end,
    focus = {
      fn = function(sel, opts)
        local lnum, col = parse_lnum_col(sel, opts)
        if not lnum then return end
        local ctx = FzfLua.utils.CTX()
        vim.wo[ctx.winid].cursorline = true
        pcall(vim.api.nvim_win_set_cursor, ctx.winid, { lnum, col })
      end,
      field_index = "{}",
      exec_silent = true,
    },
  },
}

M.blines             = focused_win
M.git                = { blame = focused_win }
M.lines              = { winopts = up, previewer = { toggle_behavior = "extend" } }
M.grep               = { winopts = up, previewer = { toggle_behavior = "extend" } }
M.grep_curbuf        = { winopts = up, previewer = { toggle_behavior = "extend" } }

return M
