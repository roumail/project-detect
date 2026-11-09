# project-detect

Recognises the project Vim starts in, and describes it for other plugins: its
type, name, language, root, and where its code and tests live. Python
(`pyproject.toml`, `setup.py`, `setup.cfg`, `Pipfile`, `requirements.txt`,
`tox.ini`, `manage.py`, `wsgi.py` or `app.py`), Go (`go.mod`), Rust
(`Cargo.toml`) and Vim plugin projects work out of the box, alone or together in
one directory.

**Vim or Neovim:** tested on Vim 9.1 and newer. It's plain Vimscript, so it may
work on Neovim, but that's untested.

**Repositories:** tested on repositories that hold one project. It may work in
a monorepo, but that's untested.

**Where to start Vim:** open Vim at the project root. That's the setup that's
tested and encouraged.

## Install

```vim
Plug 'vimoured/project-detect'
```

## Use

The project is detected once, from the directory Vim starts in or above it.

| Function | Returns |
| --- | --- |
| `project_detect#active()` | The project type, or `''`. |
| `project_detect#name()` | The project name, or `''`. |
| `project_detect#root()` | The project root. |
| `project_detect#parts()` | One entry per language: its `language`, `sources` and `tests`. |
| `project_detect#part([file])` | The part a file belongs to, or `{}`. |
| `project_detect#is_test([file])` | Whether a file is one of its part's tests. |

A Python or Rust project with no name of its own is named after its directory.

Set `g:project_name` to use it in place of detecting a name. It's enough to make
the directory a project, with tests in `tests/` or `test/`. In that project, and
in a Python one without maturin's `python-source`, it's the folder to search, at
the root or in `src/`: Vim shows an error at startup if there's no such folder.

Add another project type with
`project_detect#register(name, {'detect': function('s:detect')})`. `detect()`
returns `''` when it isn't that kind of project, else the project name or a dict
with `name` and any of `root`, `language`, `sources` and `tests`.

## Tests

The specs in [vim-suite](https://github.com/vimoured/vim-suite) define what it
does: `test/project-detect.vim`.
