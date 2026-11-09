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

" One for each language: {'language': ..., 'sources': [...], 'tests': [...]}
function! project_detect#parts() abort
  call project_detect#detect()
  return deepcopy(get(s:project, 'parts', []))
endfunction

" The part a file (default: the current buffer's) belongs to, or {}
function! project_detect#part(...) abort
  call project_detect#detect()
  if empty(s:project)
    return {}
  endif
  return deepcopy(s:part_of(fnamemodify(a:0 ? a:1 : bufname('%'), ':p')))
endfunction

" Where a file is decides before its extension: Python under a Rust crate's
" crates/ is that crate's test data. With one part, every file is in it.
function! s:part_of(path) abort
  if len(s:project.parts) == 1
    return s:project.parts[0]
  endif
  if stridx(a:path, s:project.root . '/') != 0
    return {}
  endif
  let l:relative = a:path[len(s:project.root) + 1 :]
  let l:part = {}
  let l:longest = 0
  for l:candidate in s:project.parts
    for l:place in filter(l:candidate.sources + l:candidate.tests, 'v:val =~# "/$"')
      if len(l:place) > l:longest && stridx(l:relative, l:place) == 0
        let l:part = l:candidate
        let l:longest = len(l:place)
      endif
    endfor
  endfor
  if !empty(l:part)
    return l:part
  endif
  let l:extension = fnamemodify(a:path, ':e')
  for l:candidate in s:project.parts
    if index(get(s:extensions, l:candidate.language, [l:candidate.language]), l:extension) >= 0
      return l:candidate
    endif
  endfor
  return {}
endfunction

" Whether a file (default: the current buffer's) is one of its part's tests
function! project_detect#is_test(...) abort
  let l:root = project_detect#root()
  if empty(l:root)
    return 0
  endif
  let l:path = fnamemodify(a:0 ? a:1 : bufname('%'), ':p')
  if stridx(l:path, l:root . '/') != 0
    return 0
  endif
  for l:place in get(s:part_of(l:path), 'tests', [])
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
  let l:parts = s:found(s:order)
  " Only when no language is here: it would be a part with no language
  if empty(l:parts)
    let l:parts = s:found(['declared'])
  endif
  if empty(l:parts)
    return
  endif
  " Strategies look upwards: one found further up is a project around this one
  let l:deepest = max(map(copy(l:parts), 'len(v:val.root)'))
  call filter(l:parts, 'len(v:val.root) == l:deepest')
  " Overrides the strategies' names, and names projects they can't
  let l:name = get(g:, 'project_name', '')
  for l:part in l:parts
    let l:name = empty(l:name) ? l:part.name : l:name
  endfor
  if !empty(l:name)
    let s:active = l:parts[0].key
    let s:project = {'root': l:parts[0].root, 'parts': l:parts}
    " After the strategies: they take a name here as one you gave
    let g:project_name = l:name
  endif
endfunction

function! s:found(keys) abort
  let l:parts = []
  for l:key in a:keys
    let l:found = s:strategies[l:key].detect()
    if empty(l:found)
      continue
    endif
    if type(l:found) == v:t_string
      let l:found = {'name': l:found}
    endif
    let l:part = extend({'root': getcwd(), 'name': '', 'language': '', 'sources': [], 'tests': []}, l:found)
    let l:part.key = l:key
    let l:part.root = fnamemodify(l:part.root, ':p:s?/$??')
    call add(l:parts, l:part)
  endfor
  return l:parts
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

" A string from a TOML file, in a section matching the pattern; '' if none
function! s:toml_string(file, sections, key) abort
  let l:section = ''
  for l:line in filereadable(a:file) ? readfile(a:file) : []
    if l:line =~# '^\s*\['
      let l:section = matchstr(l:line, '^\s*\[\+\s*\zs[^]]\{-}\ze\s*\]')
    elseif l:section =~# '^\%(' . a:sections . '\)$' && l:line =~# '^\s*' . a:key . '\s*='
      return matchstr(l:line, '^\s*' . a:key . '\s*=\s*[''"]\zs[^''"]\+')
    endif
  endfor
  return ''
endfunction

function! s:pyproject_name(root) abort
  return s:toml_string(a:root . '/pyproject.toml', 'project\|tool\.poetry', 'name')
endfunction

" The Python package of a Rust extension, as maturin's python-source says
function! s:maturin_package(root) abort
  let l:file = a:root . '/pyproject.toml'
  let l:source = s:toml_string(l:file, 'tool\.maturin', 'python-source')
  if empty(l:source)
    return []
  endif
  " module-name can be dotted: pkg._native is in pkg
  let l:module = matchstr(s:toml_string(l:file, 'tool\.maturin', 'module-name'), '^[^.]\+')
  return s:existing_dirs(a:root, (empty(l:module) ? [] : [l:source . '/' . l:module]) + [l:source])[:0]
endfunction

" When nothing else names it, the directory does, but only where Vim started:
" a requirements.txt further up may not be this project's
function! s:directory_name(root) abort
  return a:root ==# getcwd() ? fnamemodify(a:root, ':t') : ''
endfunction

function! s:python() abort
  let l:file = s:python_file()
  if empty(l:file)
    return ''
  endif
  let l:root = fnamemodify(l:file, ':h')
  let l:name = get(g:, 'project_name', '')
  " Where the code is, whatever the project is called: no folder is expected
  " under the name
  let l:packages = s:maturin_package(l:root)
  if empty(l:name)
    let l:name = s:pyproject_name(l:root)
    if empty(l:packages) && !empty(l:name)
      let l:packages = s:existing_dirs(l:root, s:package_dirs(l:name))
    endif
  elseif empty(l:packages)
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
  if empty(l:name)
    let l:name = s:directory_name(l:root)
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

" [workspace] members, on one line or several
function! s:cargo_members(file) abort
  let l:section = ''
  let l:text = ''
  for l:line in readfile(a:file)
    let l:line = substitute(l:line, '\s*#.*', '', '')
    if !empty(l:text)
      let l:text .= l:line
    elseif l:line =~# '^\s*\['
      let l:section = matchstr(l:line, '^\s*\[\+\s*\zs[^]]\{-}\ze\s*\]')
    elseif l:section ==# 'workspace' && l:line =~# '^\s*members\s*='
      let l:text = l:line
    endif
    if l:text =~# '\]'
      break
    endif
  endfor
  let l:members = []
  call substitute(matchstr(l:text, '=\zs.*'), '["'']\([^"'']\+\)["'']', '\=add(l:members, submatch(1))[-1]', 'g')
  return filter(l:members, 'v:val !=# "."')
endfunction

function! s:rust() abort
  let l:file = s:find_up('Cargo.toml')
  if empty(l:file)
    return ''
  endif
  let l:root = fnamemodify(l:file, ':h')
  let l:sources = ['src']
  let l:crates = []
  for l:member in s:cargo_members(l:file)
    let l:found = map(glob(l:root . '/' . l:member . '/Cargo.toml', 1, 1),
          \ 'fnamemodify(v:val, ":h")[len(l:root) + 1 :]')
    call extend(l:crates, l:found)
    " crates/* is one place to search, however many crates are in it
    call extend(l:sources, empty(l:found) || l:member !~# '/\*$' ? l:found : [l:member[: -3]])
  endfor
  let l:name = s:toml_string(l:file, 'package', 'name')
  return {
        \ 'name': empty(l:name) ? s:directory_name(l:root) : l:name,
        \ 'root': l:root,
        \ 'language': 'rust',
        \ 'sources': s:existing_dirs(l:root, l:sources),
        \ 'tests': s:existing_dirs(l:root, ['tests'] + map(copy(l:crates), 'v:val . "/tests"')) + ['tests.rs'],
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
let s:order = ['python', 'go', 'rust', 'vim']
let s:strategies = {
      \ 'python': {'detect': function('s:python')},
      \ 'go': {'detect': function('s:go')},
      \ 'rust': {'detect': function('s:rust')},
      \ 'vim': {'detect': function('s:vim')},
      \ 'declared': {'detect': function('s:declared')},
      \ }

" A file's language, where more than one part could have it. Any other
" language is taken to be its own extension.
let s:extensions = {'python': ['py', 'pyi'], 'rust': ['rs']}
