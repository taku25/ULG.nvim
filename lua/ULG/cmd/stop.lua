-- lua/ULG/cmd/stop.lua (索敵中断の実行部隊)

local buf_manager = require("ULG.buf")
local log = require("ULG.logger")
local M = {}

function M.execute()
  log.get().info("Stopping all log tailing.")
  buf_manager.stop_all_tailing() -- ★ 司令官の「索敵中断」命令を直接実行
end

return M
