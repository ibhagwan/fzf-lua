local Previewer = {}

Previewer.fzf = {}
Previewer.fzf.cmd = function() return require "fzf-lua.previewer.fzf".cmd end
Previewer.fzf.bat = function() return require "fzf-lua.previewer.fzf".bat end
Previewer.fzf.head = function() return require "fzf-lua.previewer.fzf".head end
Previewer.fzf.cmd_async = function() return require "fzf-lua.previewer.fzf".cmd_async end
Previewer.fzf.bat_async = function() return require "fzf-lua.previewer.fzf".bat_async end
Previewer.fzf.git_diff = function() return require "fzf-lua.previewer.fzf".git_diff end
Previewer.fzf.man_pages = function() return require "fzf-lua.previewer.fzf".man_pages end
Previewer.fzf.help_tags = function() return require "fzf-lua.previewer.fzf".help_tags end

Previewer.builtin = {}
Previewer.builtin.buffer_or_file = function()
  return require "fzf-lua.previewer.builtin".buffer_or_file
end
Previewer.builtin.help_tags = function() return require "fzf-lua.previewer.builtin".help_tags end
Previewer.builtin.help_file = function() return require "fzf-lua.previewer.builtin".help_file end
Previewer.builtin.man_pages = function() return require "fzf-lua.previewer.builtin".man_pages end
Previewer.builtin.marks = function() return require "fzf-lua.previewer.builtin".marks end
Previewer.builtin.jumps = function() return require "fzf-lua.previewer.builtin".jumps end
Previewer.builtin.tags = function() return require "fzf-lua.previewer.builtin".tags end
Previewer.builtin.quickfix = function() return require "fzf-lua.previewer.builtin".quickfix end
Previewer.builtin.highlights = function() return require "fzf-lua.previewer.builtin".highlights end
Previewer.builtin.autocmds = function() return require "fzf-lua.previewer.builtin".autocmds end

return Previewer
