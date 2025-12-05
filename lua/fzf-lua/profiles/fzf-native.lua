return {
  { "default-title" }, -- base profile
  desc = "fzf with `bat` as native previewer",
  winopts = {
    preview = {
      default = "bat",
      border = function(_, m)
        -- NOTE: will err on `FzfLua ... winopts.toggle_behavior=extend`
        -- assert(m.type == "fzf")
        if FzfLua.utils.has(m.opts, "fzf", { 0, 63 }) then
          return "border-line"
        else
          return "border-sharp"
        end
      end
    }
  },
  manpages = { previewer = "man_native" },
  helptags = { previewer = "help_native" },
  undotree = { previewer = "undo_native" },
  lsp = { code_actions = { previewer = "codeaction_native" } },
  tags = { previewer = "bat" },
  btags = { previewer = "bat" },
}
