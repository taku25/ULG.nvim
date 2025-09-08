-- lua/ULG/window/gantt_chart.lua (描画ロジック実装版)

local M = {}

local state = {
  win = nil, buf = nil, trace_handle = nil, frame_data = nil,
  display_opts = {}, is_showing_all = false,
}

local function close_window()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_close(state.win, true)
  end
  state = { win = nil, buf = nil, trace_handle = nil, frame_data = nil, display_opts = {}, is_showing_all = false }
end

local function redraw_buffer()
  if not (state.buf and vim.api.nvim_buf_is_valid(state.buf)) then return end

  local trace_analyzer = require("ULG.analyzer.trace")
  
  local center_time = state.frame_data.frame_start_time
  local time_range_sec = (state.display_opts.time_range_ms or 16.6) / 1000
  local time_radius_sec = time_range_sec / 2
  local start_time, end_time = center_time - time_radius_sec, center_time + time_radius_sec

  local analyzer_opts = {}
  if not state.is_showing_all then
    local conf = require("UNL.config").get("ULG")
    analyzer_opts.thread_names = conf.gantt.default_threads
  end
  local events_by_thread = trace_analyzer.get_events_in_range(state.trace_handle, start_time, end_time, analyzer_opts)

  local lines = {
    "ULG Gantt Chart", "====================================",
    string.format("Frame: %d (%.3fms) | Center: %.3fs", state.frame_data.frame_number, state.frame_data.duration_ms, center_time),
    string.format("Displaying %.1fms (%.3fs to %.3fs)", time_range_sec * 1000, start_time, end_time),
    "------------------------------------", "Keymaps: [q] close | [a] all threads | Work: █  Wait: ░", "",
  }

  local total_width = vim.api.nvim_win_get_width(state.win)
  local thread_name_margin = 45
  local chart_width = total_width - thread_name_margin - 3
  if chart_width <= 0 then
    table.insert(lines, "Window is too narrow.")
  else
    local sec_per_char = time_range_sec / chart_width
    local sorted_threads = {}
    for name, _ in pairs(events_by_thread) do table.insert(sorted_threads, name) end
    local priority_threads = { "GameThread", "RenderThread", "RHIThread" }
    table.sort(sorted_threads, function(a, b)
      local a_base, b_base = a:match("([^ ]+)"), b:match("([^ ]+)")
      local a_prio, b_prio = #priority_threads + 1, #priority_threads + 1
      for i, p_name in ipairs(priority_threads) do
        if a_base == p_name then a_prio = i end
        if b_base == p_name then b_prio = i end
      end
      if a_prio ~= b_prio then return a_prio < b_prio end
      return a < b
    end)

    -- ★★★ ここからが新しい描画ロジック ★★★
    
    -- イベント名が「待機」を示しているか判定するヘルパー関数
    local function is_wait_event(name)
      if not name then return false end
      return name:find("Wait") or name:find("Stall") or name:find("Idle") or name:find("Sync")
    end

    for _, thread_name in ipairs(sorted_threads) do
      local char_array = {}
      for i = 1, chart_width do char_array[i] = "─" end

      -- イベントツリーを再帰的に描画する関数
      -- 子イベントは親イベントを上書きするため、詳細な情報が優先される
      local function fill_chart_recursive(events)
        for _, event in ipairs(events) do
          local event_start_rel = math.max(0, event.s - start_time)
          local event_end_rel = math.min(time_range_sec, event.e - start_time)
          if event_end_rel <= event_start_rel then goto continue end

          local start_idx = math.floor(event_start_rel / sec_per_char) + 1
          local end_idx = math.ceil(event_end_rel / sec_per_char)
          
          -- ★ 待機イベントかワークイベントかで文字を決定
          local char_to_draw = is_wait_event(event.name) and "░" or "█"

          for i = start_idx, end_idx do
            if i >= 1 and i <= chart_width then
              char_array[i] = char_to_draw
            end
          end
          
          -- 子イベントを再帰的に描画 (上書き)
          if event.children and #event.children > 0 then
            fill_chart_recursive(event.children)
          end
          ::continue::
        end
      end
      
      fill_chart_recursive(events_by_thread[thread_name])

      local chart_str = table.concat(char_array)
      local line_str = string.format("%-" .. thread_name_margin .. "s |%s|", thread_name, chart_str)
      table.insert(lines, line_str)
    end
    -- ★★★ 描画ロジックここまで ★★★
  end

  vim.api.nvim_set_option_value("modifiable", true, { buf = state.buf })
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  vim.api.nvim_set_option_value("modifiable", false, { buf = state.buf })
end

-- M.open と M.toggle_all_threads は変更なし
function M.open(trace_handle, frame_data, opts)
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    close_window()
  end
  state.trace_handle, state.frame_data, state.display_opts = trace_handle, frame_data, opts or { time_range_ms = 16.6 }
  state.is_showing_all = false
  state.buf = vim.api.nvim_create_buf(false, true)
  vim.bo[state.buf].buftype = "nofile"; vim.bo[state.buf].swapfile = false
  
  local width = math.floor(vim.o.columns * 0.9)
  local height = math.floor(vim.o.lines * 0.6)
  local row, col = math.floor((vim.o.lines - height) / 2), math.floor((vim.o.columns - width) / 2)
  state.win = vim.api.nvim_open_win(state.buf, true, {
    relative = "editor", width = width, height = height, row = row, col = col,
    style = "minimal", border = "rounded", title = "ULG Gantt Chart (Frame " .. frame_data.frame_number .. ")",
  })
  
  -- 初回描画はwinのIDが確定してから行う
  redraw_buffer()

  local map_opts = { noremap = true, silent = true }
  vim.api.nvim_buf_set_keymap(state.buf, "n", "q", "<cmd>lua require('ULG.window.gantt_chart').close()<cr>", map_opts)
  vim.api.nvim_buf_set_keymap(state.buf, "n", "a", "<cmd>lua require('ULG.window.gantt_chart').toggle_all_threads()<cr>", map_opts)
end

M.close = close_window

function M.toggle_all_threads()
  if not (state.win and vim.api.nvim_win_is_valid(state.win)) then return end
  state.is_showing_all = not state.is_showing_all
  if state.is_showing_all then
    vim.notify("Loading all threads, this may take a moment...", vim.log.levels.INFO)
  end
  vim.schedule(redraw_buffer)
end

return M
