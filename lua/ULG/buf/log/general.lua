-- lua/ULG/buf/log/general.lua (汎用ログビューアとしての最終版)

local unl_log_engine = require("UNL.backend.buf.log")
local log = require("ULG.logger")
local tail = require("ULG.core.tail")

local M = {}
local handle, tailer

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

---
-- この汎用ビューアの仕様書(spec)を作成する
-- @param conf table プラグインの設定テーブル
-- @return table UNL.backend.buf.log.createに渡すためのspec
function M.create_spec(conf)
  return {
    id = "ulg_general_log", -- IDを汎用的な名前に
    title = "[[ General Log ]]", -- タイトルは通常、set_titleで上書きされる
    filetype = "log", -- 汎用的な"log"ファイルタイプ
    auto_scroll = true,
    keymaps = {
      -- ウィンドウを閉じるキーマップのみを設定
      ["q"] = "<cmd>lua require('ULG.api').close()<cr>",
      -- エラー箇所へのジャンプなどは、特定のコンテキスト(UBT実行時など)で
      -- 動的に追加/削除するのが望ましいかもしれない
    },
  }
end

---
-- 司令官から、このモジュールが操作すべきハンドルを受け取る
-- @param h table ウィンドウハンドル
function M.set_handle(h)
  handle = h
end

---
-- ウィンドウのタイトルを動的に変更する
-- @param title string 新しいタイトル
function M.set_title(title)
  if handle and handle:is_open() then
    vim.api.nvim_set_option_value("statusline", title, { win = handle:get_win_id() })
  end
end

---
-- バッファの内容を全てクリアする
function M.clear_buffer()
    if handle and handle:is_open() then
        vim.api.nvim_set_option_value("modifiable", true, { buf = handle._buf })
        vim.api.nvim_buf_set_lines(handle._buf, 0, -1, false, {})
        vim.api.nvim_set_option_value("modifiable", false, { buf = handle._buf })
    end
end

function M.is_open()
  return handle and handle:is_open()
end
---
-- 指定されたファイルの追跡(tailing)を開始する
-- @param filepath string 監視対象のファイルパス
function M.start_tailing(filepath, opts)
  opts = opts or {}
  if not (handle and handle:is_open()) then 
    log.get().warn("General log window is not open. Cannot start tailing.")
    return 
  end
  
  if tailer then tailer:stop() end
  
  M.clear_buffer()
  local conf = require("UNL.config").get("ULG")
  
  tailer = tail.start(filepath, conf.polling_interval_ms or 200, function(new_lines)
    if not (handle and handle:is_open()) then return end

    local lines_to_add = {}
    for _, line in ipairs(new_lines) do
      local is_handled = false
      if opts.on_line then
        -- コールバックを呼び出し、戻り値でバッファに追加するか判断
        is_handled = opts.on_line(line)
      end
      -- コールバックが存在しないか、falseを返した場合のみバッファに追加
      if not is_handled then
        table.insert(lines_to_add, line)
      end
    end

    if #lines_to_add > 0 then
      handle:add_lines(lines_to_add)
    end
  end)
end

---
-- 現在のファイルの追跡を停止する
function M.stop_tailing()
  if tailer then
    tailer:stop()
    tailer = nil
    log.get().debug("General log tailer stopped.")
  end
end

---
-- このウィンドウを閉じる (現在は司令官が一括で閉じるため、直接は使われない)
function M.close()
  M.stop_tailing()
  if handle and handle:is_open() then
    handle:close()
    handle = nil
  end
end

return M
