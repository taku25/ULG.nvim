" Vim syntax file
" Language: Unreal Engine Log for ULG.nvim
" Filetype: ulg-general-log

if exists("b:current_syntax")
  finish
endif

" --- 1. まず、中に含まれるパーツを定義する ---
" ファイルパス (スペース対応のGreedy Match)
syn match ulgLogFilePath '\v([A-Z]:[\\/]|[\\/]).*(\.h|\.cpp|\.c)\(\d+(,\d+)?\)' contained contains=ulgLogLineNr
" ファイルパスに含まれる行番号
syn match ulgLogLineNr '(\d\+\(,\d\+\)\?)' contained

" --- 2. 次に、行全体をハイライトする大きな入れ物を定義 ---
"    contains=... で、中に上記のパーツが含まれることを許可する
" 'error' という単語が含まれる行全体
syn match ulgLogErrorLine /.*error.*/ contains=ulgLogFilePath
" 'warning' という単語が含まれる行全体
syn match ulgLogWarningLine /.*warning.*/ contains=ulgLogFilePath

" --- その他のルール ---
syn match ulgLogMeta "^\s*Log[a-zA-Z0-9_]\+:"
syn match ulgLogObjectPath "'/Game/[^']\+'"

" ### 標準ハイライトグループへのリンク ###
" 行全体
hi def link ulgLogErrorLine   Error
hi def link ulgLogWarningLine WarningMsg

" 行の中に含まれるパーツ
hi def link ulgLogFilePath    Directory " 標準ではディレクトリの色
hi def link ulgLogLineNr      Number

" その他
hi def link ulgLogMeta        Type
hi def link ulgLogObjectPath  String
" Directoryグループの色を使いつつ、下線を追加する場合
highlight link ulgLogFilePath Directory
highlight default ulgLogFilePath cterm=underline gui=underline

let b:current_syntax = "ulg-general-log"
