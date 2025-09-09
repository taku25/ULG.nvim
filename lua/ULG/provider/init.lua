-- lua/ULG/provider/init.lua (新規作成)
local unl_log = require("UNL.logging")
local log = require("ULG.logger")

local M = {}

M.setup = function()
  local unl_api_ok, unl_api = pcall(require, "UNL.api")
  if unl_api_ok then
    local trace_provider = require("ULG.provider.trace")
    unl_api.provider.register({
      capability = "ulg.get_pending_trace_request",
      name = "ULG.nvim",
      impl = trace_provider, 
    })
    log.get().info("Registered ULG providers to UNL.nvim.")
  end
end

return M
