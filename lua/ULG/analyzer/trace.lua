-- lua/ULG/analyzer/trace.lua

local M = {}

---
-- GameThreadのイベントツリーからフレームごとの統計データを抽出する
-- @param events table GameThreadのイベントツリー
-- @return table フレームごとのデータの配列 { { duration_ms, events_tree, frame_start_time, frame_end_time }, ... }
function M.analyze_gamethread_frames(events)
  if not events then return {} end

  local frames = {}
  for i, top_level_event in ipairs(events) do
    if top_level_event.name and top_level_event.name == "FEngineLoop::Tick" then
      local duration_ms = (top_level_event.e - top_level_event.s) * 1000
      
      table.insert(frames, {
        frame_number = #frames + 1,
        duration_ms = duration_ms,
        -- ★★★ 開始時刻と終了時刻を分かりやすい名前で追加 ★★★
        frame_start_time = top_level_event.s,
        frame_end_time = top_level_event.e,
        -- ★★★ ここまで ★★★
        events_tree = top_level_event.children,
      })
    end
  end

  return frames
end

-- ★★★ ここから最適化版の get_events_in_range ★★★
---
-- 指定された時間範囲に存在するイベントを、スレッドごとに収集する (最適化版)
-- @param trace_handle table ULG.cache.trace のハンドル
-- @param start_time number 収集開始時間 (秒)
-- @param end_time number 収集終了時間 (秒)
-- @return table { [thread_name] = { event, ... }, ... }
-- lua/ULG/analyzer/trace.lua (get_events_in_range の完全なコード)

function M.get_events_in_range(trace_handle, start_time, end_time, opts)
  opts = opts or {}
  local events_by_thread = {}
  local all_threads_map = trace_handle:get_available_threads()
  
  local threads_to_process = {}
  if opts.thread_names and type(opts.thread_names) == "table" then
    for _, name in ipairs(opts.thread_names) do
      for id, data in pairs(all_threads_map) do
        if data.name == name then
          threads_to_process[id] = data; break
        end
      end
    end
  else
    threads_to_process = all_threads_map
  end

  for thread_id, thread_info in pairs(threads_to_process) do
    local top_level_events = trace_handle:get_thread_events(thread_info.name)
    if not top_level_events then goto continue end

    local events_in_range = {}

    local function find_overlapping_events_recursive(events_tree)
      local result = {}
      for _, event in ipairs(events_tree) do
        if event.e < start_time or event.s > end_time then goto continue end
        local event_in_range = { name = event.name, s = event.s, e = event.e, tid = event.tid }
        if event.children and #event.children > 0 then
          event_in_range.children = find_overlapping_events_recursive(event.children)
        else
          event_in_range.children = {}
        end
        table.insert(result, event_in_range)
        ::continue::
      end
      return result
    end

    for _, event in ipairs(top_level_events) do
      if event.s > end_time then break end
      if event.e > start_time then
        local event_in_range = { name = event.name, s = event.s, e = event.e, tid = event.tid }
        if event.children and #event.children > 0 then
          event_in_range.children = find_overlapping_events_recursive(event.children)
        else
          event_in_range.children = {}
        end
        table.insert(events_in_range, event_in_range)
      end
    end

    if #events_in_range > 0 then
      local key = string.format("%s (%s)", thread_info.name, thread_info.group or "Default")
      events_by_thread[key] = events_in_range
    end
    ::continue::
  end
  return events_by_thread
end


return M
