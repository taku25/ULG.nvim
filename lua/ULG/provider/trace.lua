local unl_context = require("UNL.context")
local ulg_log = require("ULG.logger").get()

local M = {}

-- capability: "ulg.get_pending_trace_request"
function M.get_pending_trace_request(opts)
  local consumer_id = (opts and opts.consumer) or "unknown"
  ulg_log.debug("Provider 'get_pending_trace_request' called by: %s", consumer_id)
  local handle = unl_context.use("ULG"):key("pending_request:" .. consumer_id)
  local payload = handle:get("payload")
  if payload then
    ulg_log.info("Found and returning pending trace request for %s.", consumer_id)
    handle:del("payload") -- 一度渡したら削除
    return payload
  else
    return nil
  end
end

-- このプロバイダーは今のところ、保留中リクエストを返すだけ
function M.request(opts)
  if opts and opts.capability == "ulg.get_pending_trace_request" then
    return M.get_pending_trace_request(opts)
  else
    ulg_log.warn("Unknown request to ULG trace provider: %s", vim.inspect(opts))
    return nil
  end
end

return M
