-- lua/ULG/cmd/start.lua

local unl_finder = require("UNL.finder")
local unl_picker = require("UNL.backend.picker")
local buf_manager = require("ULG.buf")
local log = require("ULG.logger")
-- finderモジュールを新しいパスで読み込む
local log_finder = require("ULG.finder.log")

local M = {}

function M.execute(opts)
  opts = opts or {}

  local function start_with_file(filepath)
    buf_manager.open_console(filepath)
  end

  local project_root = unl_finder.project.find_project_root(vim.loop.cwd())
  if not project_root then
    return log.get().error("Not in an Unreal Engine project.")
  end

  -- 'ULG start!' の場合 (bangあり)
  if opts.has_bang then
    -- ▼▼▼【ここが変更点】▼▼▼
    -- 以前はここにあったローカル関数を削除し、finderモジュールを呼び出す
    local log_files = log_finder.find_logs()
    -- ▲▲▲【変更点ここまで】▲▲▲
    
    if #log_files == 0 then
      local logs_dir = project_root .. "/Saved/Logs/"
      return log.get().warn("No log files found in %s", logs_dir)
    end
    
    -- 更新日時でソート
    table.sort(log_files, function(a, b)
      local stat_a, stat_b = vim.loop.fs_stat(a), vim.loop.fs_stat(b)
      if stat_a and stat_b then return stat_a.mtime.sec > stat_b.mtime.sec end
      return false
    end)
    
    -- ピッカーで表示
    unl_picker.pick({
      kind = "ulg_select_log_file",
      title = "Select Log File to View",
      conf = require("UNL.config").get("ULG"),
      items = log_files,
      on_submit = function(selected_file)
        if selected_file then
          start_with_file(selected_file)
        end
      end,
    })
  else
    -- 'ULG start' の場合 (bangなし)
    local uproject_path = unl_finder.project.find_project_file(project_root)
    if not uproject_path then
      log.get().warn("Could not find .uproject file. Opening picker instead.")
      M.execute({ has_bang = true }) -- bang付きの動作にフォールバック
      return
    end
    local project_name = vim.fn.fnamemodify(uproject_path, ":t:r")
    local default_log_file = project_root .. "/Saved/Logs/" .. project_name .. ".log"
    start_with_file(default_log_file)
  end
end

return M
