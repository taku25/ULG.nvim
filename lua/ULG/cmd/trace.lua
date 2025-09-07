-- lua/ULG/cmd/trace.lua (エラー修正・UNL API準拠版)

local unl_api = require("UNL.api")
local unl_finder = require("UNL.finder")
local unl_picker = require("UNL.backend.picker")
local path = require("UNL.path")
local log = require("ULG.logger")
local general_log_view = require("ULG.buf.log.general")
local trace_cache = require("ULG.cache.trace")
local unl_progress = require("UNL.backend.progress")
local unl_cache_core = require("UNL.cache.core")

local M = {}

--------------------------------------------------------------------------------
-- Helper Functions (Private)
--------------------------------------------------------------------------------
-- (find_utrace_files, parse_timer_line ヘルパーは変更なし)
local function parse_timer_line(line)
  if not line or line == "" then return nil end
  local id, type, name, file, line_num
  local current_pos = 1
  local next_comma = line:find(",", current_pos)
  if not next_comma then return nil end
  id = line:sub(current_pos, next_comma - 1)
  current_pos = next_comma + 1
  next_comma = line:find(",", current_pos)
  if not next_comma then return nil end
  type = line:sub(current_pos, next_comma - 1)
  current_pos = next_comma + 1
  if line:sub(current_pos, current_pos) == '"' then
    current_pos = current_pos + 1
    local end_quote = line:find('",', current_pos)
    if not end_quote then return nil end
    name = line:sub(current_pos, end_quote - 1)
    current_pos = end_quote + 2
  else
    next_comma = line:find(",", current_pos)
    if not next_comma then return nil end
    name = line:sub(current_pos, next_comma - 1)
    current_pos = next_comma + 1
  end
  if current_pos > #line then
    file, line_num = "", ""
  else
    local rest_of_line = line:sub(current_pos)
    local last_comma_pos = rest_of_line:match("^.*,")
    if last_comma_pos then
      local split_pos = #last_comma_pos
      file = rest_of_line:sub(1, split_pos - 1)
      line_num = rest_of_line:sub(split_pos + 1)
    else
      file, line_num = rest_of_line, ""
    end
  end
  return id, type, name, file, line_num
end

local function find_utrace_files(search_dirs)
  if not search_dirs or #search_dirs == 0 then return {} end
  if vim.fn.executable("fd") == 1 then
    local cmd = { "fd", "--type", "f", "--extension", "utrace", "--absolute-path" }
    vim.list_extend(cmd, search_dirs)
    local output = vim.fn.system(cmd)
    if vim.v.shell_error == 0 and output and output:match("%S") then
      return vim.split(output, "\n", { plain = true, trimempty = true })
    end
  end
  local files = {}
  local visited = {}
  local function find_recursive(current_dir)
    if visited[current_dir] then return end; visited[current_dir] = true
    local iter = vim.fs.dir(current_dir, { on_error = function() end })
    if not iter then return end
    for file, type in iter do
      local full_path = path.join(current_dir, file)
      if type == "file" and file:match("%.utrace$") then
        table.insert(files, full_path)
      elseif type == "directory" then
        find_recursive(full_path)
      end
    end
  end
  for _, dir in ipairs(search_dirs) do find_recursive(dir) end
  return files
end

---
-- CSVファイルをメモリにロードする (TimingEvents.csv以外)
local function load_small_csvs(export_dir)
    local timer_csv_path = path.join(export_dir, "Timers.csv")
    local thread_csv_path = path.join(export_dir, "Threads.csv")

    -- ★★★ ここが前回のエラーの修正点です ★★★
    -- 存在しない unl_cache_core.load_text_file の代わりに vim.fn.readfile を使用します。
    local timer_lines = vim.fn.filereadable(timer_csv_path) == 1 and vim.fn.readfile(timer_csv_path) or nil
    local thread_lines = vim.fn.filereadable(thread_csv_path) == 1 and vim.fn.readfile(thread_csv_path) or nil
    
    local timer_info, thread_info = {}, {}
    -- Timers.csv をパース
    if timer_lines then
        for _, line in ipairs(timer_lines) do
            if line ~= "Id,Type,Name,File,Line" and line ~= "" then
                local id, type, name, file, line_num = parse_timer_line(line)
                if id then timer_info[id] = { name = name, file = file, line = line_num } end
            end
        end
    end
    -- Threads.csv をパース
    if thread_lines then
        for _, line in ipairs(thread_lines) do
            if line ~= "Id,Name,Group" and line ~= "" then
                local id, name, group = line:match('^([^,]+),([^,]+),?(.*)$')
                if id and name then thread_info[id] = { name = name, group = group } end
            end
        end
    end
    return timer_info, thread_info
end


---
-- TimingEvents.csvをストリーム処理して階層化データを構築・保存する
-- @param utrace_filepath string 元となった.utraceファイルのパス
-- @param loaded_maps table {timers, threads} 事前にパースしたIDと情報のマップ
-- @param progress_handle table プログレスバーのハンドル
---
-- TimingEvents.csvをストリーム処理して階層化データを構築・チャンク保存する
local function process_stream_data_async(utrace_filepath, loaded_maps, progress_handle, on_complete_callback)
  local trace_dir = trace_cache.get_trace_cache_dir(utrace_filepath)
  local events_csv_path = path.join(trace_dir, "TimingEvents.csv")

  -- ★★★ 修正点1: ファイルサイズを事前に取得 ★★★
  local total_size = 0
  local stat = vim.loop.fs_stat(events_csv_path)
  if stat then
    total_size = stat.size
  end

  local function is_finite(n)
    return n == n and n ~= 1/0 and n ~= -1/0
  end

  local worker = coroutine.create(function()
    local thread_states = {}
    local CHUNK_SIZE_LIMIT_BYTES = 15 * 1024 * 1024

    local function write_chunk_to_disk(state, thread_id)
        if #state.current_chunk_events == 0 then return end
        local chunk_filename = string.format("chunk_thread_%d_%d.json", thread_id, state.chunk_index)
        local chunk_path = path.join(trace_dir, chunk_filename)
        unl_cache_core.save_json(chunk_path, state.current_chunk_events)
        table.insert(state.chunk_file_list, chunk_filename)
        state.chunk_index = state.chunk_index + 1
        state.current_chunk_events = {}
        state.current_chunk_size_bytes = 0
    end

    local line_count = 0
    progress_handle:stage_define("processing", 1)
    progress_handle:stage_update("processing", 0, "Processing events...")

    -- ★★★ 修正点2: io.linesではなく、ファイルハンドルを使ってループする ★★★
    local file = io.open(events_csv_path, "r")
    if not file then
        log.get().error("Could not open TimingEvents.csv for processing: %s", events_csv_path)
        progress_handle:finish(false)
        return
    end

    for line in file:lines() do
      line_count = line_count + 1
      local thread_id_str, timer_id_str, start_time_str, end_time_str, depth_str = line:match('^([^,]+),([^,]+),([^,]+),([^,]+),([^,]+)$')

      if timer_id_str and timer_id_str ~= "TimerId" then
        local start_time = tonumber(start_time_str)
        local end_time = tonumber(end_time_str)
        if not is_finite(start_time) then start_time = 0.0 end
        if not is_finite(end_time) then end_time = start_time end

        -- ★★★ ここからが修正箇所です ★★★
        local duration = end_time - start_time
        -- 非常に小さい値や0を対数に入れると-infになるのを防ぐため、微小な値を加える
        local log_duration = math.log(math.max(1e-9, duration))

        local event = {
          tid = tonumber(timer_id_str),
          s = start_time,
          e = end_time,
          ldur = log_duration, -- 対数持続時間をキャッシュに含める
          children = {}
        }
        -- ★★★ 修正箇所ここまで ★★★
        local thread_id = tonumber(thread_id_str)
        local depth = tonumber(depth_str)

        if not thread_states[thread_id] then
          thread_states[thread_id] = {
            event_stack = {}, current_chunk_events = {}, current_chunk_size_bytes = 0,
            chunk_index = 0, chunk_file_list = {},
          }
        end
        local state = thread_states[thread_id]

        while #state.event_stack > depth do
          table.remove(state.event_stack)
        end

        if #state.event_stack > 0 then
          table.insert(state.event_stack[#state.event_stack].children, event)
        else
          if state.current_chunk_size_bytes > CHUNK_SIZE_LIMIT_BYTES then
            write_chunk_to_disk(state, thread_id)
          end
          table.insert(state.current_chunk_events, event)
          local ok, encoded = pcall(vim.json.encode, event)
          if ok then
            state.current_chunk_size_bytes = state.current_chunk_size_bytes + #encoded
          end
        end
        table.insert(state.event_stack, event)
      end

      -- ★★★ 修正点3: 固定値ではなく、計算した進捗率を渡す ★★★
      if line_count % 5000 == 0 then -- 更新頻度を少し調整
        local progress = 0.0
        if total_size > 0 then
          -- file:seek("cur") で現在のバイト位置を取得
          progress = file:seek("cur") / total_size
        end
        progress_handle:stage_update("processing", progress, string.format("Processing... (%d%%)", math.floor(progress * 100)))
        coroutine.yield()
      end
    end
    
    file:close() -- ★★★ 修正点4: ファイルハンドルを閉じる ★★★

    progress_handle:stage_update("processing", 1, "Finished processing events.")

    for thread_id, state in pairs(thread_states) do
      write_chunk_to_disk(state, thread_id)
    end

    progress_handle:stage_define("saving", 1)
    progress_handle:stage_update("saving", 0, "Saving metadata...")
    local trace_data_metadata = {}
    for thread_id, state in pairs(thread_states) do
      if #state.chunk_file_list > 0 then
        trace_data_metadata[tostring(thread_id)] = { chunks = state.chunk_file_list }
      end
    end
    local final_metadata = {
      timers = loaded_maps.timers,
      threads = loaded_maps.threads,
      trace_data = trace_data_metadata,
    }
    -- ★★★ メタデータ保存後の処理 ★★★
    trace_cache.save_metadata(utrace_filepath, final_metadata)
    progress_handle:stage_update("saving", 1, "Metadata saved.")
    log.get().info("Successfully saved trace cache for %s", utrace_filepath)
    vim.notify("Trace analysis complete and cached successfully!")

    -- ★★★ 完了コールバックを呼び出す ★★★
    if on_complete_callback then
      on_complete_callback(true)
    end
  end)

  local function resume_worker()
    if coroutine.status(worker) == "suspended" then
      local ok, err = coroutine.resume(worker)
      if not ok then
        if progress_handle then progress_handle:finish(false) end
        log.get().error("Coroutine worker failed: %s", tostring(err))
        return
      end
      if coroutine.status(worker) == "suspended" then
        vim.defer_fn(resume_worker, 1)
      else
        if progress_handle then progress_handle:finish(true) end
      end
    end
  end
  coroutine.resume(worker)
  if coroutine.status(worker) == "suspended" then vim.defer_fn(resume_worker, 1) end
end
--- UnrealInsights.exe を非同期で実行してCSV群を生成する
local function run_insights(utrace_filepath, on_complete)
  local export_dir = trace_cache.get_trace_cache_dir(utrace_filepath)
  if not export_dir then
    on_complete(false)
    return
  end
  vim.fn.mkdir(export_dir, "p")
  local timers_csv_path = path.join(export_dir, "Timers.csv")
  local events_csv_path = path.join(export_dir, "TimingEvents.csv")
  local threads_csv_path = path.join(export_dir, "Threads.csv")
  local quoted_timers_path = string.format('%q', timers_csv_path)
  local quoted_events_path = string.format('%q', events_csv_path)
  local quoted_threads_path = string.format('%q', threads_csv_path)
  local rsp_path = path.join(export_dir, "export.rsp")
  local rsp_content = {
    "TimingInsights.ExportTimers " .. quoted_timers_path,
    "TimingInsights.ExportTimingEvents " .. quoted_events_path,
    "TimingInsights.ExportThreads " .. quoted_threads_path,
  }
  vim.fn.writefile(rsp_content, rsp_path)
  local insights_log_path = path.join(export_dir, "UnrealInsights.log")
  local conf = require("UNL.config").get("ULG")
  local progress_handle, provider_name =unl_progress.create_for_refresh(conf, {
    title = "ULG Trace Analysis", client_name = "ULG",
    weights = { insights = 0.20, load_csv = 0.15, processing = 0.45, saving = 0.20, },
  })
  progress_handle:stage_define("insights", 1)
  progress_handle:stage_define("load_csv", 1)

  if general_log_view.is_open and general_log_view.is_open() then
    general_log_view.clear_buffer()
    general_log_view.set_title("[[ Unreal Insights LOG ]]")
    general_log_view.start_tailing(insights_log_path)
  else
    log.get().info("General log window is not open. Insights progress will be written to: %s", insights_log_path)
  end
  local project_root = unl_finder.project.find_project_root(vim.loop.cwd())
  local insights_exe, err = unl_api.find_insights(project_root)
  if not insights_exe then
    progress_handle:stop(false)
    on_complete(false)
    return log.get().error("Could not find UnrealInsights.exe. Error: %s", tostring(err))
  end
  local final_command
  if vim.loop.os_uname().sysname == "Windows_NT" then
    local inner_command = string.format(
      '"%s" -OpenTraceFile="%s" -ABSLOG="%s" -NoUI -AutoQuit -ExecOnAnalysisCompleteCmd="@=%s"',
      insights_exe, utrace_filepath, insights_log_path, rsp_path
    )
    final_command = "cmd.exe /c " .. inner_command
  else
    final_command = {
        insights_exe, "-OpenTraceFile=" .. utrace_filepath, "-ABSLOG=" .. insights_log_path,
        "-NoUI", "-AutoQuit", "-ExecOnAnalysisCompleteCmd=@=" .. rsp_path
    }
  end
  log.get().info("Executing UnrealInsights with final command: %s", vim.inspect(final_command))
  vim.notify("Starting full trace export for: " .. vim.fn.fnamemodify(utrace_filepath, ":t"))
  progress_handle:stage_update("insights", 0, "Running UnrealInsights.exe...")

  vim.fn.jobstart(final_command, {
    on_exit = function(_, exit_code)
      vim.schedule(function()
        if general_log_view.is_open and general_log_view.is_open() then general_log_view.set_title("[[ General Log ]]") end
        if exit_code == 0 then
          progress_handle:stage_update("insights", 1, "UnrealInsights finished.")
          progress_handle:stage_update("load_csv", 0, "Loading Timers/Threads CSV...")
          local timer_info, thread_info = load_small_csvs(export_dir)
          progress_handle:stage_update("load_csv", 1, "CSV files loaded.")
          
          -- ★★★ process_stream_data_async に on_complete をそのまま渡す ★★★
          process_stream_data_async(
            utrace_filepath,
            { timers = timer_info, threads = thread_info },
            progress_handle,
            on_complete
          )
        else
          log.get().error("UnrealInsights failed with exit code: %s", exit_code)
          progress_handle:finish(false)
          -- ★★★ 失敗した場合もコールバックを呼ぶ ★★★
          on_complete(false)
        end
      end)
    end,
  })
end

local function process_selected_utrace(utrace_filepath)
  if not utrace_filepath then return end

  -- ★★★ ご提案の美しいロジック ★★★
  local trace_handle = trace_cache.load(utrace_filepath)
  if trace_handle then
    log.get().info("Found valid trace cache for %s, opening summary.", utrace_filepath)
    require("ULG.buf.log.trace").open(trace_handle)
  else
    log.get().info("No cache found for %s. Starting new analysis.", utrace_filepath)
    run_insights(utrace_filepath, function(is_success)
      if is_success then
        -- キャッシュ作成が成功したので、再度loadしてUIを開く
        local new_trace_handle = trace_cache.load(utrace_filepath)
        if new_trace_handle then
          require("ULG.buf.log.trace").open(new_trace_handle)
        else
          log.get().error("Cache was created but failed to load. Please check logs.")
        end
      else
        log.get().error("Trace analysis failed. Summary window will not be opened.")
      end
    end)
  end
end


--------------------------------------------------------------------------------
-- Command Logic (:ULG trace)
--------------------------------------------------------------------------------


-- (open_trace_picker と M.execute は変更なし)
local function open_trace_picker()
  local project_root = unl_finder.project.find_project_root(vim.loop.cwd())
  if not project_root then return log.get().error("Not in an Unreal Engine project.") end
  local conf = require("UNL.config").get("ULG")
  local search_dirs = {}
  local appdata_store = path.join(vim.loop.os_homedir(), "AppData", "Local", "UnrealEngine", "Common", "UnrealTrace", "Store")
  table.insert(search_dirs, appdata_store)
  local project_profiling_dir = path.join(project_root, "Saved", "Profiling")
  table.insert(search_dirs, project_profiling_dir)
  if conf.profiling and type(conf.profiling.additional_search_dirs) == "table" then
    vim.list_extend(search_dirs, conf.profiling.additional_search_dirs)
  end
  log.get().debug("Searching for .utrace files in: %s", table.concat(search_dirs, ", "))
  local utrace_files = find_utrace_files(search_dirs)
  if #utrace_files == 0 then
    return log.get().warn("No .utrace files found in any of the configured search directories.")
  end
  table.sort(utrace_files, function(a, b)
      local ok_a, stat_a = pcall(vim.loop.fs_stat, a)
      local ok_b, stat_b = pcall(vim.loop.fs_stat, b)
      if ok_a and ok_b then return stat_a.mtime.sec > stat_b.mtime.sec end
      return false
  end)
  unl_picker.pick({
    kind = "ulg_select_trace_file", title = "Select .utrace File to Analyze",
    conf = conf, items = utrace_files, on_submit = process_selected_utrace,
    preview_enabled = false, picker_opts = { preview = false, },
  })
end

function M.execute(opts)
  opts = opts or {}
  local project_root = unl_finder.project.find_project_root(vim.loop.cwd())
  if not project_root then
    return log.get().error("Not in an Unreal Engine project.")
  end
  if opts.has_bang then
    log.get().debug("Bang provided, opening trace picker directly.")
    open_trace_picker()
  else
    log.get().debug("Searching for the newest trace in Saved/Profiling...")
    local project_profiling_dir = path.join(project_root, "Saved", "Profiling")
    local files_in_proj = find_utrace_files({ project_profiling_dir })
    if #files_in_proj > 0 then
      table.sort(files_in_proj, function(a, b)
          local ok_a, stat_a = pcall(vim.loop.fs_stat, a)
          local ok_b, stat_b = pcall(vim.loop.fs_stat, b)
          if ok_a and ok_b then return stat_a.mtime.sec > stat_b.mtime.sec end
          return false
      end)
      local newest_file = files_in_proj[1]
      log.get().info("Found newest trace file: %s", newest_file)
      process_selected_utrace(newest_file)
    else
      log.get().debug("No trace files found in Saved/Profiling. Falling back to picker.")
      open_trace_picker()
    end
  end
end

return M

