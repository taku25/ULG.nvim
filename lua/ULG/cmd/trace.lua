-- lua/ULG/cmd/trace.lua (キャッシュ統合版・完全コード)

local unl_api = require("UNL.api")
local unl_finder = require("UNL.finder")
local unl_picker = require("UNL.backend.picker")
local path = require("UNL.path")
local log = require("ULG.logger")
local general_log_view = require("ULG.buf.log.general")
local trace_cache = require("ULG.cache.trace")
local unl_progress = require("UNL.backend.progress") -- ★ プログレスバーをrequire

local M = {}

--------------------------------------------------------------------------------
-- Helper Functions (Private)
--------------------------------------------------------------------------------


--- [FIX] Timers.csvの行を堅牢に解析するヘルパー関数
-- Nameフィールドが引用符で囲まれている場合と、そうでない場合の両方に対応する
local function parse_timer_line(line)
  if not line or line == "" then return nil end

  local id, type, name, file, line_num
  local current_pos = 1

  -- 1. Idの解析
  local next_comma = line:find(",", current_pos)
  if not next_comma then return nil end
  id = line:sub(current_pos, next_comma - 1)
  current_pos = next_comma + 1

  -- 2. Typeの解析
  next_comma = line:find(",", current_pos)
  if not next_comma then return nil end
  type = line:sub(current_pos, next_comma - 1)
  current_pos = next_comma + 1

  -- 3. Nameの解析 (引用符の有無を考慮)
  if line:sub(current_pos, current_pos) == '"' then
    -- Nameが引用符で囲まれている
    current_pos = current_pos + 1
    local end_quote = line:find('",', current_pos)
    if not end_quote then return nil end -- 予期せぬ形式
    name = line:sub(current_pos, end_quote - 1)
    current_pos = end_quote + 2 -- `",`をスキップ
  else
    -- Nameが引用符で囲まれていない
    next_comma = line:find(",", current_pos)
    if not next_comma then return nil end
    name = line:sub(current_pos, next_comma - 1)
    current_pos = next_comma + 1
  end

  -- 4. FileとLineの解析 (存在しない場合も考慮)
  if current_pos > #line then
    -- 行の末尾に到達した場合
    file = ""
    line_num = ""
  else
    local rest_of_line = line:sub(current_pos)
    local last_comma_pos = rest_of_line:match("^.*,") -- 最後尾のカンマを探す
    if last_comma_pos then
      -- カンマが見つかれば、それがFileとLineの区切り
      local split_pos = #last_comma_pos
      file = rest_of_line:sub(1, split_pos - 1)
      line_num = rest_of_line:sub(split_pos + 1)
    else
      -- カンマがなければ、残りは全てFileでLineは空
      file = rest_of_line
      line_num = ""
    end
  end

  return id, type, name, file, line_num
end

--- .utrace ファイルを再帰的に検索するヘルパー
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

local function load_csvs_async(export_dir, on_complete)
  local files_to_load = {
    timers = path.join(export_dir, "Timers.csv"),
    threads = path.join(export_dir, "Threads.csv"),
    events = path.join(export_dir, "TimingEvents.csv"),
  }
  
  local results = {}
  local remaining = vim.tbl_count(files_to_load)

  -- 真の非同期ファイルリーダー
  local function read_file_async(filepath, callback)
    local fd = vim.loop.fs_open(filepath, "r", 438)
    if not fd then return callback(nil, "Failed to open file") end

    vim.loop.fs_fstat(fd, function(err, stat)
      if err or not stat then
        vim.loop.fs_close(fd)
        return callback(nil, "Failed to get file stats")
      end

      vim.loop.fs_read(fd, stat.size, 0, function(err2, data)
        vim.loop.fs_close(fd)
        if err2 or not data then
          return callback(nil, "Failed to read file content")
        end
        -- 読み込み成功後、安全なタイミングでコールバックを呼び出す
        vim.schedule(function()
          callback(vim.split(data, "\r?\n"))
        end)
      end)
    end)
  end

  -- 各ファイルを非同期で読み込むループ
  for key, filepath in pairs(files_to_load) do
    -- ★★★ これが、最後の、そして真の修正です ★★★
    -- ループ内の変数をキャプチャするために、無名関数でラップする
    (function(current_key, current_filepath)
      read_file_async(current_filepath, function(lines, err_msg)
        if not lines then
          log.get().error("Failed to read '%s': %s", current_key, err_msg or "Unknown error")
          results[current_key] = {} -- 失敗した場合は空のテーブルを入れる
        else
          results[current_key] = lines
        end
        
        remaining = remaining - 1
        if remaining == 0 then
          -- 全ての読み込みが完了したら、最終コールバックを呼ぶ
          on_complete(results)
        end
      end)
    end)(key, filepath)
  end
end
---
-- @param utrace_filepath string 元となった.utraceファイルのパス
-- @param loaded_data table {timers, threads, events} 各CSVの内容(行のテーブル)を格納したテーブル
-- @param progress_handle table create_for_refreshから返されたプログレスハンドル
local function process_in_memory_data_async(utrace_filepath, loaded_data, progress_handle)
  -- 読み込まれたデータを展開
  local timer_lines = loaded_data.timers
  local thread_lines = loaded_data.threads
  local event_lines = loaded_data.events

  local worker = coroutine.create(function()
    local timer_info = {}
    local thread_info = {}
    local integrated_events = {}

    -- ステージ: Timers.csv
    progress_handle:stage_define("timers", #timer_lines)
    progress_handle:stage_update("timers", 0, "Parsing Timers...")
    for i, line in ipairs(timer_lines) do
      if line ~= "Id,Type,Name,File,Line" and line ~= "" then
        -- BUG: 古い正規表現は削除
        -- local id, type, name, file, line_num = line:match('^([^,]+),([^,]+),"(.-)",(.-),([^,]+)$')
        
        -- FIX: 新しい堅牢なパーサーを呼び出す
        local id, type, name, file, line_num = parse_timer_line(line)

        if id then
          timer_info[tonumber(id)] = { name = name, file = file, line = line_num }
        end
      end
      if i % 500 == 0 then
        progress_handle:stage_update("timers", i, string.format("Parsing Timers... (%d/%d)", i, #timer_lines))
        coroutine.yield()
      end
    end
    progress_handle:stage_update("timers", #timer_lines, "Parsed Timers")

    -- ステージ: Threads.csv
    progress_handle:stage_define("threads", #thread_lines)
    progress_handle:stage_update("threads", 0, "Parsing Threads...")
    for i, line in ipairs(thread_lines) do
      if line ~= "Id,Name,Group" and line ~= "" then
        local id, name, group = line:match('^([^,]+),([^,]+),?(.*)$')
        if id and name then thread_info[tonumber(id)] = { name = name, group = group } end
      end
      if i % 500 == 0 then
        progress_handle:stage_update("threads", i, string.format("Parsing Threads... (%d/%d)", i, #thread_lines))
        coroutine.yield()
      end
    end
    progress_handle:stage_update("threads", #thread_lines, "Parsed Threads")
    
    -- ステージ: TimingEvents.csv
    local total_event_lines = #event_lines
    progress_handle:stage_define("events", total_event_lines)
    progress_handle:stage_update("events", 0, "Integrating Events...")
    for i, line in ipairs(event_lines) do
      local thread_id_str, timer_id_str, start_time, end_time, depth = line:match('^([^,]+),([^,]+),([^,]+),([^,]+),([^,]+)$')
      if timer_id_str and timer_id_str ~= "TimerId" then
        local timer_id, thread_id = tonumber(timer_id_str), tonumber(thread_id_str)
        local info, th_info = timer_info[timer_id], thread_info[thread_id]
        if info then
          table.insert(integrated_events, {
            name = info.name, file = info.file, line = info.line,
            start = tonumber(start_time), ["end"] = tonumber(end_time), depth = tonumber(depth),
            thread_id = thread_id, thread_name = (th_info and th_info.name) or "Unknown",
            thread_group = (th_info and th_info.group) or "",
          })
        end
      end
      if i % 2000 == 0 then
        progress_handle:stage_update("events", i, string.format("Integrating Events... (%d/%d)", i, total_event_lines))
        coroutine.yield()
      end
    end
    progress_handle:stage_update("events", total_event_lines, "Integrated all events")
    
    -- ステージ: finalize
    progress_handle:stage_update("finalize", 0, "Saving cache...")
    local ok = trace_cache.save(utrace_filepath, integrated_events)
    if ok then
      log.get().info("Successfully saved trace cache for %s", utrace_filepath)
      vim.notify("Trace analysis complete and cached successfully!")
      -- TODO: display_trace_data(integrated_events)
    else
      log.get().error("Failed to save trace cache for %s", utrace_filepath)
    end
    progress_handle:stage_update("finalize", 1, "Cache saved.")
  end)
  
  -- コルーチンを駆動する関数
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
  if coroutine.status(worker) == "suspended" then
    vim.defer_fn(resume_worker, 1)
  end
end


--- UnrealInsights.exe を非同期で実行してCSV群を生成する
local function run_insights(utrace_filepath)
  local export_dir = trace_cache.get_trace_cache_dir(utrace_filepath)
  if not export_dir then return end
  vim.fn.mkdir(export_dir, "p")

  -- 1. スレッド情報CSVの絶対パスも構築
  local timers_csv_path = path.join(export_dir, "Timers.csv")
  local events_csv_path = path.join(export_dir, "TimingEvents.csv")
  local threads_csv_path = path.join(export_dir, "Threads.csv") -- ★ 新設

  -- 2. パスを引用符で囲む
  local quoted_timers_path = string.format('%q', timers_csv_path)
  local quoted_events_path = string.format('%q', events_csv_path)
  local quoted_threads_path = string.format('%q', threads_csv_path) -- ★ 新設

  -- 3. レスポンスファイルに、ExportThreadsコマンドを追加
  local rsp_path = path.join(export_dir, "export.rsp")
  local rsp_content = {
    "TimingInsights.ExportTimers " .. quoted_timers_path,
    "TimingInsights.ExportTimingEvents " .. quoted_events_path,
    "TimingInsights.ExportThreads " .. quoted_threads_path, -- ★ 新設
  }
  vim.fn.writefile(rsp_content, rsp_path)
  
  local insights_log_path = path.join(export_dir, "UnrealInsights.log")
  
  local conf = require("UNL.config").get("ULG")
  local progress_handle, provider_name =unl_progress.create_for_refresh(conf, {
    title = "ULG Trace Analysis",
    client_name = "ULG",
    weights = {
      insights = 0.30, -- Insights実行 (30%)
      load_csv = 0.20, -- CSV読み込み (20%)
      timers   = 0.05, -- Timers解析 (5%)
      threads  = 0.05, -- Threads解析 (5%)
      events   = 0.35, -- Events統合 (35%)
      finalize = 0.05, -- 最終保存 (5%)
    },
  })
  
  progress_handle:stage_define("insights", 1)
  progress_handle:stage_define("load_csv", 1) -- 新しいステージ
  progress_handle:stage_define("finalize", 1)
  -- (他のステージは、async関数内で動的にdefineしても良いが、ここで定義するとより明確)

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
  
  -- ★★★ ここからが、最後の改修です ★★★

  local final_command
  if vim.loop.os_uname().sysname == "Windows_NT" then
    -- 内部のコマンド文字列を、cmd.exeが解釈できるように組み立てる
    local inner_command = string.format(
      '"%s" -OpenTraceFile="%s" -ABSLOG="%s" -NoUI -AutoQuit -ExecOnAnalysisCompleteCmd="@=%s"',
      insights_exe,
      utrace_filepath,
      insights_log_path,
      rsp_path
    )
    -- jobstartに渡す、最終的な「単一の文字列」を作成
    final_command = "cmd.exe /c " .. inner_command
  else
    -- 非Windowsでは、これまで通りテーブル形式が最も安全
    final_command = {
        insights_exe,
        "-OpenTraceFile=" .. utrace_filepath,
        "-ABSLOG=" .. insights_log_path,
        "-NoUI",
        "-AutoQuit",
        "-ExecOnAnalysisCompleteCmd=@=" .. rsp_path
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
          
          -- ★ ステージ2: CSVの非同期読み込みを開始
          progress_handle:stage_update("load_csv", 0, "Loading CSV files...")
          load_csvs_async(export_dir, function(loaded_data)
            progress_handle:stage_update("load_csv", 1, "CSV files loaded.")
            
            -- ★ ステージ3: 読み込んだデータを、非同期パーサーに渡す
            process_in_memory_data_async(utrace_filepath, loaded_data, progress_handle)
          end)
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

--- 選択された.utraceファイルを処理する共通ロジック
local function process_selected_utrace(utrace_filepath)
  if not utrace_filepath then return end

  local cached_data = trace_cache.load(utrace_filepath)
  if cached_data then
    log.get().info("Found valid trace cache for %s", utrace_filepath)
    vim.notify("Trace cache loaded successfully!")
    -- TODO: ここで、キャッシュされたデータを表示する関数を呼ぶ
    -- display_trace_data(cached_data)
    return
  end

  log.get().info("No cache found for %s. Starting new analysis.", utrace_filepath)
  run_insights(utrace_filepath)
end

--- 全領域から.utraceファイルを探し、ピッカーを開く
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
      if ok_a and ok_b then
          return stat_a.mtime.sec > stat_b.mtime.sec
      end
      return false
  end)

  unl_picker.pick({
    kind = "ulg_select_trace_file",
    title = "Select .utrace File to Analyze",
    conf = conf,
    items = utrace_files,
    on_submit = process_selected_utrace,
    preview_enabled = false,
    picker_opts = {
      preview = false,
    },
  })
end

--- :ULG trace コマンドのメインロジック (Public)
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
          if ok_a and ok_b then
              return stat_a.mtime.sec > stat_b.mtime.sec
          end
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
