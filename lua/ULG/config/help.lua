-- lua/ULG/config/help.lua
-- このファイルは、ヘルプウィンドウに表示されるテキストのテンプレートを定義します。
-- {keymap_name} の部分は、viewer.luaによってユーザーの現在のキー設定に動的に置き換えられます。

return {
  "ULG.nvim - Unreal Log Viewer Help",
  "",
  "────────────────────────────────────────",
  "Filtering & Searching:",
  "  {filter_prompt}      Set/Update Regex Filter",
  "  {category_filter_prompt}      Filter by Log Category (multi-select)",
  "  {search_prompt}      Highlight Regex in current view",
  "  {filter_toggle}      Toggle all filters ON / OFF",
  "  {filter_clear}  Clear all filters and highlights",
  "",
  "Navigation:",
  "  {jump_next_match}     Jump to NEXT filtered log line",
  "  {jump_prev_match}     Jump to PREV filtered log line",
  "  {jump_to_source}   Jump to source file location (if available)",
  "",
  "View Control:",
  "  {toggle_timestamp}      Toggle timestamp visibility",
  "  {clear_content}      Clear all log content from view",
  "  {show_help}      Show/Hide this help window",
  "",
  "────────────────────────────────────────",
  "Press ANY KEY to close this window.",
}
