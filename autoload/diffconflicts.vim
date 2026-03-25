let s:save_cpo = &cpo
set cpo&vim

let g:diffconflicts_vcs = get(g:, "diffconflicts_vcs", "git")

function! diffconflicts#has_conflicts()
    try
        silent execute "%s/^<<<<<<< //gn"
        return 1
    catch /Pattern not found/
        return 0
    endtry
endfunction

function! diffconflicts#diffconfl()
    let l:orig_buf = bufnr("%")
    let l:orig_ft = &filetype

    if g:diffconflicts_vcs == "git"
        " Obtain the git setting for the conflict style.
        let l:conflict_style = 'diff3'
    else
        " Assume 2way conflict style otherwise.
        let l:conflict_style = "diff"
    endif

    " Set up the right-hand side.
    rightb vnew
    silent execute "read #". l:orig_buf
    1delete_
    silent 0file
    silent execute "set filetype=". l:orig_ft
    diffthis " set foldmethod before editing
    silent execute "g/^<<<<<<< /,/^=======\\r\\?$/d"
    silent execute "g/^>>>>>>> /d"
    setlocal nomodifiable readonly buftype=nofile bufhidden=delete nobuflisted

    " Set up the left-hand side.
    wincmd p
    diffthis " set foldmethod before editing
    if l:conflict_style ==# "diff3"
        silent execute "g/^||||||| \\?/,/^>>>>>>> /d"
    else
        silent execute "g/^=======\\r\\?$/,/^>>>>>>> /d"
    endif
    silent execute "g/^<<<<<<< /d"

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

    " Put cursor in back in BASE.
    wincmd h
endfunction

function! diffconflicts#check_then_show_history()
    if g:diffconflicts_vcs == "hg"
        let l:filecheck = 'v:val =~# "\\~base\\." || v:val =~# "\\~local\\." || v:val =~# "\\~other\\."'
    else
        let l:filecheck = 'v:val =~# "BASE" || v:val =~# "LOCAL" || v:val =~# "REMOTE"'
    endif
    let l:xs =
        \ filter(
        \   map(
        \     filter(
        \       range(1, bufnr('$')),
        \       'bufexists(v:val)'
        \     ),
        \     'bufname(v:val)'
        \   ),
        \   l:filecheck
        \ )

    if len(l:xs) < 3
        echoerr "Missing one or more of BASE, LOCAL, REMOTE."
            \   ." Was Vim invoked by a Git mergetool?"
        return
    endif

    call diffconflicts#show_history()
endfunction

function! diffconflicts#check_then_diff()
    if diffconflicts#has_conflicts()
        echohl WarningMsg
        echon "Resolve conflicts leftward then save. Use :cq to abort"
        echohl None

        call diffconflicts#diffconfl()
    else
        echohl WarningMsg
        echo "No conflict markers found"
        echohl None
    endif
endfunction
