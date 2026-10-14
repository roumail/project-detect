" Project detection strategies.
"
" A strategy is a dict with one Funcref:
"   detect()  -> '' when this is not such a project, else the project name or
"                a dict describing the project:
"                  name      the project name, '' when it declares none: it is
"                            then named by g:project_name, and does not match
"                            without it
"                  root      the project root directory (default: getcwd())
"                  language  the language, e.g. 'python' (default: '')
"                  sources   where the code lives, relative to root
"                  tests     where the tests live, relative to root
"                Paths ending in '/' are directories, anything else is a
"                file-name glob such as '*_test.go'. A file is in sources or
"                tests when it is in one of the directories or matches one of
"                the globs.
"
" Strategies are tried in registration order and the first match wins.
" Python and Go are built in; registering one of their names replaces it.
let s:detected = 0
let s:active = ''
let s:project = {}

function! project_detect#register(name, strategy) abort
  if !has_key(s:strategies, a:name)
    call add(s:order, a:name)
  endif
  let s:strategies[a:name] = a:strategy
  " Registered after detection ran without a match: try again
  if s:detected && empty(s:active)
    call s:detect()
  endif
endfunction

" Names of the registered strategies, in detection order
function! project_detect#strategies() abort
  return copy(s:order)
endfunction

" Name of the strategy that matched, or ''
function! project_detect#active() abort
  call project_detect#detect()
  return s:active
endfunction

" The project name (g:project_name), or '' when no strategy matched
function! project_detect#name() abort
  return empty(project_detect#active()) ? '' : get(g:, 'project_name', '')
endfunction

" The project root directory (absolute, no trailing '/'), or ''
function! project_detect#root() abort
  call project_detect#detect()
  return get(s:project, 'root', '')
endfunction

" The project's language ('python', 'go'), or ''
function! project_detect#language() abort
  call project_detect#detect()
  return get(s:project, 'language', '')
endfunction

" Where the code lives: directories (trailing '/') and file globs, relative to
" the root
function! project_detect#sources() abort
  call project_detect#detect()
  return copy(get(s:project, 'sources', []))
endfunction

" Where the tests live: directories (trailing '/') and file globs, relative to
" the root
function! project_detect#tests() abort
  call project_detect#detect()
  return copy(get(s:project, 'tests', []))
endfunction

" Whether a file (default: the current buffer's) is one of the project's tests
function! project_detect#is_test(...) abort
  let l:root = project_detect#root()
  if empty(l:root)
    return 0
  endif
  let l:path = fnamemodify(a:0 ? a:1 : bufname('%'), ':p')
  if stridx(l:path, l:root . '/') != 0
    return 0
  endif
  let l:relative = l:path[len(l:root) + 1 :]
  for l:place in s:project.tests
    if l:place =~# '/$'
      if stridx(l:relative, l:place) == 0
        return 1
      endif
    elseif fnamemodify(l:path, ':t') =~# glob2regpat(l:place)
      return 1
    endif
  endfor
  return 0
endfunction

" The project's search scopes, in order: its code and its tests, each also
" limited to the project's language. A scope is a dict:
"   label     'project', 'project python', 'tests', 'tests python'
"   root      the project root
"   places    directories and globs as in sources() / tests(); [] is the root
"   language  the language it is limited to, or ''
function! project_detect#scopes() abort
  if empty(project_detect#active())
    return []
  endif
  let l:language = project_detect#language()
  let l:scopes = []
  for [l:label, l:places] in [['project', project_detect#sources()], ['tests', project_detect#tests()]]
    if l:label ==# 'tests' && empty(l:places)
      continue
    endif
    for l:limit in empty(l:language) ? [''] : ['', l:language]
      call add(l:scopes, {
            \ 'label': empty(l:limit) ? l:label : l:label . ' ' . l:limit,
            \ 'root': s:project.root,
            \ 'places': l:places,
            \ 'language': l:limit,
            \ })
    endfor
  endfor
  return l:scopes
endfunction

" How a language's tests are run: a dict with
"   run    the test command
"   debug  the command for interactive debugging sessions (default: run)
" from g:project_detect_runners[language], else the built-in one.
function! project_detect#runner(language) abort
  let l:runner = extend(copy(get(s:runners, a:language, {})),
        \ get(get(g:, 'project_detect_runners', {}), a:language, {}))
  if has_key(l:runner, 'run') && !has_key(l:runner, 'debug')
    let l:runner.debug = l:runner.run
  endif
  return l:runner
endfunction

" Detects the project once: at VimEnter, or earlier when a project is asked for
" first (by an ftplugin for a file given on the command line).
function! project_detect#detect() abort
  if !s:detected
    call s:detect()
  endif
endfunction

" Sets g:project_name from the first matching strategy and fires
" User ProjectDetected. A g:project_name that is already set is kept, so it
" can be overridden per project, and names projects that declare no name.
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
    let l:name = get(g:, 'project_name', '')
    if empty(l:name)
      let l:name = get(l:found, 'name', '')
    endif
    if !empty(l:name)
      let s:active = l:key
      let s:project = extend({'root': getcwd(), 'language': '', 'sources': [], 'tests': []}, l:found)
      let s:project.root = fnamemodify(s:project.root, ':p:s?/$??')
      let s:project.name = l:name
      let g:project_name = l:name
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

" Python: pyproject.toml, named by [project] or [tool.poetry], else after its
" import package. The code is the import package (see s:python_package()).
" The tests are tests/ or test/, and the files pytest collects: test_*.py and
" *_test.py.
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
  let l:package = s:python_package(l:root, [l:name, get(g:, 'project_name', '')])
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

" The import package of the Python project in a:root, relative to it with a
" trailing '/', or '' when there is none or there are several. In order:
"   - src/<name>/ or <name>/ for one of a:names (my-project is imported as
"     my_project)
"   - src/, when it is a package itself
"   - the only package in src/, else the only one in the root besides tests/
"     and test/
function! s:python_package(root, names) abort
  let l:candidates = []
  for l:name in filter(copy(a:names), '!empty(v:val)')
    let l:package = substitute(tolower(l:name), '[-.]\+', '_', 'g')
    for l:dir in ['src/', '']
      let l:candidates += [l:dir . l:package, l:dir . l:name]
    endfor
  endfor
  let l:named = s:existing_dirs(a:root, l:candidates)
  if !empty(l:named)
    return l:named[0]
  endif
  if filereadable(a:root . '/src/__init__.py')
    return 'src/'
  endif
  for l:dir in ['src/', '']
    let l:packages = map(glob(a:root . '/' . l:dir . '*/__init__.py', 0, 1),
          \ 'l:dir . fnamemodify(v:val, ":h:t") . "/"')
    call filter(l:packages, 'v:val !~# "^tests\\=/$"')
    if !empty(l:packages)
      return len(l:packages) == 1 ? l:packages[0] : ''
    endif
  endfor
  return ''
endfunction

" Go: go.mod, named by the last element of the module path (without a /vN
" major-version suffix). The code is the whole module, the tests are the
" *_test.go files next to it.
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

" Built-in test runners, by language
let s:runners = {
      \ 'python': {'run': 'pytest'},
      \ 'go': {'run': 'go test'},
      \ }
