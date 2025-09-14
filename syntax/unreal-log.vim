" Vim syntax file
" Language: Unreal Engine Log
" Maintainer: taku25
" Last Change: 2025 Sep 14

" もし既にシンタックスが定義されていたら、何もしない
if exists("b:current_syntax")
  finish
endif

" Luaヘルパーを呼び出して、ハイライトルールのリストを取得する
let s:rules = v:lua.require('ULG.syntax').get_highlight_rules()

" 取得したルールをループして、'syntax match'コマンドを動的に生成・実行する
for rule in s:rules
  " executeコマンドを使って、変数からコマンドを組み立てる
  " 'rule.pattern'内のシングルクォートをエスケープして、コマンドが壊れないようにする
  " ★★★ ここが修正点です: 'l:' を削除しました ★★★
  let escaped_pattern = substitute(rule.pattern, "'", "''", 'g')
  
  " 'contains=@NoSpell' はスペルチェックを無効化するおまじない
  " ★★★ ここも修正点です: 'l:' を削除しました ★★★
  execute 'syntax match' rule.hl_group "'" . escaped_pattern . "' contains=@NoSpell"
endfor

" このバッファのシンタックス名を 'unreal-log' に設定したことを記録する
let b:current_syntax = "unreal-log"
