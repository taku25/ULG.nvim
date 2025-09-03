local M = {}
local unl_logging
local function create_dummy_logger()
  vim.notify("[ULG.nvim] Logger not initialized, using fallback.", vim.log.levels.WARN)
  return {
    notify = function(msg, level)
      local lvl = vim.log.levels[(level:upper())] or vim.log.levels.INFO
      vim.notify("[ULG] " .. tostring(msg), lvl)
    end,
    info = function() end, warn = function() end, error = function() end,
    debug = function() end, trace = function() end,
  }
end

M.name = "ULG"
M.get = function()
  if not unl_logging then unl_logging = require("UNL.logging") end
  local logger = unl_logging.get(M.name)
  if logger then return logger end
  return create_dummy_logger()
end

return M
