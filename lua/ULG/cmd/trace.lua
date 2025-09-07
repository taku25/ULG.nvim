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
local function process_stream_data_async(utrace_filepath, loaded_maps, progress_handle)
  local trace_dir = trace_cache.get_trace_cache_dir(utrace_filepath)
  local events_csv_path = path.join(trace_dir, "TimingEvents.csv")

  local worker = coroutine.create(function()
    local thread_states = {}
    local line_count = 0
    progress_handle:stage_define("processing", 1)
    progress_handle:stage_update("processing", 0, "Processing events...")

    for line in io.lines(events_csv_path) do
      line_count = line_count + 1
      local thread_id_str, timer_id_str, start_time, end_time, depth_str = line:match('^([^,]+),([^,]+),([^,]+),([^,]+),([^,]+)$')

      if timer_id_str and timer_id_str ~= "TimerId" then
        local thread_id = tonumber(thread_id_str)
        local depth = tonumber(depth_str)

        if not thread_states[thread_id] then
          thread_states[thread_id] = {
            event_stack = {},
            top_level_events = {},
          }
        end
        local state = thread_states[thread_id]

        local event = {
          tid = tonumber(timer_id_str),
          s = tonumber(start_time),
          e = tonumber(end_time),
          children = {}
        }

        while #state.event_stack > depth do
          table.remove(state.event_stack)
        end

        if #state.event_stack > 0 then
          local parent = state.event_stack[#state.event_stack]
          table.insert(parent.children, event)
        else
          table.insert(state.top_level_events, event)
        end

        table.insert(state.event_stack, event)
      end

      if line_count % 10000 == 0 then
        progress_handle:stage_update("processing", 0.5, string.format("Processing events... (line %d)", line_count))
        coroutine.yield()
      end
    end
    progress_handle:stage_update("processing", 1, "Finished processing events.")

    progress_handle:stage_define("saving", vim.tbl_count(thread_states))
    progress_handle:stage_update("saving", 0, "Saving cache files...")

    local trace_data_metadata = {}
    local saved_count = 0
    for thread_id, state in pairs(thread_states) do
      if #state.top_level_events > 0 then
        local thread_data_path = path.join(trace_dir, string.format("trace_data_thread_%s.json", thread_id))
        unl_cache_core.save_json(thread_data_path, state.top_level_events)
        trace_data_metadata[tostring(thread_id)] = {}
      end
      saved_count = saved_count + 1
      progress_handle:stage_update("saving", saved_count, string.format("Saving cache for thread %d", thread_id))
      coroutine.yield()
    end

    local final_metadata = {
      timers = loaded_maps.timers,
      threads = loaded_maps.threads,
      trace_data = trace_data_metadata,
    }
    trace_cache.save_metadata(utrace_filepath, final_metadata)

    log.get().info("Successfully saved trace cache for %s", utrace_filepath)
    vim.notify("Trace analysis complete and cached successfully!")
    progress_handle:stage_update("saving", saved_count, "Cache saved.")
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
local function run_insights(utrace_filepath)
  local export_dir = trace_cache.get_trace_cache_dir(utrace_filepath)
  if not export_dir then return end
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
    weights = { insights = 0.40, load_csv = 0.10, processing = 0.40, saving = 0.10, },
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
        if general_log_view.is_open and general_log_view.is_open() then
          general_log_view.set_title("[[ General Log ]]")
        end

        if exit_code == 0 then
          progress_handle:stage_update("insights", 1, "UnrealInsights finished.")

          progress_handle:stage_update("load_csv", 0, "Loading Timers/Threads CSV...")
          local timer_info, thread_info = load_small_csvs(export_dir)
          progress_handle:stage_update("load_csv", 1, "CSV files loaded.")

          process_stream_data_async(utrace_filepath, { timers = timer_info, threads = thread_info }, progress_handle)

        else
          log.get().error("UnrealInsights failed with exit code: %s", exit_code)
          progress_handle:finish(false)
        end
      end)
    end,
  })
end


--------------------------------------------------------------------------------
-- Command Logic (:ULG trace)
--------------------------------------------------------------------------------

local function process_selected_utrace(utrace_filepath)
  if not utrace_filepath then return end

  local trace_handle = trace_cache.load(utrace_filepath)
  if trace_handle then
    log.get().info("Found valid trace cache for %s", utrace_filepath)
    vim.notify("Trace cache loaded successfully!")
    -- TODO: ここで、ハンドルを使ってデータを表示する関数を呼ぶ
    -- 例:
    -- local game_thread_data = trace_handle:get_thread_events("GameThread")
    -- if game_thread_data then
    --   -- ここでデータを表示するUIロジックを呼び出す
    --   require("ULG.ui.trace_viewer").display(game_thread_data)
    -- end
    return
  end

  log.get().info("No cache found for %s. Starting new analysis.", utrace_filepath)
  run_insights(utrace_filepath)
end

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

