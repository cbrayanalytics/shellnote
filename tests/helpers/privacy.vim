set swapfile backup writebackup undofile
set shada=!,'100,<50,s10,h
autocmd VimEnter * call writefile([string(&swapfile), string(&backup), string(&writebackup), string(&undofile), &shada, string(line('.')), expand('%:p')], $TEST_NVIM_RESULT) | qa!
