-- lua/ULG/context/trace_log_view_context_defaults.lua

-- Trace Logビューの状態のデフォルト値
return {
  handle = nil,         -- trace viewのバッファハンドル
  trace_handle = nil,   -- 解析済みutraceデータのハンドル
  frames_data = nil,
  display_mode = "33ms",
  global_stats = { avg = 0, max = 0 },
  spike_indices = {},
  autocmd_group = nil,
  vtext_ns_id = nil,
}
