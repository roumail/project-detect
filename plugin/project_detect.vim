" project-detect: recognise the current project and describe its layout.
" No dependencies. Python and Go are built in; more can be registered.
if exists('g:loaded_project_detect')
  finish
endif
let g:loaded_project_detect = 1

" Detect once everything is loaded, unless a plugin asked for the project
" earlier
augroup project_detect
  autocmd!
  autocmd VimEnter * call project_detect#detect()
augroup END
