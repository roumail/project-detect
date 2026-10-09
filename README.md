# project-detect

Recognises the project Vim is started in and describes it: its type, name,
root, and where its code and tests live. Other plugins (such as
[grepscope](https://github.com/roumail/grepscope)) read the description. It
depends on nothing.

Python and Go projects are recognised out of the box:

| Type | Recognised by | Name | Code | Tests |
| --- | --- | --- | --- | --- |
| `python` | `pyproject.toml` | `name` in `[project]` or `[tool.poetry]` | the import package: `src/<pkg>/` or `<pkg>/` | `tests/`, `test/` |
| `go` | `go.mod` | last element of the module path, without a `/vN` suffix | the whole module | `*_test.go` |

The marker file is looked up from the working directory upwards, so Vim can be
started anywhere inside the project, for example in a Go module's `cmd/app`.

## The project is the working directory

The project is detected once, at startup (`VimEnter`), from the directory Vim
starts in. Opening files elsewhere, or files that belong to another project,
does not change it.

| Result | |
| --- | --- |
| `project_detect#active()` | The project type (`'python'`, `'go'`), or `''`. |
| `project_detect#name()` | The project name, or `''`. |
| `project_detect#root()` | The project root directory. |
| `project_detect#sources()` | Where the code lives, relative to the root. |
| `project_detect#tests()` | Where the tests live, relative to the root. |
| `g:project_name` | Where the name is stored. Set it yourself beforehand to override the name only. |
| `project_detect#strategies()` | Strategy names, in detection order. |
| `User ProjectDetected` | Fired after a strategy matches. |

In `sources()` and `tests()`, entries ending in `/` are directories; the rest
are file-name globs.

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
  let l:root = fnamemodify(l:file, ':p:h')
  return {'name': l:name, 'root': l:root, 'sources': [l:name . '/'], 'tests': ['tests/']}
endfunction

call project_detect#register('python-setupcfg', {'detect': function('s:setup_cfg')})
```

- `detect()` returns `''` when this is not such a project. Otherwise it returns
  the project name, or a dict with `name` and any of `root` (default: the
  working directory), `sources` and `tests` (default: `[]`).
- Strategies are tried in order, built-in ones first, and the first match wins.
  A strategy registered after startup triggers a new attempt if nothing matched
  yet.
- Search from `getcwd()`, as above, rather than from the current buffer (`'.;'`,
  `expand('%')`). At `VimEnter` the current buffer can be anything: netrw, or
  fugitive's status window after `vim . -c Git`.

## Install

```vim
Plug 'roumail/project-detect'
```
