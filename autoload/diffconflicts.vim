let g:diffconflicts_vcs = get(g:, "diffconflicts_vcs", "git")

" a jj diff looks like:
" <<<<<<<<
" ++++++
" original code here
"
" %%%% from
" \\\\ to
" patch 1 here
"
" %%%% from
" \\\\ to
" patch 2 here
"
" %%%% ...
" \\\\ ...
" ...
" >>>>>>>>
"
" the "+++" block might not be at the start so we parse through them and
" create new windows for each side

function! diffconflicts#split() abort
  let orig_buf = bufnr("%")
  let orig_ft = &filetype

  " git mode? jj mode?
  call cursor(1, 1)
  let jj = search('^%%%%%%% diff from: ', 'cn') > 0

  if jj
    call s:split_jj(orig_buf, orig_ft)
    return
  endif

  call s:vnew(orig_buf, orig_ft)

  " git/hg
  silent g/^<<<<<<< /,/^=======\r\?$/d
  silent g/^>>>>>>> /d

  call s:vnew_end()

  wincmd p
  diffthis " set foldmethod before editing

  let diff3 = search('^||||||| \?') > 0
  if diff3
    silent g/^||||||| \?/,/^>>>>>>> /d
  else
    silent g/^=======\r\?$/,/^>>>>>>> /d
  endif
  silent g/^<<<<<<< /d

  diffupdate
endfunction

function! s:split_jj(orig_buf, orig_ft) abort
  let groups = []

  call cursor(1, 1)
  let cur = 0

  while 1
    let i = search('^[%\\<>+]\+ ', 'ceWz')
    if i == 0
      break
    endif

    let line = getline(i)
    if cur is 0
      if line !~ '^<'
        throw "Expected '<<<...' marker"
      endif

      let cur = { "start": i, "markers": [] }
      continue
    endif

    if line =~ '^[%\\+]'
      call add(cur["markers"], { "lno": i, "text": line })
      continue
    endif

    if line =~ '^>'
      let cur["end"] = i
      call add(groups, cur)
      let cur = 0
      continue
    endif

    throw "Invalid line: \"" .. line .. "\""
  endwhile

  let sides = {} " set of side names
  for group in groups
    for marker in group["markers"]
      let text = marker["text"]

      let side = substitute(text, '^\v\S+( diff from:| +to:|\+) (.*)', '\2', '')
      if side ==# text
        throw "Couldn't extract side from \"" .. text .. "\""
      endif

      let marker["side"] = side

      " ignore the "from" parts - we don't want sides for them
      if stridx(text, "from:") >= 0
        continue
      endif

      " dict[x] = 1
      let sides[side] = get(sides, side, 1)
    endfor
  endfor

  let win_cur = win_getid()
  if win_cur == 0
    throw "couldn't get current window id"
  endif
  let [first; sides] = keys(sides)

  for side in sides
    call s:vnew(a:orig_buf, a:orig_ft)

    " introduce only our diff entry
    call s:jj_reduce_conflict(side, groups)

    call s:vnew_end()
  endfor

  call win_gotoid(win_cur)
  set nowrap
  call s:jj_reduce_conflict(first, groups)
  difft
  wincmd =
endfunction

function! s:jj_reduce_conflict(name, groups) abort
  let deletes = [] " delete from a..<b, depending on c

  for group in a:groups
    let anchor = group["start"]
    let anchor_undiff = -1

    for marker in group["markers"]
      let lno = marker["lno"]

      if anchor != -1
        call add(deletes, [anchor, lno - 1, 0])
      endif

      if anchor_undiff != -1
        call s:add_undiff(anchor_undiff, lno - 1, deletes)
        let anchor_undiff = -1
      endif

      let is_plain_side = marker["text"][0] ==# "+"
      let should_keep = marker["side"] ==# a:name

      if should_keep
        " keep this side, just delete the current marker
        call add(deletes, [lno, lno, 0])

        let anchor = -1

        " do we want to remove the diff +/- parts?
        if !is_plain_side
          let anchor_undiff = lno + 1
        endif
      else
        " drop this side
        let anchor = lno
      endif
    endfor

    if anchor_undiff != -1
      call s:add_undiff(anchor_undiff, group["end"] - 1, deletes)
      let anchor_undiff = -1
    endif

    let from = anchor == -1 ? group["end"] : anchor
    call add(deletes, [from, group["end"], 0])
  endfor

  let debug = !empty($DIFFCONFLICTS_DEBUG)
  if debug
    call append('$', 'for side "' .. a:name .. '"')
  endif

  for [a, b, type] in reverse(deletes)
    if type == 0
      let cmd = a .. "," .. b .. "delete"
    elseif type == 1
      let cmd = a .. "," .. b .. "g/^-\\|^DELETE_ME_ZZZ$/d"
    elseif type == 2
      let range = a .. "," .. b
      let cmd = [range .. "s/^-.*/DELETE_ME_ZZZ/e", range .. "s/^.//e"]
    else
      throw "unknown delete type " .. type
    endif

    for cmd_ in type(cmd) == v:t_list ? cmd : [cmd]
      if debug
        call append('$', cmd_ .. " (type " .. type .. ")")
      else
        execute "silent" cmd_
      endif
    endfor
  endfor
endfunction

function! s:add_undiff(a, b, deletes) abort
  let a = a:a
  let b = a:b

  if a > b
    let t = a
    let a = b
    let b = t
  endif

  " add this in reverse, because they then get reversed
  call add(a:deletes, [a, b, 1]) " delete
  call add(a:deletes, [a, b, 2]) " s/^.//
endfunction

function! s:vnew(orig_buf, orig_ft) abort
  rightb vnew
  silent execute "read #". a:orig_buf
  1delete_
  silent 0file
  silent execute "set filetype=" . a:orig_ft
  diffthis " set foldmethod before editing
endfunction

function! s:vnew_end() abort
  setlocal nomodifiable readonly buftype=nofile bufhidden=hide nobuflisted nowrap
endfunction

function! diffconflicts#show_history() abort
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
