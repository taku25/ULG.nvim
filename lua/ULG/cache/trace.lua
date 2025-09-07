-- lua/ULG/cache/trace.lua (path.joinエラー修正版)

local unl_config = require("UNL.config")
local unl_cache_core = require("UNL.cache.core")
local ulg_log = require("ULG.logger")
local unl_path = require("UNL.path")

local M = {}

-- (get_trace_cache_dir, get_metadata_path, save_metadata は変更なし)
function M.get_trace_cache_dir(utrace_filepath)
  if not utrace_filepath or type(utrace_filepath) ~= "string" then
    ulg_log.get().error("Invalid utrace_filepath provided: %s", tostring(utrace_filepath))
    return nil
  end
  local conf = unl_config.get("ULG")
  local base_dir = unl_cache_core.get_cache_dir(conf)
  local traces_dir = unl_path.join(base_dir, "traces")
  local utrace_without_ext = vim.fn.fnamemodify(utrace_filepath, ":r")
  local safe_dirname = unl_path.path_to_cache_filename(utrace_without_ext)
  return unl_path.join(traces_dir, safe_dirname)
end
local function get_metadata_path(trace_dir)
  return unl_path.join(trace_dir, "trace_metadata.json")
end
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


function M.load(utrace_filepath)
  local dir = M.get_trace_cache_dir(utrace_filepath)
  if not dir then return nil end
  local path = get_metadata_path(dir)
  if vim.fn.filereadable(path) == 0 then return nil end
  local metadata = unl_cache_core.load_json(path)
  if not metadata then return nil end

  local handle = {
    _metadata = metadata,
    _cache_dir = dir,
    _hydrated_cache = {},
    _hydrate_tree = function(self, events)
      for _, event in ipairs(events) do
        local timer_data = self._metadata.timers[tostring(event.tid)]
        if timer_data then
          event.name = timer_data.name; event.file = timer_data.file; event.line = timer_data.line;
        end
        if event.children and #event.children > 0 then self:_hydrate_tree(event.children) end
      end
    end,
    get_thread_events = function(self, thread_id_or_name)
      local key = tostring(thread_id_or_name)
      if self._hydrated_cache[key] then return self._hydrated_cache[key] end

      local thread_id
      if type(thread_id_or_name) == "number" then
        thread_id = thread_id_or_name
      else
        for id, data in pairs(self._metadata.threads) do
          if data.name == thread_id_or_name then thread_id = tonumber(id); break end
        end
      end
      if not thread_id then return nil end
      
      local thread_data_info = self._metadata.trace_data[tostring(thread_id)]
      if not (thread_data_info and thread_data_info.chunks and #thread_data_info.chunks > 0) then return {} end

      local all_events_for_thread = {}
      for _, chunk_filename in ipairs(thread_data_info.chunks) do
        -- ★★★ ここで path.join が使われるため、require が必要でした ★★★
        local chunk_path = unl_path.join(self._cache_dir, chunk_filename)
        local chunk_events = unl_cache_core.load_json(chunk_path)
        if chunk_events then
          vim.list_extend(all_events_for_thread, chunk_events)
        else
          ulg_log.get().warn("Failed to load trace chunk: %s", chunk_path)
        end
      end

      self:_hydrate_tree(all_events_for_thread)
      self._hydrated_cache[key] = all_events_for_thread
      return all_events_for_thread
    end,
    get_available_threads = function(self) return self._metadata.threads end,
  }
  return handle
end

return M
