" Project detection strategies.
"
" A strategy is a dict with one Funcref:
"   detect()  -> the project name, or '' when this is not such a project
"
" Strategies are tried in registration order and the first match wins.
let s:strategies = {}
let s:order = []
let s:active = ''

function! project_detect#register(name, strategy) abort
  if !has_key(s:strategies, a:name)
    call add(s:order, a:name)
  endif
  let s:strategies[a:name] = a:strategy
  " Registered after startup: detection has already run, so try again
  if v:vim_did_enter && empty(s:active)
    call project_detect#detect()
  endif
endfunction

" Names of the registered strategies, in detection order
function! project_detect#strategies() abort
  return copy(s:order)
endfunction

" Name of the strategy that matched, or ''
function! project_detect#active() abort
  return s:active
endfunction

" The project name (g:project_name), or '' when no strategy matched
function! project_detect#name() abort
  return empty(s:active) ? '' : get(g:, 'project_name', '')
endfunction

" Sets g:project_name from the first matching strategy and fires
" User ProjectDetected. A g:project_name that is already set is kept, so it
" can be overridden per project.
function! project_detect#detect() abort
  for l:key in s:order
    let l:name = s:strategies[l:key].detect()
    if !empty(l:name)
      let s:active = l:key
      let g:project_name = get(g:, 'project_name', l:name)
      if exists('#User#ProjectDetected')
        doautocmd <nomodeline> User ProjectDetected
      endif
      return
    endif
  endfor
endfunction
