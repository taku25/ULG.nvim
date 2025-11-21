-- lua/ULG/buf/log/trace.lua (ステートマネージャー対応版)

local trace_analyzer = require("ULG.analyzer.trace")
local unl_log_engine = require("UNL.backend.buf.log")
local unl_events = require("UNL.event.events")
local unl_event_types = require("UNL.event.types")
local view_state = require("ULG.context.view_state")

local M = {}
M.callbacks = {}

local function redraw_huds()
  local s = view_state.get_state("trace_log_view")
  if not (s.handle and s.handle:is_open()) then
    return
  end
  local win_id = s.handle:get_win_id()
  if not win_id then
    return
  end
  local buf_id = vim.api.nvim_win_get_buf(win_id)
  if not (buf_id and s.vtext_ns_id) then
    return
  end

  vim.api.nvim_buf_clear_namespace(buf_id, s.vtext_ns_id, 0, -1)

  local win_info = vim.fn.getwininfo(win_id)[1]
  local scroll_col = win_info and win_info.winscrolled or 0

  local scale_text = s.display_mode
  if s.display_mode == "avg" then
    scale_text = string.format("avg (0-%.1fms)", s.global_stats.avg * 3)
  end
  local cursor = vim.api.nvim_win_get_cursor(win_id)
  local cursor_row = cursor[1] - 1
  local cursor_col = cursor[2]
  local frame_index = cursor_col + 1
  local frame = s.frames_data[frame_index]

  if not frame then return end

  local frame_info = string.format("Frame %d: %.2fms", frame.frame_number, frame.duration_ms)
  local static_text = string.format("[Total: %d frames | Avg: %.2fms | Max: %.2fms | Scale: %s]",
  #s.frames_data, s.global_stats.avg, s.global_stats.max, scale_text)

  vim.api.nvim_buf_set_extmark(buf_id, s.vtext_ns_id, 0, scroll_col, {
    virt_text = {

      { frame_info, "Identifier" },
      { " ", "" },
      { static_text, "Comment" }
    },
    virt_text_pos = "overlay",
  })

  local marker = "▼"
  if cursor_row > 0 then marker = "●" end

  vim.api.nvim_buf_set_extmark(buf_id, s.vtext_ns_id, cursor_row, cursor_col, {
    virt_text = { { marker, "DiagnosticHint" } },
    virt_text_pos = "overlay",
  })
end

function M.close()
  local s = view_state.get_state("trace_log_view")
  if s.handle and s.handle:is_open() then
    s.handle:close()
  end
  if s.autocmd_group and vim.api.nvim_augroup_exists(s.autocmd_group) then
    vim.api.nvim_del_augroup_by_id(s.autocmd_group)
  end
  view_state.reset_state("trace_log_view")
  M.callbacks = {}
end

function M.open(trace_handle_arg)
  if view_state.get_state("trace_log_view").handle then
    local handle = view_state.get_state("trace_log_view").handle
    if handle and handle:is_open() then
      return
    end
  end

  -- 新しい状態をローカルで構築する
  local new_s = vim.deepcopy(require("ULG.context.view.trace_log_defaults"))
  new_s.trace_handle = trace_handle_arg
  new_s.frames_data = trace_analyzer.analyze_gamethread_frames(trace_handle_arg:get_thread_events("GameThread"))

  if #new_s.frames_data == 0 then
    vim.notify("No 'FEngineLoop::Tick' events found in GameThread trace.", vim.log.levels.WARN)
    return
  end

  local total_ms, max_ms = 0, 0
  for _, frame in ipairs(new_s.frames_data) do
    total_ms = total_ms + frame.duration_ms
    if frame.duration_ms > max_ms then max_ms = frame.duration_ms end
  end
  new_s.global_stats.avg = total_ms / #new_s.frames_data
  new_s.global_stats.max = max_ms
  for i, frame in ipairs(new_s.frames_data) do
    if frame.duration_ms > new_s.global_stats.avg then
      table.insert(new_s.spike_indices, i)
    end
  end

  local function generate_and_apply_sparkline(buf, state_to_use)
    local conf = require("UNL.config").get("ULG")
    local spark_chars = conf.spark_chars or { " ", "▂", "▃", "▄", "▅", "▆", "▇" }
    local max_val = state_to_use.global_stats.max
    if state_to_use.display_mode == "33ms" then max_val = 33.3
    elseif state_to_use.display_mode == "16ms" then max_val = 16.6
    elseif state_to_use.display_mode == "avg" then max_val = state_to_use.global_stats.avg * 3
    end

    local line_parts = {}
    local char_info_list = {}
    local hl_groups = conf.highlights and conf.highlights.trace_sparkline and conf.highlights.trace_sparkline.groups or {}

    if max_val > 0 then
      for _, frame in ipairs(state_to_use.frames_data) do
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
    local anchor_line = string.rep(" ", #state_to_use.frames_data)

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

  local function find_next_spike(spike_indices, start_index)
    if #spike_indices == 0 then return nil end
    local low, high, result = 1, #spike_indices, nil
    while low <= high do
      local mid = math.floor((low + high) / 2)
      if spike_indices[mid] >= start_index then
        result = spike_indices[mid]
        high = mid - 1
      else
        low = mid + 1
      end
    end
    return result
  end

  local function find_prev_spike(spike_indices, start_index)
    if #spike_indices == 0 then return nil end
    local low, high, result = 1, #spike_indices, nil
    while low <= high do
      local mid = math.floor((low + high) / 2)
      if spike_indices[mid] <= start_index then
        result = spike_indices[mid]
        low = mid + 1
      else
        high = mid - 1
      end
    end
    return result
  end

  M.callbacks.show_help = function() require("ULG.window.help.trace").toggle() end

  M.callbacks.next_spike = function()
    local s = view_state.get_state("trace_log_view")
    local win = s.handle:get_win_id()
    if not win then return end
    local current_index = vim.api.nvim_win_get_cursor(win)[2] + 1
    local next_spike_index = find_next_spike(s.spike_indices, current_index + 1)
    if next_spike_index then
      vim.api.nvim_win_set_cursor(win, { 1, next_spike_index - 1 })
    end
  end

  M.callbacks.prev_spike = function()
    local s = view_state.get_state("trace_log_view")
    local win = s.handle:get_win_id()
    if not win then return end
    local current_index = vim.api.nvim_win_get_cursor(win)[2] + 1
    local prev_spike_index = find_prev_spike(s.spike_indices, current_index - 1)
    if prev_spike_index then
      vim.api.nvim_win_set_cursor(win, { 1, prev_spike_index - 1 })
    end
  end

  M.callbacks.first_spike = function()
    local s = view_state.get_state("trace_log_view")
    if #s.spike_indices > 0 then
      local win = s.handle:get_win_id()
      if win then vim.api.nvim_win_set_cursor(win, { 1, s.spike_indices[1] - 1 }) end
    end
  end

  M.callbacks.last_spike = function()
    local s = view_state.get_state("trace_log_view")
    if #s.spike_indices > 0 then
      local win = s.handle:get_win_id()
      if win then vim.api.nvim_win_set_cursor(win, { 1, s.spike_indices[#s.spike_indices] - 1 }) end
    end
  end

  M.callbacks.show_callees = function()
    local s = view_state.get_state("trace_log_view")
    local win = s.handle:get_win_id()
    if not win then return end
    local frame_index = vim.api.nvim_win_get_cursor(win)[2] + 1
    if s.frames_data[frame_index] then
      require("ULG.window.callees").open(s.frames_data[frame_index])
    end
  end

M.callbacks.show_callees_tree  = function()
    local s = view_state.get_state("trace_log_view")
    local win = s.handle:get_win_id()
    if not win then return end
    local frame_index = vim.api.nvim_win_get_cursor(win)[2] + 1
    local frame = s.frames_data[frame_index]
    
    if frame and s.trace_handle then
        local payload = {
          trace_handle = s.trace_handle,
          frame_data = frame,
        }
        
        local log = require("ULG.logger").get()
        local unl_api_ok, unl_api = pcall(require, "UNL.api")
        
        -- ★★★ 修正箇所: UNL APIの戻り値を受け取るように修正 ★★★
        if unl_api_ok then
            
            local has_unx_provider = false
            local is_unx_open = false

            -- 1. UNXプロバイダーの状態をチェック (ok, result で受け取る)
            local ok, is_open_res = unl_api.provider.request("unx.is_open", { name = "ULG.nvim" })
            
            -- ok が true で、かつ結果が nil でない (プロバイダーが存在する) 場合
            if ok and is_open_res ~= nil then
                has_unx_provider = true
                is_unx_open = is_open_res
            end

            -- 2. UNXが存在し、開いていなければ、open を要求
            if has_unx_provider and not is_unx_open then
                log.info("UNX provider detected and closed. Requesting UNX open.")
                -- open も ok, result で受け取るべきだが、ここでは戻り値は無視して実行
                unl_api.provider.request("unx.open", { name = "ULG.nvim" })
            end
            
            -- 3. 1フレーム後にイベント発行とフォールバックロジックを実行
            vim.schedule(function()
                
                -- イベントを発行し、ペイロードをUNXに送信
                require("UNL.event.events").publish(require("UNL.event.types").ON_REQUEST_TRACE_CALLEES_VIEW, payload)

                -- UNXプロバイダーが存在しない場合 (has_unx_provider が false の場合) はneo-treeにフォールバック
                if not has_unx_provider then
                    log.warn("UNL API available, but UNX provider not found. Falling back to neo-tree.")
                    local ok, neo_tree_cmd = pcall(require, "neo-tree.command")
                    if ok then
                      neo_tree_cmd.execute({ source = "insights", action = "focus" })
                    else
                      log.warn("neo-tree command not found.")
                    end
                end
            end)

        else
            -- UNL API自体がロードできなかった場合 (UNXセットアップ失敗など)
            log.warn("UNL API not available. Falling back to direct neo-tree focus.")
            
            require("UNL.event.events").publish(require("UNL.event.types").ON_REQUEST_TRACE_CALLEES_VIEW, payload)

            local ok, neo_tree_cmd = pcall(require, "neo-tree.command")
            if ok then
                neo_tree_cmd.execute({ source = "insights", action = "focus" })
            else
                log.warn("neo-tree command not found.")
            end
        end
        -- ★★★ 修正箇所ここまで ★★★
    end
  end

  M.callbacks.show_gantt_chart = function()
    local s = view_state.get_state("trace_log_view")
    local win = s.handle:get_win_id()
    if not win then return end
    local frame_index = vim.api.nvim_win_get_cursor(win)[2] + 1
    local frame = s.frames_data[frame_index]
    if frame then
      require("ULG.window.gantt_chart").open(s.trace_handle, frame, { time_range_ms = 16.6 })
    end
  end

  M.callbacks.toggle_scale_mode = function()
    local s = view_state.get_state("trace_log_view")
    local modes = { "33ms", "16ms", "avg", "auto" }
    local current_index = vim.tbl_find(modes, s.display_mode) or #modes
    local next_mode = modes[(current_index % #modes) + 1]
    
    view_state.update_state("trace_log_view", { display_mode = next_mode })
    
    local updated_s = view_state.get_state("trace_log_view")
    local win = updated_s.handle:get_win_id()
    if win then
      generate_and_apply_sparkline(vim.api.nvim_win_get_buf(win), updated_s)
      redraw_huds()
    end
    vim.notify("Sparkline scale set to: " .. next_mode)
  end

  local conf = require("UNL.config").get("ULG")
  local trace_keymaps = conf.keymaps.trace or {}
  local final_keymaps = { q = "<cmd>lua require('ULG.buf.log.trace').close()<cr>" }
  for action, key in pairs(trace_keymaps) do
    if key and key ~= "" and M.callbacks[action] then
      final_keymaps[key] = string.format("<cmd>lua require('ULG.buf.log.trace').callbacks.%s()<cr>", action)
    end
  end

  local spec = { id = "ulg_trace", title = "[[ ULG Trace ]]", filetype = "ulg-trace", auto_scroll = false, keymaps = final_keymaps }
  new_s.handle = unl_log_engine.create(spec)

  unl_log_engine.batch_open({ new_s.handle }, conf.trace_position .. " new", function()
    if not (new_s.handle and new_s.handle:is_open()) then return end
    
    local win_id = new_s.handle:get_win_id()
    local buf_id = vim.api.nvim_win_get_buf(win_id)
    vim.api.nvim_win_set_height(win_id, 2)
    local win_opts = { win = win_id }
    vim.api.nvim_set_option_value("wrap", false, win_opts)
    vim.api.nvim_set_option_value("cursorline", true, win_opts)
    
    new_s.vtext_ns_id = vim.api.nvim_create_namespace("ULGTraceSummaryHUD")
    new_s.autocmd_group = vim.api.nvim_create_augroup("ULGTraceSummaryEvents", { clear = true })
    
    view_state.update_state("trace_log_view", new_s)

    generate_and_apply_sparkline(buf_id, new_s)
    redraw_huds()
    vim.api.nvim_create_autocmd({ "CursorMoved", "WinScrolled" }, {
      group = new_s.autocmd_group,
      buffer = buf_id,
      callback = redraw_huds,
    })
    vim.api.nvim_win_set_cursor(win_id, { 1, 0 })
  end)
end

return M
