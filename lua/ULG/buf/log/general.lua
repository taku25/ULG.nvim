-- lua/ULG/buf/log/general.lua (汎用ログビューアとしての最終版)

local unl_log_engine = require("UNL.backend.buf.log")
local log = require("ULG.logger")
local tail = require("ULG.core.tail")

local M = {}
local handle = nil

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
    filetype = "ulg-log", -- 汎用的な"log"ファイルタイプ
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


-- 行をバッファに追記する
-- @param lines string | string[]
function M.append_lines(lines)
  if not M.is_open() then return end

  if type(lines) == "string" then
    lines = { lines }
  end
  if #lines > 0 then
    -- handleが持つAPIを呼び出して行を追加
    handle:add_lines(lines)
  end
end

return M
