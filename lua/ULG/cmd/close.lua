-- lua/ULG/cmd/close.lua (新設・帰投の実行部隊)

local buf_manager = require("ULG.buf")
local log = require("ULG.logger")
local M = {}

function M.execute()
  log.get().info("Closing all log viewers.")
  buf_manager.close_console() -- ★ 司令官の「帰投」命令を直接実行
end

return M
