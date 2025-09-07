-- lua/ULG/cache/trace.lua (ストリーム処理・分割キャッシュ対応版)

local unl_config = require("UNL.config")
local unl_cache_core = require("UNL.cache.core")
local ulg_log = require("ULG.logger")
local unl_path = require("UNL.path")
local fs = require("vim.fs")

local M = {}

--------------------------------------------------------------------------------
-- Path Helper Functions (Private)
--------------------------------------------------------------------------------

function M.get_trace_cache_dir(utrace_filepath)
  if not utrace_filepath or type(utrace_filepath) ~= "string" then
    ulg_log.get().error("Invalid utrace_filepath provided: %s", tostring(utrace_filepath))
    return nil
  end
  local conf = unl_config.get("ULG")
  local base_dir = unl_cache_core.get_cache_dir(conf)
  local traces_dir = fs.joinpath(base_dir, "traces")
  local utrace_without_ext = vim.fn.fnamemodify(utrace_filepath, ":r")
  local safe_dirname = unl_path.path_to_cache_filename(utrace_without_ext)
  return fs.joinpath(traces_dir, safe_dirname)
end

---
-- メタデータファイルのパスを取得する
local function get_metadata_path(trace_dir)
  return fs.joinpath(trace_dir, "trace_metadata.json")
end

---
-- 各スレッドのデータファイルのパスを取得する
local function get_thread_data_path(trace_dir, thread_id)
  return fs.joinpath(trace_dir, string.format("trace_data_thread_%s.json", thread_id))
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

---
-- トレース処理で生成されたメタデータを保存する
-- @param utrace_filepath string 元となった.utraceファイルのパス
-- @param metadata table 保存するメタデータ (timers, threads, trace_dataへのパス情報)
-- @return boolean 成功したかどうか
function M.save_metadata(utrace_filepath, metadata)
  local dir = M.get_trace_cache_dir(utrace_filepath)
  if not dir then
    ulg_log.get().error("Could not generate cache directory for metadata save. Aborting.")
    return false
  end

  local path = get_metadata_path(dir)
  local ok, err = unl_cache_core.save_json(path, metadata)
  if not ok then
    ulg_log.get().error("Failed to save trace metadata file: %s", tostring(err))
  end
  return ok
end

---
-- トレースキャッシュを読み込む (実際には軽量なメタデータのみを読み込む)
-- @param utrace_filepath string 元となった.utraceファイルのパス
-- @return table|nil データをオンデマンドで取得するためのハンドル、またはnil
function M.load(utrace_filepath)
  local dir = M.get_trace_cache_dir(utrace_filepath)
  if not dir then return nil end

  local path = get_metadata_path(dir)
  if vim.fn.filereadable(path) == 0 then
    return nil
  end

  local metadata = unl_cache_core.load_json(path)
  if not metadata then return nil end

  -- データアクセス用のメソッドを持つハンドルオブジェクトを作成して返す
  local handle = {
    _metadata = metadata,
    _cache_dir = dir,
    _hydrated_cache = {}, -- 読み込んで文字列解決したデータをメモリにキャッシュ

    ---
    -- イベントツリーのIDを実際の文字列に解決(Hydrate)する再帰関数
    _hydrate_tree = function(self, events)
      for _, event in ipairs(events) do
        local timer_data = self._metadata.timers[tostring(event.tid)]
        if timer_data then
          event.name = timer_data.name
          event.file = timer_data.file
          event.line = timer_data.line
        end
        if event.children and #event.children > 0 then
          self:_hydrate_tree(event.children)
        end
      end
    end,

    ---
    -- 指定されたスレッドの階層化イベントデータを取得する
    -- @param thread_id_or_name number | string スレッドのIDまたは名前
    -- @return table|nil 文字列が解決されたイベントツリー
    get_thread_events = function(self, thread_id_or_name)
      -- キャッシュをチェック
      local key = tostring(thread_id_or_name)
      if self._hydrated_cache[key] then
        return self._hydrated_cache[key]
      end

      local thread_id = nil
      if type(thread_id_or_name) == "number" then
        thread_id = thread_id_or_name
      else -- 文字列の場合はIDを検索
        for id, data in pairs(self._metadata.threads) do
          if data.name == thread_id_or_name then
            thread_id = tonumber(id)
            break
          end
        end
      end

      if not thread_id then
        ulg_log.get().warn("Could not find thread with name/id: %s", tostring(thread_id_or_name))
        return nil
      end

      local thread_data_info = self._metadata.trace_data[tostring(thread_id)]
      if not thread_data_info then return nil end

      -- 該当スレッドのJSONファイルを読み込む
      local data_path = get_thread_data_path(self._cache_dir, thread_id)
      local id_based_events = unl_cache_core.load_json(data_path)
      if not id_based_events then
        ulg_log.get().error("Failed to load thread data file: %s", data_path)
        return nil
      end

      -- IDを実際の文字列情報に置き換える (Hydrate)
      self:_hydrate_tree(id_based_events)

      -- 結果をキャッシュして返す
      self._hydrated_cache[key] = id_based_events
      return id_based_events
    end,

    ---
    -- 利用可能なスレッドの一覧を取得する
    get_available_threads = function(self)
      return self._metadata.threads
    end,
  }

  return handle
end

return M
