# project-detect

Recognises the project Vim is started in and describes it: its type, name,
language, root, where its code and tests live, and how its tests run. Other
plugins build on the description:
[fzf-utils](https://github.com/roumail/fzf-utils) greps its scopes and
[pytest.vim](https://github.com/roumail/pytest.vim) binds keys in its test
files. It depends on nothing.

Python and Go projects are recognised out of the box:

| Type | Recognised by | Name | Code | Tests | Test command |
| --- | --- | --- | --- | --- | --- |
| `python` | `pyproject.toml` | `name` in `[project]` or `[tool.poetry]` | the import package: `src/<pkg>/` or `<pkg>/` | `tests/`, `test/`, `test_*.py`, `*_test.py` | `pytest` |
| `go` | `go.mod` | last element of the module path, without a `/vN` suffix | the whole module | `*_test.go` | `go test` |

The marker file is looked up from the working directory upwards, so Vim can be
started anywhere inside the project, for example in a Go module's `cmd/app`.

## The project is the working directory

The project is detected once, from the directory Vim starts in: at `VimEnter`,
or as soon as a plugin asks for it. Opening files elsewhere, or files that
belong to another project, does not change it.

| Result | |
| --- | --- |
| `project_detect#active()` | The project type (`'python'`, `'go'`), or `''`. |
| `project_detect#name()` | The project name, or `''`. |
| `project_detect#language()` | The project's language (`'python'`, `'go'`), or `''`. |
| `project_detect#root()` | The project root directory. |
| `project_detect#sources()` | Where the code lives, relative to the root. |
| `project_detect#tests()` | Where the tests live, relative to the root. |
| `project_detect#is_test([file])` | Whether a file (default: the current buffer's) is one of the tests. |
| `project_detect#scopes()` | The parts of the project to search: `project` and `tests`, each also limited to the language (`project python`). |
| `project_detect#runner(language)` | How a language's tests run: `{'run': …, 'debug': …}`. |
| `g:project_name` | Where the name is stored. Set it yourself beforehand to override the name only. |
| `project_detect#strategies()` | Strategy names, in detection order. |
| `User ProjectDetected` | Fired after a strategy matches. |

In `sources()` and `tests()`, entries ending in `/` are directories; the rest
are file-name globs. A file belongs when it is in one of the directories or
matches one of the globs.

## Test commands: `g:project_detect_runners`

Set the commands for a language to run its tests your way. `debug` runs
interactive debugging sessions (pytest's `--trace` / `--pdb`) and defaults to
`run`:

```vim
let g:project_detect_runners = {
      \ 'python': {'run': 'chkpyt.sh', 'debug': 'chkpyt.sh --no-default-addopts'},
      \ }
```

## More project types

A strategy recognises one type of project. Register your own for other
layouts, or under `'python'` / `'go'` to replace a built-in one:

```vim
" Python packages that only have a setup.cfg
function! s:setup_cfg() abort
  let l:file = findfile('setup.cfg', escape(getcwd(), ' ,\') . ';')
  if empty(l:file)
    return ''
  endif
  let l:name = matchstr(join(readfile(l:file), "\n"), '\n\s*name\s*=\s*\zs[^[:space:]]\+')
  return {
        \ 'name': l:name,
        \ 'root': fnamemodify(l:file, ':p:h'),
        \ 'language': 'python',
        \ 'sources': [l:name . '/'],
        \ 'tests': ['tests/'],
        \ }
endfunction

call project_detect#register('python-setupcfg', {'detect': function('s:setup_cfg')})
```

- `detect()` returns `''` when this is not such a project. Otherwise it returns
  the project name, or a dict with `name` and any of `root` (default: the
  working directory), `language`, `sources` and `tests` (default: `[]`).
- Strategies are tried in order, built-in ones first, and the first match wins.
  A strategy registered after detection ran without a match triggers a new
  attempt.
- Search from `getcwd()`, as above, rather than from the current buffer (`'.;'`,
  `expand('%')`). At `VimEnter` the current buffer can be anything: netrw, or
  fugitive's status window after `vim . -c Git`.

## Install

```vim
Plug 'roumail/project-detect'
```
