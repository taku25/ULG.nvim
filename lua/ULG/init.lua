local unl_log = require("UNL.logging")
local ubt_defaults = require("ULG.config.defaults")

local M = {}

function M.setup(user_opts)
  unl_log.setup("ULG", ubt_defaults, user_opts or {})
  local log = unl_log.get("ULG")
  if log then
    log.debug("ULG.nvim setup complete.")
  end
end

return M
