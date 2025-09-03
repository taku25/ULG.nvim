-- lua/ULG/context/view_state.lua
-- ULG.nvim のビューアの状態を UNL.context を使って管理するモジュール
local unl_context = require("UNL.context")

local M = {}

local NS = "ulg.viewer" -- このモジュール用の名前空間
local KEY = "singleton"  -- ビューアは常に一つなので、キーは固定

-- state のデフォルト構造を返す関数
local function get_default_state()
  return {
    master_buf = nil,
    view_buf = nil,
    win = nil,
    watcher = nil,
    filepath = nil,
    last_size = 0,
    filter_query = nil,
    category_filters = {},
    filters_enabled = true,
    saved_filters = nil,
    search_query = nil,
    search_hl_id = nil,
    line_queue = {},
    is_processing = false,
    conf = nil,
    help_win = nil,
    help_buf = nil,
  }
end

-- UNL.context のハンドルを取得する内部関数
local function get_handle()
  return unl_context.use(NS):key(KEY)
end

---
-- 状態が初期化されていなければ、デフォルト値で初期化します。
function M.init()
  local handle = get_handle()
  if handle:get("state") == nil then
    handle:set("state", get_default_state())
  end
end

---
-- 現在の state テーブル全体を返します。
-- @return table 現在の状態
function M.get_state()
  local handle = get_handle()
  -- 万が一初期化されていなくても安全に呼び出せるようにする
  if handle:get("state") == nil then
    M.init()
  end
  return handle:get("state")
end

---
-- state テーブルの一部を更新します。
-- @param new_values table 更新したいキーと値のペアを持つテーブル
function M.update_state(new_values)
  local handle = get_handle()
  local current_state = M.get_state()
  -- 新しい値を現在の状態にマージ
  for k, v in pairs(new_values) do
    current_state[k] = v
  end
  handle:set("state", current_state)
end

---
-- state を完全にデフォルト値にリセットします。
function M.reset_state()
  get_handle():set("state", get_default_state())
end

---
-- ビューアが現在アクティブ（ウィンドウが有効）かどうかをチェックします。
-- @return boolean
function M.is_active()
  local s = M.get_state()
  return s.win and vim.api.nvim_win_is_valid(s.win)
end

-- このモジュールが読み込まれた時点で一度初期化を実行
M.init()

return M
