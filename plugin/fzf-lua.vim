" Neovim >= v0.7 uses 'plugin/fzf-lua.lua'
if has('nvim-0.7')
  finish
end

if !has('nvim-0.5')
    echohl Error
    echomsg "Fzf-lua is only available for Neovim versions 0.5 and above"
    echohl clear
    finish
endif

if exists('g:loaded_fzf_lua') | finish | endif
let g:loaded_fzf_lua = 1

" FzfLua builtin lists
function! s:fzflua_complete(arg, line, pos) abort
  " Should we use `a:line[:a:pos-1]`?
  let l:candidates = luaeval('require("fzf-lua.cmd")._candidates("'.a:line.'")')
  return join(candidates,"\n")
endfunction

" FzfLua commands with auto-complete
command! -nargs=* -complete=custom,s:fzflua_complete FzfLua
  \ lua require("fzf-lua.cmd").run_command(<f-args>)
