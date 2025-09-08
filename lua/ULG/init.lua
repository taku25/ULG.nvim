local unl_log = require("UNL.logging")
local ulg_defaults = require("ULG.config.defaults")

local M = {}

local setup_done = false

function M.setup(user_opts)
  if setup_done then return end

  unl_log.setup("ULG", ulg_defaults, user_opts or {})
  local log = unl_log.get("ULG")


  local buf_manager = require("ULG.buf")
  buf_manager.setup()

  if log then
    log.debug("ULG.nvim setup complete.")
  end
  
  require("ULG.event.hub").setup()

  setup_done = true
end

return M
