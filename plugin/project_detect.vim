" project-detect: name the current project from registered strategies.
" No dependencies. Strategies come from your vimrc; none ship here.
if exists('g:loaded_project_detect')
  finish
endif
let g:loaded_project_detect = 1

" Run the registered strategies once everything is loaded
augroup project_detect
  autocmd!
  autocmd VimEnter * call project_detect#detect()
augroup END
