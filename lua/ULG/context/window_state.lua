-- lua/ULG/window/state.lua (新規作成)

local unl_context = require("UNL.context")

local M = {}

-- UNL.contextを使って状態を永続化するためのハンドル
local context_handle = unl_context.use("ULG"):key("window_state_v1")

-- 内部で全ての状態を保持するテーブル
local _state_data = {}
local _default_states = {}

-- 状態モジュールを登録する内部関数
local function register_state(name, defaults_path)
  local defaults = require(defaults_path)
  _default_states[name] = defaults
  _state_data[name] = vim.deepcopy(defaults)
end

-- プラグイン起動時に全ての状態モジュールを初期化する
function M.setup()
  _state_data = {}
  _default_states = {}
  
  -- 各状態モジュールを登録
  register_state("gantt_chart", "ULG.context.window.gantt_chart_defaults")
  register_state("callees", "ULG.context.window.callees_defaults")
 
  register_state("help_ue", "ULG.context.window.help.ue_defaults")
  register_state("help_trace", "ULG.context.window.help.trace_defaults")

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
function M.get_state(name)
  return _state_data[name]
end

--- 指定したモジュールの状態を更新する
function M.update_state(name, new_values)
  if not _state_data[name] or not new_values then return end
  
  _state_data[name] = vim.tbl_deep_extend("force", _state_data[name], new_values)
  save_all_states()
end

--- 指定したモジュールの状態をデフォルト値にリセットする
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

return M
