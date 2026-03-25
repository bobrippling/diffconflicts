" Two-way diff each side of a file with Git conflict markers
" License: MIT

command! DiffConflicts call diffconflicts#check_then_diff()
command! DiffConflictsShowHistory call diffconflicts#check_then_show_history()
