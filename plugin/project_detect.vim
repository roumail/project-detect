if exists('g:loaded_project_detect')
  finish
endif
let g:loaded_project_detect = 1

" Not at load time: plugins loaded later must be able to register a strategy
" that replaces a built-in one
augroup project_detect
  autocmd!
  autocmd VimEnter * call project_detect#detect()
augroup END
