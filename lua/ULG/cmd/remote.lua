local unl_api = require("UNL.api")
local log = require("ULG.logger")

local M = {}

vim.cmd([[
  function! ULG_CompleteRemoteCommandsAPI_VimFunc(arglead, cmdline, cursorpos)
    return v:lua.require('ULG.buf.log.ue').get_remote_commands()
  endfunction
]])

function M.execute(opts)
  opts = opts or {}
  local conf = require("UNL.config").get("ULG")
  vim.ui.input({ prompt = "UE Remote Command: ", completion = "customlist,ULG_CompleteRemoteCommandsAPI_VimFunc" }, function(input)
    if not input or input == "" then return end
    unl_api.kismet_command({
      command = input, host = (conf.remote and conf.remote.host), port = (conf.remote and conf.remote.port),
      on_success = function() log.get().info("UE Command Sent: %s", input) end,
      on_error = function(err) log.get().error("UE Command Failed: %s", err) end,
    })
  end)
end

return M
