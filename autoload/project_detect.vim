" Project detection strategies.
"
" A strategy is a dict with one Funcref:
"   detect()  -> '' when this is not such a project, else the project name or
"                a dict describing the project:
"                  name     the project name
"                  root     the project root directory (default: getcwd())
"                  sources  where the code lives, relative to root
"                  tests    where the tests live, relative to root
"                Paths ending in '/' are directories, anything else is a
"                file-name glob such as '*_test.go'.
"
" Strategies are tried in registration order and the first match wins.
" Python and Go are built in; registering one of their names replaces it.
let s:active = ''
let s:project = {}

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

" The project root directory (absolute, no trailing '/'), or ''
function! project_detect#root() abort
  return get(s:project, 'root', '')
endfunction

" Where the code lives: directories (trailing '/') and file globs, relative to
" the root
function! project_detect#sources() abort
  return copy(get(s:project, 'sources', []))
endfunction

" Where the tests live: directories (trailing '/') and file globs, relative to
" the root
function! project_detect#tests() abort
  return copy(get(s:project, 'tests', []))
endfunction

" Sets g:project_name from the first matching strategy and fires
" User ProjectDetected. A g:project_name that is already set is kept, so it
" can be overridden per project.
function! project_detect#detect() abort
  for l:key in s:order
    let l:found = s:strategies[l:key].detect()
    if type(l:found) == v:t_string
      let l:found = {'name': l:found}
    endif
    if !empty(get(l:found, 'name', ''))
      let s:active = l:key
      let s:project = extend({'root': getcwd(), 'sources': [], 'tests': []}, l:found)
      let s:project.root = fnamemodify(s:project.root, ':p:s?/$??')
      let g:project_name = get(g:, 'project_name', l:found.name)
      if exists('#User#ProjectDetected')
        doautocmd <nomodeline> User ProjectDetected
      endif
      return
    endif
  endfor
endfunction

" Built-in strategies. Each looks for its marker file in the working directory
" or above it (Vim is started inside the project).

" The nearest file named a:name, from the working directory upwards, or ''.
" Searches from getcwd(), not the current buffer: at VimEnter the buffer can be
" netrw or fugitive's status window.
function! s:find_up(name) abort
  let l:file = findfile(a:name, escape(getcwd(), ' ,\') . ';')
  return empty(l:file) ? '' : fnamemodify(l:file, ':p')
endfunction

" Those of a:dirs (relative to a:root) that exist, with a trailing '/'
function! s:existing_dirs(root, dirs) abort
  return map(filter(copy(a:dirs), 'isdirectory(a:root . "/" . v:val)'), 'v:val . "/"')
endfunction

" Python: pyproject.toml, named by [project] or [tool.poetry]. The code is the
" import package (src/ layout or flat), the tests are in tests/ or test/.
function! s:python() abort
  let l:file = s:find_up('pyproject.toml')
  if empty(l:file)
    return ''
  endif
  let l:name = ''
  let l:section = ''
  for l:line in readfile(l:file)
    if l:line =~# '^\s*\['
      let l:section = matchstr(l:line, '^\s*\[\+\s*\zs[^]]\{-}\ze\s*\]')
    elseif l:section =~# '^\%(project\|tool\.poetry\)$' && l:line =~# '^\s*name\s*='
      let l:name = matchstr(l:line, '^\s*name\s*=\s*[''"]\zs[^''"]\+')
      break
    endif
  endfor
  if empty(l:name)
    return ''
  endif

  let l:root = fnamemodify(l:file, ':h')
  " The import package: my-project is imported as my_project
  let l:package = substitute(tolower(l:name), '[-.]\+', '_', 'g')
  let l:candidates = []
  for l:dir in ['src/', '']
    let l:candidates += [l:dir . l:package, l:dir . l:name]
  endfor
  return {
        \ 'name': l:name,
        \ 'root': l:root,
        \ 'sources': s:existing_dirs(l:root, l:candidates)[:0],
        \ 'tests': s:existing_dirs(l:root, ['tests', 'test']),
        \ }
endfunction

" Go: go.mod, named by the last element of the module path (without a /vN
" major-version suffix). The code is the whole module, the tests are the
" *_test.go files next to it.
function! s:go() abort
  let l:file = s:find_up('go.mod')
  if empty(l:file)
    return ''
  endif
  for l:line in readfile(l:file)
    let l:path = matchstr(l:line, '^\s*module\s\+["`]\?\zs[^"`[:space:]]\+')
    if !empty(l:path)
      return {
            \ 'name': fnamemodify(substitute(l:path, '/v\d\+$', '', ''), ':t'),
            \ 'root': fnamemodify(l:file, ':h'),
            \ 'tests': ['*_test.go'],
            \ }
    endif
  endfor
  return ''
endfunction

" Added directly: register() would detect again when this file is first loaded
" by the VimEnter detection itself
let s:order = ['python', 'go']
let s:strategies = {
      \ 'python': {'detect': function('s:python')},
      \ 'go': {'detect': function('s:go')},
      \ }
