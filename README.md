# project-detect

Names the current project, using detection strategies you register. It ships
no strategies of its own and depends on nothing; other plugins (such as
[grepscope](https://github.com/roumail/grepscope)) read the
result.

```vim
" Python: the project is named in the nearest pyproject.toml
function! s:pyproject_name() abort
  let l:file = findfile('pyproject.toml', '.;')
  if empty(l:file)
    return ''
  endif
  for l:line in readfile(l:file)
    if l:line =~ '^name\s*='
      return matchstr(l:line, '"\zs[^"]\+\ze"')
    endif
  endfor
  return ''
endfunction

call project_detect#register('python', {'detect': function('s:pyproject_name')})
```

- `detect()` returns the project name, or `''` when this is not such a project.
- At startup (`VimEnter`) strategies are tried in registration order and the
  first that returns a name wins. A strategy registered later triggers a new
  attempt if nothing matched yet.

| Result | |
| --- | --- |
| `project_detect#name()` | The detected name, or `''`. Other plugins read the name through this. |
| `project_detect#active()` | The matching strategy (`'python'` above), or `''`. |
| `g:project_name` | Where the name is stored. Set it yourself beforehand to override the name only. |
| `project_detect#strategies()` | Registered strategy names, in detection order. |
| `User ProjectDetected` | Fired after a strategy matches. |

## Install

```vim
Plug 'roumail/project-detect'
```
