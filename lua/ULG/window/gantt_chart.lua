-- lua/ULG/window/gantt_chart.lua (ステートマネージャー対応版)

local unl_config = require("UNL.config")
local trace_analyzer = require("ULG.analyzer.trace")
local window_state = require("ULG.context.window_state") -- context/に移動したパス

local M = {}

local function close_window()
  local s = window_state.get_state("gantt_chart")
  if s.win and vim.api.nvim_win_is_valid(s.win) then
    vim.api.nvim_win_close(s.win, true)
  end
  window_state.reset_state("gantt_chart")
end

local function redraw_buffer()
  local s = window_state.get_state("gantt_chart")
  if not (s.buf and vim.api.nvim_buf_is_valid(s.buf)) then
    return
  end

  local conf = unl_config.get("ULG")
  
  local center_time = s.frame_data.frame_start_time
  local time_range_sec = (s.display_opts.time_range_ms or 16.6) / 1000
  local time_radius_sec = time_range_sec / 2
  local start_time = center_time - time_radius_sec
  local end_time = center_time + time_radius_sec

  local analyzer_opts = {}
  if not s.is_showing_all then
    analyzer_opts.thread_names = conf.gantt.default_threads
  end
  local events_by_thread = trace_analyzer.get_events_in_range(s.trace_handle, start_time, end_time, analyzer_opts)

  local lines = {
    "ULG Gantt Chart",
    "====================================",
    string.format("Frame: %d (%.3fms) | Center: %.3fs", s.frame_data.frame_number, s.frame_data.duration_ms, center_time),
    string.format("Displaying %.1fms (%.3fs to %.3fs)", time_range_sec * 1000, start_time, end_time),
    "------------------------------------",
    "Keymaps: [q] close | [a] all threads | [h] toggle hierarchy | Work: █  Wait: ░",
    "",
  }

  local total_width = vim.api.nvim_win_get_width(s.win)
  local thread_name_margin = 45
  local chart_width = total_width - thread_name_margin - 3
  
  if chart_width <= 0 then
    table.insert(lines, "Window is too narrow.")
  else
    local sec_per_char = time_range_sec / chart_width
    
    local sorted_threads = {}
    for name, _ in pairs(events_by_thread) do
      table.insert(sorted_threads, name)
    end
    
    local priority_threads = { "GameThread", "RenderThread", "RHIThread" }
    table.sort(sorted_threads, function(a, b)
      local a_base = a:match("([^ ]+)")
      local b_base = b:match("([^ ]+)")
      local a_prio = #priority_threads + 1
      local b_prio = #priority_threads + 1
      for i, p_name in ipairs(priority_threads) do
        if a_base == p_name then a_prio = i end
        if b_base == p_name then b_prio = i end
      end
      if a_prio ~= b_prio then
        return a_prio < b_prio
      end
      return a < b
    end)
    
    local gantt_hl_conf = conf.highlights.gantt_chart or {}
    local color_palette = gantt_hl_conf.color_palette or {}
    local wait_hl = gantt_hl_conf.wait_hl_group or "SpecialComment"
    
    local function string_hash(s)
      local hash = 5381
      for i = 1, #s do
        hash = (hash * 33) + string.byte(s, i)
      end
      return hash
    end
    
    local function is_wait_event(name)
      if not name then return false end
      return name:find("Wait") or name:find("Stall") or name:find("Idle") or name:find("Sync")
    end
    
    local highlights_to_apply = {}

    for _, thread_name in ipairs(sorted_threads) do
      if s.view_mode == "hierarchical" then
        local max_depth = 0
        local function find_max_depth(events, current_depth)
          for _, event in ipairs(events) do
            max_depth = math.max(max_depth, current_depth)
            if event.children and #event.children > 0 then
              find_max_depth(event.children, current_depth + 1)
            end
          end
        end
        find_max_depth(events_by_thread[thread_name], 0)
        
        local canvas = {}
        for i = 1, max_depth + 1 do
          canvas[i] = {}
          for j = 1, chart_width do
            canvas[i][j] = " "
          end
        end
        
        local function fill_chart_recursive(events, current_depth)
          for _, event in ipairs(events) do
            local event_start_rel = math.max(0, event.s - start_time)
            local event_end_rel = math.min(time_range_sec, event.e - start_time)
            if event_end_rel <= event_start_rel then goto continue end
            local start_idx = math.floor(event_start_rel / sec_per_char) + 1
            local end_idx = math.ceil(event_end_rel / sec_per_char)
            local is_wait = is_wait_event(event.name)
            local char_to_draw = is_wait and "░" or "█"
            local target_row_idx = current_depth + 1
            if canvas[target_row_idx] then
              for i = start_idx, end_idx do
                if i >= 1 and i <= chart_width then
                  canvas[target_row_idx][i] = char_to_draw
                end
              end
              local hl_group
              if is_wait then
                hl_group = wait_hl
              elseif #color_palette > 0 and event.name then
                local hash = string_hash(event.name)
                local color_index = (hash % #color_palette) + 1
                hl_group = color_palette[color_index]
              end
              if hl_group then
                table.insert(highlights_to_apply, {
                  line = #lines + target_row_idx,
                  start_col = thread_name_margin + 2 + start_idx - 1,
                  end_col = thread_name_margin + 2 + end_idx,
                  hl = hl_group,
                })
              end
            end
            if event.children and #event.children > 0 then
              fill_chart_recursive(event.children, current_depth + 1)
            end
            ::continue::
          end
        end
        fill_chart_recursive(events_by_thread[thread_name], 0)
        
        table.insert(lines, string.format("%-" .. thread_name_margin .. "s |", thread_name))
        for i = 1, max_depth + 1 do
          table.insert(lines, string.format("%-" .. thread_name_margin .. "s |%s|", "", table.concat(canvas[i])))
        end
        table.insert(lines, "")
      else -- "flat" mode
        local char_array = {}
        for i = 1, chart_width do
          char_array[i] = "─"
        end
        
        local function fill_chart_flat(events)
          for _, event in ipairs(events) do
            local event_start_rel = math.max(0, event.s - start_time)
            local event_end_rel = math.min(time_range_sec, event.e - start_time)
            if event_end_rel <= event_start_rel then goto continue end
            local start_idx = math.floor(event_start_rel / sec_per_char) + 1
            local end_idx = math.ceil(event_end_rel / sec_per_char)
            local is_wait = is_wait_event(event.name)
            local char_to_draw = is_wait and "░" or "█"
            for i = start_idx, end_idx do
              if i >= 1 and i <= chart_width then
                char_array[i] = char_to_draw
              end
            end
            local hl_group
            if is_wait then
              hl_group = wait_hl
            elseif #color_palette > 0 and event.name then
              local hash = string_hash(event.name)
              local color_index = (hash % #color_palette) + 1
              hl_group = color_palette[color_index]
            end
            if hl_group then
              table.insert(highlights_to_apply, {
                line = #lines,
                start_col = thread_name_margin + 2 + start_idx - 1,
                end_col = thread_name_margin + 2 + end_idx,
                hl = hl_group,
              })
            end
            if event.children and #event.children > 0 then
              fill_chart_flat(event.children)
            end
            ::continue::
          end
        end
        fill_chart_flat(events_by_thread[thread_name])
        
        table.insert(lines, string.format("%-" .. thread_name_margin .. "s |%s|", thread_name, table.concat(char_array)))
        table.insert(lines, "")
      end
    end

    vim.api.nvim_set_option_value("modifiable", true, { buf = s.buf })
    vim.api.nvim_buf_set_lines(s.buf, 0, -1, false, lines)
    
    local ns = vim.api.nvim_create_namespace("ULGGanttChart")
    vim.api.nvim_buf_clear_namespace(s.buf, ns, 0, -1)
    
    for _, h in ipairs(highlights_to_apply) do
      local line_content = lines[h.line + 1]
      if line_content and h.end_col <= #line_content then
        vim.api.nvim_buf_set_extmark(s.buf, ns, h.line, h.start_col, {
          end_col = h.end_col,
          hl_group = h.hl,
        })
      end
    end
    
    vim.api.nvim_set_option_value("modifiable", false, { buf = s.buf })
  end
end

function M.open(trace_handle, frame_data, opts)
  local s = window_state.get_state("gantt_chart")
  if s.win and vim.api.nvim_win_is_valid(s.win) then
    close_window()
  end

  local new_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[new_buf].buftype = "nofile"; vim.bo[new_buf].swapfile = false

  local width = math.floor(vim.o.columns * 0.9)
  local height = math.floor(vim.o.lines * 0.6)
  local row, col = math.floor((vim.o.lines - height) / 2), math.floor((vim.o.columns - width) / 2)
  local new_win = vim.api.nvim_open_win(new_buf, true, {
    relative = "editor", width = width, height = height, row = row, col = col,
    style = "minimal", border = "rounded", title = "ULG Gantt Chart (Frame " .. frame_data.frame_number .. ")",
  })

  window_state.update_state("gantt_chart", {
    win = new_win,
    buf = new_buf,
    trace_handle = trace_handle,
    frame_data = frame_data,
    display_opts = opts or { time_range_ms = 16.6 },
    is_showing_all = false,
    view_mode = "flat",
  })

  redraw_buffer()

  local map_opts = { noremap = true, silent = true }
  vim.api.nvim_buf_set_keymap(new_buf, "n", "q", "<cmd>lua require('ULG.window.gantt_chart').close()<cr>", map_opts)
  vim.api.nvim_buf_set_keymap(new_buf, "n", "a", "<cmd>lua require('ULG.window.gantt_chart').toggle_all_threads()<cr>", map_opts)
  vim.api.nvim_buf_set_keymap(new_buf, "n", "h", "<cmd>lua require('ULG.window.gantt_chart').toggle_view_mode()<cr>", map_opts)
end

M.close = close_window

function M.toggle_all_threads()
  local s = window_state.get_state("gantt_chart")
  if not (s.win and vim.api.nvim_win_is_valid(s.win)) then return end
  
  window_state.update_state("gantt_chart", { is_showing_all = not s.is_showing_all })
  
  if window_state.get_state("gantt_chart").is_showing_all then
    vim.notify("Loading all threads, this may take a moment...", vim.log.levels.INFO)
  end
  vim.schedule(redraw_buffer)
end

function M.toggle_view_mode()
    local s = window_state.get_state("gantt_chart")
    if not (s.win and vim.api.nvim_win_is_valid(s.win)) then return end

    local next_mode = s.view_mode == "hierarchical" and "flat" or "hierarchical"
    window_state.update_state("gantt_chart", { view_mode = next_mode })

    vim.notify("Gantt view mode: " .. next_mode, vim.log.levels.INFO)
    redraw_buffer()
end

return M
