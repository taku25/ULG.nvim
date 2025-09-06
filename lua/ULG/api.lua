-- lua/ULG/api.lua (修正版)

local start_cmd = require("ULG.cmd.start")
local stop_cmd = require("ULG.cmd.stop") -- ★ stop_cmdをrequire
local close_cmd = require("ULG.cmd.close") -- ★ stop_cmdをrequire

local M = {}

function M.start(opts)
  start_cmd.execute(opts)
end

function M.stop()
  stop_cmd.execute() -- ★ stop_cmd.execute()を呼び出す
end

function M.close()
  close_cmd.execute() -- ★ stop_cmd.execute()を呼び出す
end

return M
