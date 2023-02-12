local _MODREV, _SPECREV = 'scm', '-1'
rockspec_format = "3.0"
package = 'fzf-lua'
version = _MODREV .. _SPECREV

description = {
   summary = 'Improved fzf.vim written in lua',
   labels = {
     'neovim',
     'plugin'
   },
   homepage = 'http://github.com/ibhagwan/fzf-lua',
   license = 'AGPL-3.0',
}

dependencies = {
   'lua >= 5.1',
}

source = {
   url = 'git://github.com/ibhagwan/fzf-lua'
}

build = {
   type = 'builtin',
   copy_directories = {
     'doc',
     'plugin',
   },
}
