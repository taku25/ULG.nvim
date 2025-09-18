-- lua/ULG/cmd/crash.lua

-- 新しいパスでfinderを読み込む
local log_finder = require("ULG.finder.log")
local unl_picker = require("UNL.backend.picker")
local log = require("ULG.logger")
-- おそらくバッファを開くためのモジュールが必要になります
local buf_manager = require("ULG.buf")

local M = {}

function M.execute()
  -- クラッシュログを検索
  local crash_logs = log_finder.find_crashes()
  if #crash_logs == 0 then
    log.get().info("No crash logs found.")
    vim.notify("ULG: No crash logs found.")
    return
  end
  
  -- 見つかったログを更新日時順にソート
  table.sort(crash_logs, function(a, b)
    local stat_a, stat_b = vim.loop.fs_stat(a), vim.loop.fs_stat(b)
    if stat_a and stat_b then return stat_a.mtime.sec > stat_b.mtime.sec end
    return false
  end)

  -- ピッカーでユーザーに選択させる
  unl_picker.pick({
    kind = "ulg_select_crash_log",
    title = "Select Crash Log to View",
    conf = require("UNL.config").get("ULG"),
    items = crash_logs,
    on_submit = function(selected_file)
      if selected_file then
        -- 既存のログ表示機能を呼び出す（ファイルパスを渡す）
        -- ※ buf_manager.open_console がUEログ専用の場合、
        --   クラッシュログ用の新しい関数が必要になるかもしれません。
        buf_manager.open_console(selected_file)
      end
    end,
  })
end

return M
