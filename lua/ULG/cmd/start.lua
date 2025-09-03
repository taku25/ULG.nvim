local unl_finder = require("UNL.finder")
local unl_picker = require("UNL.backend.picker")
local viewer = require("ULG.window.log")
local log = require("ULG.logger")

local M = {}

---
-- ログディレクトリから再帰的にファイルを取得するヘルパー関数
-- fd が利用可能であれば fd を使い、なければ vim.fs.dir にフォールバックします。
-- @param dir string 探索を開始するディレクトリ
-- @return string[] 見つかったファイルのフルパスのリスト
local function find_log_files(dir)
  -- fd が利用可能かチェック
  if vim.fn.executable("fd") == 1 then
    log.get().debug("Using 'fd' to find log files.")
    -- --absolute-path で絶対パスを取得
    local cmd = { "fd", "--type", "f", "--absolute-path", ".", dir }
    local output = vim.fn.system(cmd)

    -- コマンドが成功し、空でないことを確認
    if vim.v.shell_error == 0 and output and output:match("%S") then
      return vim.split(output, "\n", { plain = true, trimempty = true })
    else
      log.get().warn("'fd' command failed or returned empty. Falling back to native search.")
      -- 失敗した場合は、下のネイティブ実装にフォールバック
    end
  end

  -- fd がない、または失敗した場合のフォールバック (vim.fs.dir を使用)
  log.get().debug("Using native vim.fs.dir recursive search.")
  local files = {}
  local function find_recursive(current_dir)
    -- on_error で権限エラーなどを無視して処理を続行
    local iter = vim.fs.dir(current_dir, { on_error = function() end })
    if not iter then
      return
    end

    for file, type in iter do
      local full_path = vim.fs.joinpath(current_dir, file)
      if type == "file" then
        table.insert(files, full_path)
      elseif type == "directory" then
        -- 再帰的に探索
        find_recursive(full_path)
      end
    end
  end

  find_recursive(dir)
  return files
end

function M.execute(opts)
  opts = opts or {}

  local project_root = unl_finder.project.find_project_root(vim.loop.cwd())
  if not project_root then
    return log.get().error("Not in an Unreal Engine project.")
  end

  local logs_dir = project_root .. "/Saved/Logs/"

  -- Case 1: `!`付きの場合 -> ピッカーで選択
  if opts.has_bang then
    --- ★★★ 変更点: exec_cmd の代わりに items を使用 ★★★
    local log_files = find_log_files(logs_dir)
    if #log_files == 0 then
      return log.get().warn("No log files found in %s", logs_dir)
    end

    -- 最終更新日時でソートする (新しいものが上に来るように)
    table.sort(log_files, function(a, b)
      local stat_a = vim.loop.fs_stat(a)
      local stat_b = vim.loop.fs_stat(b)
      if stat_a and stat_b then
        return stat_a.mtime.sec > stat_b.mtime.sec
      end
      return false
    end)

    unl_picker.pick({
      kind = "ulg_select_log_file",
      title = "Select Log File to View (sorted by latest)",
      conf = require("UNL.config").get("ULG"),
      items = log_files, -- exec_cmd の代わりに items を渡す
      on_submit = function(selected_file)
        if selected_file then
          viewer.start(selected_file)
        end
      end,
    })
    -- Case 2: `!`なしの場合 -> デフォルトのログをテイル
  else
    local uproject_path = unl_finder.project.find_project_file(project_root)
    if not uproject_path then
      log.get().warn("Could not find .uproject file to determine default log. Opening picker instead.")
      M.execute({ has_bang = true }) -- フォールバック
      return
    end

    local project_name = vim.fn.fnamemodify(uproject_path, ":t:r")
    local default_log_file = logs_dir .. project_name .. ".log"

    viewer.start(default_log_file)
  end
end

return M
