
-- UEP/lua/UEP/event/hub.lua
-- UEPプラグイン内のイベントを仲介するハブ (Mediator)。
-- 責務:
-- 1. データ層のイベント (キャッシュ更新) をリッスンする。
-- 2. UI層のイベント (neo-treeの準備完了) をリッスンする。
-- 3. コマンド層からのUI更新リクエストを受け付ける。
-- 4. 状態を賢く管理し、適切なタイミングでUI層にモデル更新イベントを発行する。

local unl_events = require("UNL.event.events")
local unl_event_types = require("UNL.event.types")
local log = require("ULG.logger").get()

-- --- 内部状態 ---
-- UI (neo-tree-uproject) がイベントを購読する準備ができたか
local ui_component_is_ready = false
-- UIの準備ができる前にリクエストされた、保留中のツリーデータ
local pending_event_data = nil

local M = {}


---
-- UIコンポーネント (neo-tree-uproject) の準備が完了したときに呼ばれるコールバック
local function on_ui_component_ready()
  log.info("Event hub: Detected that UI component 'neo-tree-uproject' is ready.")
  ui_component_is_ready = true
  -- もし、UIの準備ができる前に発行がリクエストされたデータが保留されていれば、
  -- まさにこのタイミングで発行する
  if pending_event_data then
    log.info("Hub: UI is now ready, publishing pending tree data.")

    unl_events.publish(unl_event_types.ON_REQUEST_TRACE_CALLEES_VIEW, pending_event_data)
    pending_event_data = nil
  end
end

---

-- プラグイン初期化時に一度だけ呼ばれ、すべてのイベント購読を開始する
local is_subscribed = false
function M.setup()
  if is_subscribed then return end

  unl_events.subscribe(unl_event_types.ON_REQUEST_TRACE_CALLEES_VIEW, function(event_data)
    if ui_component_is_ready == false then
      pending_event_data = event_data
    end
  end)

  unl_events.subscribe(unl_event_types.ON_PLUGIN_AFTER_SETUP, function(plugin_info)
    if plugin_info and plugin_info.name == "neo-tree-unl-insights" then
      on_ui_component_ready()
    end
  end)

  is_subscribed = true
  log.info("ULG event hub initialized and subscribed to global events.")
end

return M
