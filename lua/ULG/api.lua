-- lua/ULG/api.lua (修正版)

local start_cmd = require("ULG.cmd.start")
local stop_cmd = require("ULG.cmd.stop") -- ★ stop_cmdをrequire
local close_cmd = require("ULG.cmd.close") -- ★ stop_cmdをrequire
local trace_cmd = require("ULG.cmd.trace") -- ★ stop_cmdをrequire
local crash_cmd = require("ULG.cmd.crash") -- 追加
local remote_cmd = require("ULG.cmd.remote") -- 追加

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
function M.trace(opts)
  trace_cmd.execute(opts)
end
function M.crash() -- 追加
  crash_cmd.execute()
end
function M.remote(opts) -- 追加
  remote_cmd.execute(opts)
end

function M.remote_command(command) -- 追加
  remote_cmd.execute_command(command)
end
return M
