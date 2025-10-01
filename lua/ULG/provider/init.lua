-- lua/ULG/provider/init.lua

local unl_log = require("UNL.logging")
local log = require("ULG.logger")
-- ★司令官である buf/init.lua を buf_manager としてrequire
local buf_manager = require("ULG.buf")

local M = {}

M.setup = function()
  local unl_api_ok, unl_api = pcall(require, "UNL.api")
  if unl_api_ok then
    -- 1. 既存のTraceプロバイダー (変更なし)
    local trace_provider = require("ULG.provider.trace")
    unl_api.provider.register({
      capability = "ulg.get_pending_trace_request",
      name = "ULG.nvim",
      impl = trace_provider,
    })

    -- 2. Build Logプロバイダー
    unl_api.provider.register({
      capability = "ulg.build_log",
      name = "ULG.nvim",
      impl = {
        -- UBTから通知が来たら、buf_managerにそのまま渡す
        notify = function(opts)
          buf_manager.display_ubt_log(opts)
        end,
      },
    })

    log.get().info("Registered ULG providers to UNL.nvim.")
  end
end

return M
