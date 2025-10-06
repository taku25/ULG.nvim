-- lua/ULG/context/view_state.lua (ステートマネージャーとして再構築)

local unl_context = require("UNL.context")

local M = {}

-- UNL.contextを使って状態を永続化するためのハンドル
local context_handle = unl_context.use("ULG"):key("view_state_v2")

-- 内部で全ての状態を保持するテーブル
local _state_data = {}
local _default_states = {}

-- 状態モジュールを登録する内部関数
local function register_state(name, defaults_path)
  local defaults = require(defaults_path)
  _default_states[name] = defaults
  _state_data[name] = vim.deepcopy(defaults) -- 初回はデフォルト値をコピー
end

-- プラグイン起動時に全ての状態モジュールを初期化する
function M.setup()
  _state_data = {}
  _default_states = {}
  
  -- 各状態モジュールを登録
  register_state("ULG", "ULG.context.ulg_context_defaults")
  register_state("general_log_view", "ULG.context.general_log_view_context_defaults")
  register_state("ue_log_view", "ULG.context.ue_log_view_context_defaults")
  register_state("trace_log_view", "ULG.context.trace_log_view_context_defaults")

  -- UNL.contextから保存されたデータを読み込み、デフォルト値とマージ
  local loaded_data = context_handle:get("main")
  if loaded_data then
    _state_data = vim.tbl_deep_extend("force", _state_data, loaded_data)
  end
end

-- 状態をUNL.contextに保存する
local function save_all_states()
  context_handle:set("main", _state_data)
end

--- 指定したモジュールの状態を取得する
-- @param name string 状態モジュールの名前 (e.g., "ue_log_view")
-- @return table|nil そのモジュールの現在の状態テーブル
function M.get_state(name)
  return _state_data[name]
end

--- 指定したモジュールの状態を更新する
-- @param name string 状態モジュールの名前
-- @param new_values table 更新したい値を含むテーブル
function M.update_state(name, new_values)
  if not _state_data[name] or not new_values then return end
  
  _state_data[name] = vim.tbl_deep_extend("force", _state_data[name], new_values)
  save_all_states() -- 更新があるたびに保存
end

--- 指定したモジュールの状態をデフォルト値にリセットする
-- @param name string 状態モジュールの名前
function M.reset_state(name)
  if _default_states[name] then
    _state_data[name] = vim.deepcopy(_default_states[name])
    save_all_states()
  end
end

--- 全ての状態をデフォルト値にリセットする
function M.reset_all_states()
  for name, defaults in pairs(_default_states) do
    _state_data[name] = vim.deepcopy(defaults)
  end
  save_all_states()
end

-- モジュールが読み込まれた時に初期化を実行
M.setup()

return M
