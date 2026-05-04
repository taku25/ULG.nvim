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

---
-- .uba ビルドトレースファイルを検索する
-- 検索場所: {engine_root}/Engine/Programs/UnrealBuildTool/ (最優先)
--           {project_root}/Engine/Programs/UnrealBuildTool/
-- @return table<string> .uba ファイルのフルパスリスト
function M.find_uba_logs()
  local files = {}

  -- プロジェクトルートを取得 (cwd → 現在バッファ → 失敗の順で試みる)
  local function resolve_project_root()
    local pr = unl_finder.project.find_project_root(vim.loop.cwd())
    if pr then return pr end
    local buf_path = vim.api.nvim_buf_get_name(0)
    if buf_path and buf_path ~= "" then
      pr = unl_finder.project.find_project_root(vim.fn.fnamemodify(buf_path, ":p:h"))
      if pr then return pr end
    end
    return nil
  end

  local project_root = resolve_project_root()

  local search_dirs = {}

  if project_root then
    -- ゲームプロジェクト内の UBT ログディレクトリ
    -- (source build / embedded engine の場合: {project_root}/Engine/Programs/UnrealBuildTool/)
    table.insert(search_dirs, project_root .. "/Engine/Programs/UnrealBuildTool")
    table.insert(search_dirs, project_root .. "/Saved/Logs")

    -- エンジンが別インストールの場合: エンジンルートも探す
    local project = unl_finder.project.find_project(vim.loop.cwd())
      or (vim.api.nvim_buf_get_name(0) ~= "" and
          unl_finder.project.find_project(
            vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ":p:h")))
    if project and project.uproject then
      local ok, engine_finder = pcall(require, "UNL.finder.engine")
      if ok then
        local engine_root = engine_finder.find_engine_root
          and engine_finder.find_engine_root(project.uproject,
              { engine_override_path = require("UNL.config").get("ULG").engine_path })
        if engine_root and engine_root ~= project_root then
          table.insert(search_dirs, engine_root .. "/Engine/Programs/UnrealBuildTool")
        end
      end
    end
  end

  -- エンジン側の UBT ログ (LOCALAPPDATA / XDG_CACHE)
  if vim.fn.has("win32") == 1 then
    local local_appdata = os.getenv("LOCALAPPDATA")
    if local_appdata then
      table.insert(search_dirs, local_appdata .. "\\UnrealBuildTool")
    end
  else
    local home = os.getenv("HOME")
    if home then
      table.insert(search_dirs, home .. "/.config/UnrealBuildTool")
    end
  end

  for _, dir in ipairs(search_dirs) do
    if vim.fn.isdirectory(dir) == 1 then
      if vim.fn.executable("fd") == 1 then
        local output = vim.fn.system({
          "fd", "--type", "f", "--extension", "uba",
          "--no-ignore",
          "--absolute-path", "--max-depth", "2", ".", dir
        })
        if vim.v.shell_error == 0 and output and output:match("%S") then
          for _, p in ipairs(vim.split(output, "\n", { plain = true, trimempty = true })) do
            table.insert(files, p)
          end
        end
      else
        -- fd が無い場合は vim.fs.dir でフラットに検索
        for fname, ftype in vim.fs.dir(dir) do
          if ftype == "file" and fname:match("%.uba$") then
            table.insert(files, dir .. "/" .. fname)
          end
        end
      end
    end
  end

  -- 重複排除
  local seen = {}
  local unique = {}
  for _, p in ipairs(files) do
    if not seen[p] then seen[p] = true; table.insert(unique, p) end
  end
  return unique
end

return M
