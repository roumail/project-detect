let s:detected = 0
let s:active = ''
let s:project = {}

function! project_detect#register(name, strategy) abort
  if !has_key(s:strategies, a:name)
    call add(s:order, a:name)
  endif
  let s:strategies[a:name] = a:strategy
  " A built-in it replaces no longer counts towards more than one language
  call filter(s:signs, 'v:key !=# a:name')
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

" Detects once a session, from the directory Vim started in. Known limit
" (found 2026-11-04 with pytest.vim's test lists): a file of another git work
" tree opened in the same session isn't the project's, so is_test() is 0 for
" it (no pytest.vim keys, not in :PytestTests), and :cd to that tree doesn't
" detect again. Start Vim in the work tree you work in. A fix would detect
" again on DirChanged.
function! project_detect#detect() abort
  if !s:detected
    call s:detect()
  endif
endfunction

function! s:detect() abort
  let s:detected = 1
  let l:languages = sort(filter(keys(s:signs), '!empty(s:signs[v:val]())'))
  if len(l:languages) > 1
    call s:error('more than one language here (' . join(l:languages, ', ') . '): no project detected')
    return
  endif
  for l:key in s:order + ['declared']
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

function! s:package_dirs(name) abort
  " my-project is imported as my_project
  let l:import = substitute(tolower(a:name), '[-.]\+', '_', 'g')
  return ['src/' . l:import, 'src/' . a:name, l:import, a:name]
endfunction

" The folders g:project_name names. It says what to search, so none is an error
function! s:named_folders(root) abort
  let l:name = get(g:, 'project_name', '')
  let l:folders = s:existing_dirs(a:root, s:package_dirs(l:name))
  if empty(l:folders)
    call s:error('no folder for g:project_name "' . l:name . '" in ' . fnamemodify(a:root, ':~'))
  endif
  return l:folders
endfunction

function! s:error(message) abort
  echohl ErrorMsg
  echomsg 'project-detect: ' . a:message
  echohl None
endfunction

" Strongest first: a requirements.txt can sit in a docs/ below a setup.py
let s:python_files = ['pyproject.toml', 'setup.py', 'setup.cfg', 'Pipfile',
      \ 'requirements.txt', 'tox.ini', 'manage.py', 'wsgi.py', 'app.py']

function! s:python_file() abort
  for l:name in s:python_files
    let l:file = s:find_up(l:name)
    if !empty(l:file)
      return l:file
    endif
  endfor
  return ''
endfunction

function! s:pyproject_name(root) abort
  let l:file = a:root . '/pyproject.toml'
  let l:section = ''
  for l:line in filereadable(l:file) ? readfile(l:file) : []
    if l:line =~# '^\s*\['
      let l:section = matchstr(l:line, '^\s*\[\+\s*\zs[^]]\{-}\ze\s*\]')
    elseif l:section =~# '^\%(project\|tool\.poetry\)$' && l:line =~# '^\s*name\s*='
      return matchstr(l:line, '^\s*name\s*=\s*[''"]\zs[^''"]\+')
    endif
  endfor
  return ''
endfunction

function! s:python() abort
  let l:file = s:python_file()
  if empty(l:file)
    return ''
  endif
  let l:root = fnamemodify(l:file, ':h')
  let l:name = get(g:, 'project_name', '')
  if empty(l:name)
    let l:name = s:pyproject_name(l:root)
    let l:packages = empty(l:name) ? [] : s:existing_dirs(l:root, s:package_dirs(l:name))
  else
    let l:packages = s:named_folders(l:root)
  endif
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

" A directory with Vim script in plugin/ or autoload/, from the working
" directory upwards
function! s:vim_root() abort
  let l:dir = getcwd()
  while 1
    if !empty(glob(l:dir . '/plugin/*.vim', 1, 1)) || !empty(glob(l:dir . '/autoload/**/*.vim', 1, 1))
      return l:dir
    endif
    let l:parent = fnamemodify(l:dir, ':h')
    if l:parent ==# l:dir
      return ''
    endif
    let l:dir = l:parent
  endwhile
endfunction

function! s:vim() abort
  let l:dir = s:vim_root()
  if empty(l:dir)
    return ''
  endif
  return {
        \ 'name': fnamemodify(l:dir, ':t'),
        \ 'root': l:dir,
        \ 'language': 'vim',
        \ 'sources': s:existing_dirs(l:dir, ['autoload', 'plugin', 'ftplugin', 'ftdetect',
        \   'syntax', 'indent', 'compiler', 'colors', 'after']),
        \ 'tests': s:existing_dirs(l:dir, ['test', 'tests']),
        \ }
endfunction

" Nothing recognised the project: g:project_name alone makes one
function! s:declared() abort
  if empty(get(g:, 'project_name', ''))
    return ''
  endif
  return {
        \ 'name': g:project_name,
        \ 'sources': s:named_folders(getcwd())[:0],
        \ 'tests': s:existing_dirs(getcwd(), ['tests', 'test']),
        \ }
endfunction

" Added directly: register() would detect again
let s:order = ['python', 'go', 'vim']
let s:strategies = {
      \ 'python': {'detect': function('s:python')},
      \ 'go': {'detect': function('s:go')},
      \ 'vim': {'detect': function('s:vim')},
      \ 'declared': {'detect': function('s:declared')},
      \ }

" What says a project is in that language, whether or not it has a name
let s:signs = {
      \ 'python': function('s:python_file'),
      \ 'go': {-> s:find_up('go.mod')},
      \ 'vim': function('s:vim_root'),
      \ }
