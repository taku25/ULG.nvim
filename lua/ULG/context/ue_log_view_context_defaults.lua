-- lua/ULG/context/ue_log_view_context_defaults.lua

-- UE Logビューの状態のデフォルト値
return {
  handle = nil,
  tailer = nil,
  master_lines = {},

  -- フィルタリングやUIの状態
  filter_query = nil,
  category_filters = {},
  filters_enabled = true,
  search_query = nil,
  search_hl_id = nil,
  hide_timestamp = true,
  is_watching = false,
  
  -- ヘルプウィンドウの状態
  help_win = nil,
  help_buf = nil,
}
