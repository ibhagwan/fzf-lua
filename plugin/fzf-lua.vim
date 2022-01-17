if !has('nvim-0.5')
    echohl Error
    echomsg "Fzf-lua is only available for Neovim versions 0.5 and above"
    echohl clear
    finish
endif

if exists('g:loaded_fzf_lua') | finish | endif
let g:loaded_fzf_lua = 1

" FzfLua builtin lists
function! s:fzflua_complete(arg,line,pos)
  let l:builtin_list = luaeval('vim.tbl_filter(
    \ function(k)
    \   if require("fzf-lua")._excluded_metamap[k] then
    \     return false
    \   end
    \   return true
    \ end,
    \ vim.tbl_keys(require("fzf-lua")))')

  let list = [l:builtin_list]
  let l = split(a:line[:a:pos-1], '\%(\%(\%(^\|[^\\]\)\\\)\@<!\s\)\+', 1)
  let n = len(l) - index(l, 'FzfLua') - 2

  return join(list[0],"\n")
endfunction

" FzfLua commands with auto-complete
command! -nargs=* -complete=custom,s:fzflua_complete FzfLua lua require('fzf-lua.cmd').load_command(<f-args>)
