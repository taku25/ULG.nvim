-- lua/ULG/analyzer/trace.lua (フレームイベント名修正版)

local M = {}

---
-- GameThreadのイベントツリーからフレームごとの統計データを抽出する
-- @param events table GameThreadのイベントツリー
-- @return table フレームごとのデータの配列 { { duration_ms, events_tree }, ... }
function M.analyze_gamethread_frames(events)
  if not events then return {} end

  local frames = {}
  for i, top_level_event in ipairs(events) do
    -- ★★★ 修正点: フレームを示すイベント名を "FEngineLoop::Tick" に変更 ★★★
    if top_level_event.name and top_level_event.name == "FEngineLoop::Tick" then
      local duration_ms = (top_level_event.e - top_level_event.s) * 1000
      
      table.insert(frames, {
        frame_number = #frames + 1,
        duration_ms = duration_ms,
        -- このフレーム内の詳細なイベントツリー（子イベント）を保持
        events_tree = top_level_event.children,
      })
    end
  end

  return frames
end

return M
