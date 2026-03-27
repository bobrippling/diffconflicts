let g:diffconflicts_vcs = get(g:, "diffconflicts_vcs", "git")

function! diffconflicts#split()
  let orig_buf = bufnr("%")
  let orig_ft = &filetype

  " Set up the right-hand side
  rightb vnew
  silent execute "read #". orig_buf
  1delete_
  silent 0file
  silent execute "set filetype=" . orig_ft
  diffthis " set foldmethod before editing

  " git mode? jj mode?
  call cursor(1, 1)
  let jj = search('^%%%%%%% diff from: ', 'cn') > 0
  if jj
    silent g/^<<<<<<< /,/^+++++++/d
    silent g/^>>>>>>> /d
  else
    " git/hg
    silent g/^<<<<<<< /,/^=======\r\?$/d
    silent g/^>>>>>>> /d
  endif

  setlocal nomodifiable readonly buftype=nofile bufhidden=delete nobuflisted

  " Set up the left-hand side
  wincmd p
  diffthis " set foldmethod before editing
  if jj
    silent /^%%%%%%% /,/^+++++++ /g/^-/d
    1
    silent /^%%%%%%% /++,/^+++++++ /-s/^.

    silent g/^%%%%%%%\|\\\\\\\\\\\\\\\|<<<<<<</d
    silent g/^+++++++ /,/^>>>>>>> /d
  else
    if search('^||||||| \?') > 0
      " diff3
      silent g/^||||||| \?/,/^>>>>>>> /d
    else
      silent g/^=======\r\?$/,/^>>>>>>> /d
    endif
    silent g/^<<<<<<< /d
  endif

  diffupdate
endfunction

function! diffconflicts#show_history()
  tabnew

  if g:diffconflicts_vcs == "hg"
    buffer ~local.
    file LOCAL
  else
    buffer LOCAL
  endif
  setlocal nomodifiable readonly
  diffthis

  if g:diffconflicts_vcs == "hg"
    vert sbuffer ~base.
    file BASE
  else
    vert sbuffer BASE
  endif
  setlocal nomodifiable readonly
  diffthis

  if g:diffconflicts_vcs == "hg"
    vert sbuffer ~other.
    file OTHER
  else
    vert sbuffer REMOTE
  endif
  setlocal nomodifiable readonly
  diffthis

  wincmd h
endfunction
