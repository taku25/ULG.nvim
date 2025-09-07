return {
  -- ================================================================
  -- UE Log Viewer用 (ULG.window.help.lua から参照)
  -- ================================================================
  ue = {
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
    "  {remote_command_prompt}      Execute Remote Editor Command",
    "  {toggle_timestamp}      Toggle timestamp visibility",
    "  {clear_content}      Clear all log content from view",
    "  {show_help}      Show/Hide this help window",
    "",
    "────────────────────────────────────────",
    "Press q, esc, ? to close this window.",
  },

  -- ================================================================
  -- Trace Summary Viewer用 (ULG.window.trace_help.lua から参照)
  -- ================================================================
  trace = {
    "ULG.nvim - Trace Summary Help",
    "",
    "────────────────────────────────────────",
    "Navigation:",
    "  {scroll_left} / {scroll_right}        Scroll frame by frame",
    "  {scroll_left_page} / {scroll_right_page}        Scroll page by page",
    "  {first_frame} / {last_frame}          Jump to first/last frame",
    "",
    "Spike Navigation:",
    "  {prev_spike} / {next_spike}          Jump to previous/next spike",
    "  {first_spike} / {last_spike}        Jump to first/last spike",
    "",
    "View Control:",
    "  {show_details}       Show frame details in a floating window",
    "  {toggle_scale_mode}       Toggle sparkline scale mode",
    "  {show_help}       Show/Hide this help window",
    "",
    "────────────────────────────────────────",
    "Press q, esc, ? to close this window.",
  }
}
