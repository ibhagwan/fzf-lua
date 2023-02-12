local _MODREV, _SPECREV = 'scm', '-1'
rockspec_format = "3.0"
package = 'fzf-lua'
version = _MODREV .. _SPECREV

description = {
   summary = 'UI Component Library for Neovim',
   labels = {
     'neovim',
     'plugin'
   },
   homepage = 'http://github.com/ibhagwan/fzf-lua',
   license = 'MIT',
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
