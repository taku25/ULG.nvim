
local builder = require("UNL.command.builder")
local api = require("ULG.api")

builder.create({
  plugin_name = "ULG",
  cmd_name = "ULG",
  desc = "ULG: Unreal Log Viewer commands",
  subcommands = {
    ["start"] = {
      handler = function(opts) api.start(opts) end,
      desc = "Start tailing a log file. Use 'start!' to pick a file.",
      bang = true,
      args = {},
    },
    --- ★★★ このサブコマンドを追加 ★★★
    ["stop"] = {
      handler = function() api.stop() end,
      desc = "Stop tailing log files, but keep windows open.",
      args = {},
    },
    ["close"] = {
      handler = function() api.close() end,
      desc = "Stop tailing and close all log viewer windows.",
      args = {},
    },
  },
})
