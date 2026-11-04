let s:detected = 0
let s:active = ''
let s:project = {}

function! project_detect#register(name, strategy) abort
  if !has_key(s:strategies, a:name)
    call add(s:order, a:name)
  endif
  let s:strategies[a:name] = a:strategy
  if s:detected && empty(s:active)
    call s:detect()
  endif
endfunction

function! project_detect#active() abort
  call project_detect#detect()
  return s:active
endfunction

function! project_detect#name() abort
  return empty(project_detect#active()) ? '' : get(g:, 'project_name', '')
endfunction

function! project_detect#root() abort
  call project_detect#detect()
  return get(s:project, 'root', '')
endfunction

function! project_detect#language() abort
  call project_detect#detect()
  return get(s:project, 'language', '')
endfunction

function! project_detect#sources() abort
  call project_detect#detect()
  return copy(get(s:project, 'sources', []))
endfunction

function! project_detect#tests() abort
  call project_detect#detect()
  return copy(get(s:project, 'tests', []))
endfunction

" Whether a file (default: the current buffer's) is one of the tests
function! project_detect#is_test(...) abort
  let l:root = project_detect#root()
  if empty(l:root)
    return 0
  endif
  let l:path = fnamemodify(a:0 ? a:1 : bufname('%'), ':p')
  if stridx(l:path, l:root . '/') != 0
    return 0
  endif
  for l:place in s:project.tests
    if l:place =~# '/$'
      if stridx(l:path, l:root . '/' . l:place) == 0
        return 1
      endif
    elseif fnamemodify(l:path, ':t') =~# glob2regpat(l:place)
      return 1
    endif
  endfor
  return 0
endfunction

function! project_detect#runner(language) abort
  let l:runner = extend(copy(get(s:runners, a:language, {})),
        \ get(get(g:, 'project_detect_runners', {}), a:language, {}))
  if has_key(l:runner, 'run') && !has_key(l:runner, 'debug')
    let l:runner.debug = l:runner.run
  endif
  return l:runner
endfunction

function! project_detect#detect() abort
  if !s:detected
    call s:detect()
  endif
endfunction

function! s:detect() abort
  let s:detected = 1
  for l:key in s:order
    let l:found = s:strategies[l:key].detect()
    if empty(l:found)
      continue
    endif
    if type(l:found) == v:t_string
      let l:found = {'name': l:found}
    endif
    " Overrides the strategy's name, and names projects it can't
    let l:name = get(g:, 'project_name', '')
    if empty(l:name)
      let l:name = get(l:found, 'name', '')
    endif
    if !empty(l:name)
      let s:active = l:key
      let s:project = extend({'root': getcwd(), 'language': '', 'sources': [], 'tests': []}, l:found)
      let s:project.root = fnamemodify(s:project.root, ':p:s?/$??')
      let g:project_name = l:name
      return
    endif
  endfor
endfunction

function! s:find_up(name) abort
  " Not from the current buffer: at VimEnter it can be netrw or fugitive's
  " status window
  let l:file = findfile(a:name, escape(getcwd(), ' ,\') . ';')
  return empty(l:file) ? '' : fnamemodify(l:file, ':p')
endfunction

function! s:existing_dirs(root, dirs) abort
  return map(filter(copy(a:dirs), 'isdirectory(a:root . "/" . v:val)'), 'v:val . "/"')
endfunction

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

  let l:root = fnamemodify(l:file, ':h')
  let l:candidates = []
  for l:declared in filter([l:name, get(g:, 'project_name', '')], '!empty(v:val)')
    " my-project is imported as my_project
    let l:import = substitute(tolower(l:declared), '[-.]\+', '_', 'g')
    for l:dir in ['src/', '']
      let l:candidates += [l:dir . l:import, l:dir . l:declared]
    endfor
  endfor
  let l:packages = s:existing_dirs(l:root, l:candidates)
  if empty(l:packages) && filereadable(l:root . '/src/__init__.py')
    let l:packages = ['src/']
  endif
  if empty(l:packages)
    for l:dir in ['src/', '']
      let l:packages = map(glob(l:root . '/' . l:dir . '*/__init__.py', 0, 1),
            \ 'l:dir . fnamemodify(v:val, ":h:t") . "/"')
      call filter(l:packages, 'v:val !~# "^tests\\=/$"')
      if !empty(l:packages)
        if len(l:packages) > 1
          let l:packages = []
        endif
        break
      endif
    endfor
  endif
  let l:package = get(l:packages, 0, '')

  " src/ is not a name
  if empty(l:name) && !empty(l:package) && l:package !=# 'src/'
    let l:name = fnamemodify(l:package, ':h:t')
  endif
  return {
        \ 'name': l:name,
        \ 'root': l:root,
        \ 'language': 'python',
        \ 'sources': empty(l:package) ? [] : [l:package],
        \ 'tests': s:existing_dirs(l:root, ['tests', 'test']) + ['test_*.py', '*_test.py'],
        \ }
endfunction

function! s:go() abort
  let l:file = s:find_up('go.mod')
  if empty(l:file)
    return ''
  endif
  let l:path = ''
  for l:line in readfile(l:file)
    let l:path = matchstr(l:line, '^\s*module\s\+["`]\?\zs[^"`[:space:]]\+')
    if !empty(l:path)
      break
    endif
  endfor
  return {
        \ 'name': fnamemodify(substitute(l:path, '/v\d\+$', '', ''), ':t'),
        \ 'root': fnamemodify(l:file, ':h'),
        \ 'language': 'go',
        \ 'tests': ['*_test.go'],
        \ }
endfunction

" Added directly: register() would detect again
let s:order = ['python', 'go']
let s:strategies = {
      \ 'python': {'detect': function('s:python')},
      \ 'go': {'detect': function('s:go')},
      \ }

let s:runners = {
      \ 'python': {'run': 'pytest'},
      \ 'go': {'run': 'go test'},
      \ }
