-- lua/ULG/buf/log/trace_summary.lua (スパークラインハイライト・整形・最終完成形)

local trace_analyzer = require("ULG.analyzer.trace")
local trace_tree_viewer = require("ULG.window.callees")
local unl_log_engine = require("UNL.backend.buf.log")

local M = {}
M.callbacks = {}

local state = {
  handle = nil,
  frames_data = nil,
  display_mode = "33ms",
  global_stats = { avg = 0, max = 0 },
  spike_indices = {},
  autocmd_group = nil,
  vtext_ns_id = nil,
}

-- local spark_chars = { " ", "▂", "▃", "▄", "▅", "▆", "▇" }

local function redraw_huds()
  if not (state.handle and state.handle:is_open()) then
    return
  end
  local win_id = state.handle:get_win_id()
  if not win_id then
    return
  end
  local buf_id = vim.api.nvim_win_get_buf(win_id)
  if not (buf_id and state.vtext_ns_id) then
    return
  end

  vim.api.nvim_buf_clear_namespace(buf_id, state.vtext_ns_id, 0, -1)

  local win_info = vim.fn.getwininfo(win_id)[1]
  local scroll_col = win_info and win_info.winscrolled or 0

  local scale_text = state.display_mode
  if state.display_mode == "avg" then
    scale_text = string.format("avg (0-%.1fms)", state.global_stats.avg * 3)
  end
  local cursor = vim.api.nvim_win_get_cursor(win_id)
  local cursor_row = cursor[1] - 1
  local cursor_col = cursor[2]
  local frame_index = cursor_col + 1
  local frame = state.frames_data[frame_index]


  local frame_info = string.format("Frame %d: %.2fms", frame.frame_number, frame.duration_ms)
  local static_text = string.format("[Total: %d frames | Avg: %.2fms | Max: %.2fms | Scale: %s]",
  #state.frames_data, state.global_stats.avg, state.global_stats.max, scale_text)

  vim.api.nvim_buf_set_extmark(buf_id, state.vtext_ns_id, 0, scroll_col, {
    virt_text = {

      { frame_info, "Identifier" },
      { " ", "" },
      { static_text, "Comment" }
    },
    virt_text_pos = "overlay",
  })

  local marker
  if cursor_row == 0 then
    marker = "▼"
  else
    marker = "●"
  end

  if frame then
    local cursor = vim.api.nvim_win_get_cursor(win_id)
    local cursor_row = cursor[1] - 1
    local cursor_col = cursor[2]

    vim.api.nvim_buf_set_extmark(buf_id, state.vtext_ns_id, cursor_row, cursor_col, {
      virt_text = { { marker, "DiagnosticHint" } },
      virt_text_pos = "overlay",
    })
  end
end

function M.close()
  if state.handle and state.handle:is_open() then
    state.handle:close()
  end
  if state.autocmd_group and vim.api.nvim_augroup_exists(state.autocmd_group) then
    vim.api.nvim_del_augroup_by_id(state.autocmd_group)
  end
  state.handle = nil
  state.frames_data = nil
  state.spike_indices = {}
  state.display_mode = "33ms"
  state.autocmd_group = nil
  state.vtext_ns_id = nil
  M.callbacks = {}
end

function M.open(trace_handle)
  if state.handle and state.handle:is_open() then
    return
  end
  state.frames_data = trace_analyzer.analyze_gamethread_frames(trace_handle:get_thread_events("GameThread"))
  if #state.frames_data == 0 then
    vim.notify("No 'FEngineLoop::Tick' events found in GameThread trace.", vim.log.levels.WARN)
    return
  end

  state.spike_indices = {}
  local total_ms = 0
  local max_ms = 0
  for _, frame in ipairs(state.frames_data) do
    total_ms = total_ms + frame.duration_ms
    if frame.duration_ms > max_ms then
      max_ms = frame.duration_ms
    end
  end
  state.global_stats.avg = total_ms / #state.frames_data
  state.global_stats.max = max_ms
  for i, frame in ipairs(state.frames_data) do
    if frame.duration_ms > state.global_stats.avg then
      table.insert(state.spike_indices, i)
    end
  end


  local function generate_and_apply_sparkline(buf)
    local conf = require("UNL.config").get("ULG")
    local spark_chars = conf.spark_chars or { " ", "▂", "▃", "▄", "▅", "▆", "▇" }
    local max_val = state.global_stats.max
    if state.display_mode == "33ms" then max_val = 33.3
    elseif state.display_mode == "16ms" then max_val = 16.6
    elseif state.display_mode == "avg" then max_val = state.global_stats.avg * 3
    end

    local line_parts = {}
    -- 文字列とハイライト情報を一緒に生成する
    local char_info_list = {}
    local hl_groups = conf.highlights and conf.highlights.trace_sparkline and conf.highlights.trace_sparkline.groups or {}

    if max_val > 0 then
      for _, frame in ipairs(state.frames_data) do
        local norm = math.min(1.0, frame.duration_ms / max_val)
        local index = math.floor(norm * (#spark_chars - 1)) + 1
        local char = spark_chars[index]
        table.insert(line_parts, char)
        if #hl_groups > 0 then
          table.insert(char_info_list, { char = char, hl = hl_groups[index] })
        end
      end
    end
    local sparkline = table.concat(line_parts)
    -- アンカー行は文字数で生成
    local anchor_line = string.rep(" ", #state.frames_data)

    vim.api.nvim_set_option_value("modifiable", true, { buf = buf })
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { anchor_line, sparkline })

    if #char_info_list > 0 then
      local spark_ns = vim.api.nvim_create_namespace("ULGTraceSparkline")
      vim.api.nvim_buf_clear_namespace(buf, spark_ns, 0, -1)

      local current_byte_col = 0
      for _, info in ipairs(char_info_list) do
        local char_byte_len = #info.char
        if info.hl then
          vim.api.nvim_buf_set_extmark(buf, spark_ns, 1, current_byte_col, {
            end_col = current_byte_col + char_byte_len,
            hl_group = info.hl,
          })
        end
        current_byte_col = current_byte_col + char_byte_len
      end
    end

    vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
  end

  local conf = require("UNL.config").get("ULG")
  local trace_keymaps = conf.keymaps.trace or {}
  local final_keymaps = {
    q = "<cmd>lua require('ULG.buf.log.trace_summary').close()<cr>",
  }

  local function find_next_spike(start_index)
    if #state.spike_indices == 0 then return nil end
    local low, high, result = 1, #state.spike_indices, nil
    while low <= high do
      local mid = math.floor((low + high) / 2)
      if state.spike_indices[mid] >= start_index then
        result = state.spike_indices[mid]
        high = mid - 1
      else
        low = mid + 1
      end
    end
    return result
  end

  local function find_prev_spike(start_index)
    if #state.spike_indices == 0 then return nil end
    local low, high, result = 1, #state.spike_indices, nil
    while low <= high do
      local mid = math.floor((low + high) / 2)
      if state.spike_indices[mid] <= start_index then
        result = state.spike_indices[mid]
        low = mid + 1
      else
        high = mid - 1
      end
    end
    return result
  end

  M.callbacks.next_spike = function()
    local win = state.handle:get_win_id()
    if not win then return end
    local current_index = vim.api.nvim_win_get_cursor(win)[2] + 1
    local next_spike_index = find_next_spike(current_index + 1)
    if next_spike_index then
      vim.api.nvim_win_set_cursor(win, { 1, next_spike_index - 1 })
    end
  end

  M.callbacks.prev_spike = function()
    local win = state.handle:get_win_id()
    if not win then return end
    local current_index = vim.api.nvim_win_get_cursor(win)[2] + 1
    local prev_spike_index = find_prev_spike(current_index - 1)
    if prev_spike_index then
      vim.api.nvim_win_set_cursor(win, { 1, prev_spike_index - 1 })
    end
  end

  M.callbacks.first_spike = function()
    if #state.spike_indices > 0 then
      local win = state.handle:get_win_id()
      if win then
        vim.api.nvim_win_set_cursor(win, { 1, state.spike_indices[1] - 1 })
      end
    end
  end

  M.callbacks.last_spike = function()
    if #state.spike_indices > 0 then
      local win = state.handle:get_win_id()
      if win then
        vim.api.nvim_win_set_cursor(win, { 1, state.spike_indices[#state.spike_indices] - 1 })
      end
    end
  end

  M.callbacks.show_details = function()
    local win = state.handle:get_win_id()
    if not win then return end
    local frame_index = vim.api.nvim_win_get_cursor(win)[2] + 1
    if state.frames_data[frame_index] then
      trace_tree_viewer.open(state.frames_data[frame_index])
    end
  end

  M.callbacks.toggle_scale_mode = function()
    local modes = { "33ms", "16ms", "avg", "auto" }
    local current_index = 0
    for i, mode in ipairs(modes) do
      if mode == state.display_mode then
        current_index = i
        break
      end
    end
    if current_index == 0 then
      current_index = #modes
    end
    local next_index = (current_index % #modes) + 1
    state.display_mode = modes[next_index]
    local win = state.handle:get_win_id()
    if win then
      local buf = vim.api.nvim_win_get_buf(win)
      generate_and_apply_sparkline(buf)
      redraw_huds()
    end
    vim.notify("Sparkline scale set to: " .. state.display_mode)
  end

  for action, key in pairs(trace_keymaps) do
    if key and key ~= "" and M.callbacks[action] then
      final_keymaps[key] = string.format("<cmd>lua require('ULG.buf.log.trace_summary').callbacks.%s()<cr>", action)
    end
  end

  local spec = {
    id = "ulg_trace_summary",
    title = "[[ ULG Trace Summary ]]",
    filetype = "ulg-trace-summary",
    auto_scroll = false,
    keymaps = final_keymaps
  }
  state.handle = unl_log_engine.create(spec)

  unl_log_engine.batch_open({ state.handle }, "botright new", function()
    if not (state.handle and state.handle:is_open()) then
      return
    end
    local win_id = state.handle:get_win_id()
    local buf_id = vim.api.nvim_win_get_buf(win_id)
    vim.api.nvim_win_set_height(win_id, 2)
    local win_opts = { win = win_id }
    vim.api.nvim_set_option_value("wrap", false, win_opts)
    vim.api.nvim_set_option_value("cursorline", true, win_opts)

    state.vtext_ns_id = vim.api.nvim_create_namespace("ULGTraceSummaryHUD")

    generate_and_apply_sparkline(buf_id)
    redraw_huds()

    state.autocmd_group = vim.api.nvim_create_augroup("ULGTraceSummaryEvents", { clear = true })
    vim.api.nvim_create_autocmd({ "CursorMoved", "WinScrolled" }, {
      group = state.autocmd_group,
      buffer = buf_id,
      callback = redraw_huds,
    })

    vim.api.nvim_win_set_cursor(win_id, { 1, 0 })
  end)
end

return M
