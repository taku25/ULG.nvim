-- lua/ULG/log_finder.lua
-- ログファイルやクラッシュログなど、特定のファイルを検索するロジックを集約するモジュール

local unl_finder = require("UNL.finder")
local log = require("ULG.logger")

local M = {}

---
-- プロジェクト内の指定されたサブディレクトリから、特定の拡張子を持つファイルを再帰的に検索する汎用ヘルパー関数
-- @param subdir string プロジェクトルートからのサブディレクトリパス (例: "/Saved/Logs")
-- @param extension string 検索するファイルの拡張子 (例: "log")
-- @return table<string> 見つかったファイルのフルパスのリスト
local function find_files_in_subdir(subdir, extension)
  local project_root = unl_finder.project.find_project_root(vim.loop.cwd())
  if not project_root then
    log.get().error("Not in an Unreal Engine project. Cannot find files.")
    return {}
  end
  
  local search_dir = project_root .. subdir
  if vim.fn.isdirectory(search_dir) == 0 then
    -- ディレクトリが存在しない場合は空のテーブルを返す
    return {}
  end

  -- fdコマンドが利用可能なら、高速に検索する
  if vim.fn.executable("fd") == 1 then
    local cmd = { "fd", "--type", "f", "--extension", extension, "--absolute-path", ".", search_dir }
    local output = vim.fn.system(cmd)
    if vim.v.shell_error == 0 and output and output:match("%S") then
      return vim.split(output, "\n", { plain = true, trimempty = true })
    end
  end

  -- fdがない場合のフォールバック
  local files = {}
  local function find_recursive(current_dir)
    local iter = vim.fs.dir(current_dir, { on_error = function() end })
    if not iter then return end
    for file, type in iter do
      local full_path = vim.fs.joinpath(current_dir, file)
      if type == "file" and file:match("%." .. extension .. "$") then
        table.insert(files, full_path)
      elseif type == "directory" then
        find_recursive(full_path)
      end
    end
  end
  find_recursive(search_dir)
  return files
end


---
-- /Saved/Logs ディレクトリ内の .log ファイルを検索する
-- @return table<string> ログファイルのリスト
function M.find_logs()
  return find_files_in_subdir("/Saved/Logs", "log")
end

---
-- /Saved/Crashes ディレクトリ内の .log ファイルを検索する
-- @return table<string> クラッシュログファイルのリスト
function M.find_crashes()
    return find_files_in_subdir("/Saved/Crashes", "log")
end

return M
