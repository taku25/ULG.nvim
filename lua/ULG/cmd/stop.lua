-- lua/ULG/cmd/stop.lua

local viewer = require("ULG.viewer")
local log = require("ULG.logger")

local M = {}

function M.execute()
  log.get().info("Stopping log viewer.")
  viewer.stop()
end

return M
