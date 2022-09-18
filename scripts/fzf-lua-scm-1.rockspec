local MODREV, SPECREV = "scm", "-1"
rockspec_format = "3.0"
package = "fzf-lua"
version = MODREV .. SPECREV

description = {
	summary = "Improved fzf.vim written in lua",
	labels = { "neovim"},
	homepage = "https://github.com/ibhagwan/fzf-lua",
	license = "AGPL-3.0",
}

dependencies = {
	"lua >= 5.1, < 5.4",
}

source = {
	url = "http://github.com/ibhagwan/fzf-lua/archive/v" .. MODREV .. ".zip",
}

if MODREV == "scm" then
	source = {
		url = "git://github.com/ibhagwan/fzf-lua",
	}
end

build = {
   type = "builtin",
   copy_directories = {
   	  'after',
	  'plugin'
   }
}

