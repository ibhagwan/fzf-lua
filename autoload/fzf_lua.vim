" Calling vim.fn.getbufinfo in lua can be expensive because it has to convert
" all the buffer variables into lua values. Since fzf-lua does not access
" buffer variables, this cost can be avoided by clearing the entry before
" passing the info to lua.
function! fzf_lua#getbufinfo(bufnr) abort
  let info = getbufinfo(a:bufnr)
  if empty(info)
    return [] " there is no way to return `nil` from vimscript
  endif
  let vars = info[0].variables
  unlet! info[0].variables
  " Make sure we copy 'current_syntax' as `utils.buf_is_qf`
  " uses it to detect quickfix buffers
  if !empty(vars) && has_key(vars, "current_syntax")
    let info[0].variables = { "current_syntax": vars.current_syntax }
  endif
  return info[0]
endfunction

" Similar to fzf_lua#getbufinfo, but for getwininfo.
function! fzf_lua#getwininfo(winid) abort
  let info = getwininfo(a:winid)
  if empty(info)
    return []
  endif
  unlet! info[0].variables
  return info[0]
endfunction
