if exists('g:loaded_fzf_lua') | finish | endif

if !has('nvim-0.5')
    echohl Error
    echomsg "Fzf-lua is only available for Neovim versions 0.5 and above"
    echohl clear
    finish
endif
