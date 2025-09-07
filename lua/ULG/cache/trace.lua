-- lua/ULG/cache/trace.lua (新しいディレクトリ構造に対応)

local unl_config = require("UNL.config")
local unl_cache_core = require("UNL.cache.core")
local ulg_log = require("ULG.logger")
local unl_path = require("UNL.path")
local fs = require("vim.fs")

local M = {}


---
-- ★★★ ここが新しいディレクトリ構造の心臓部です ★★★
-- .utraceファイルのパスから、専用のキャッシュディレクトリのパスを生成する
-- @param utrace_filepath string .utraceファイルの絶対パス
-- @return string|nil 専用キャッシュディレクトリの絶対パス
function M.get_trace_cache_dir(utrace_filepath)
  if not utrace_filepath or type(utrace_filepath) ~= "string" then
    ulg_log.get().error("Invalid utrace_filepath provided: %s", tostring(utrace_filepath))
    return nil
  end

  local conf = unl_config.get("ULG")
  local base_dir = unl_cache_core.get_cache_dir(conf)
  local traces_dir = fs.joinpath(base_dir, "traces")
  
  -- .utraceのフルパスを、衝突しない安全なディレクトリ名に変換
  -- (拡張子 .utrace を取り除いてから変換)
  local utrace_without_ext = vim.fn.fnamemodify(utrace_filepath, ":r")
  local safe_dirname = unl_path.path_to_cache_filename(utrace_without_ext)
  
  return fs.joinpath(traces_dir, safe_dirname)
end


---
-- 統合されたトレースデータをJSONキャッシュとして保存する
-- @param utrace_filepath string 元となった.utraceファイルのパス
-- @param data table 保存するLuaテーブル
-- @return boolean 成功したかどうか
function M.save(utrace_filepath, data)
  local dir = M.get_trace_cache_dir(utrace_filepath)
  if not dir then
    ulg_log.get().error("Could not generate cache directory for save operation. Aborting.")
    return false
  end
  
  -- 保存先は、専用ディレクトリ内の trace.json とする
  local path = fs.joinpath(dir, "trace.json")

  local ok, err = unl_cache_core.save_json(path, data)
  if not ok then
    ulg_log.get().error("Failed to save trace cache file: %s", tostring(err))
  end

  return ok
end

---
-- JSONキャッシュからトレースデータを読み込む
-- @param utrace_filepath string 元となった.utraceファイルのパス
-- @return table|nil 読み込んだLuaテーブル、またはnil
function M.load(utrace_filepath)
  local dir = M.get_trace_cache_dir(utrace_filepath)
  if not dir then return nil end

  local path = fs.joinpath(dir, "trace.json")
  if vim.fn.filereadable(path) == 0 then
    return nil
  end

  return unl_cache_core.load_json(path)
end

return M
