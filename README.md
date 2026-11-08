# project-detect

Recognises the project Vim starts in, and describes it for other plugins: its
type, name, language, root, where its code and tests live, and how its tests
run. Python (`pyproject.toml`), Go (`go.mod`) and Vim plugin projects work out
of the box.

**Vim or Neovim:** tested on Vim 9.1 and newer. It's plain Vimscript, so it may
work on Neovim, but that's untested.

## Install

```vim
Plug 'vimoured/project-detect'
```

## Use

The project is detected once, from the directory Vim starts in or above it.

| Function | Returns |
| --- | --- |
| `project_detect#active()` | The project type, or `''`. |
| `project_detect#name()` | The project name, or `''`. Set `g:project_name` to choose it. |
| `project_detect#language()` | The project's language, or `''`. |
| `project_detect#root()` | The project root. |
| `project_detect#sources()` | Where the code lives, relative to the root. |
| `project_detect#tests()` | Where the tests live, relative to the root. |
| `project_detect#is_test([file])` | Whether a file is one of the tests. |
| `project_detect#runner(language)` | How its tests run: `{'run': …, 'debug': …}`. |

Set the test commands for a language:

```vim
let g:project_detect_runners = {
      \ 'python': {'run': 'chkpyt.sh', 'debug': 'chkpyt.sh --no-default-addopts'},
      \ }
```

Add another project type with
`project_detect#register(name, {'detect': function('s:detect')})`. `detect()`
returns `''` when it isn't that kind of project, else the project name or a dict
with `name` and any of `root`, `language`, `sources` and `tests`.

## Tests

The specs in [vim-suite](https://github.com/vimoured/vim-suite) define what it
does: `test/project-detect.vim`.
