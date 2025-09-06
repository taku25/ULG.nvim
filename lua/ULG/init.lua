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

  -- -- Setup a global autocmd to always track the last window
  -- vim.cmd("augroup ULGWindowEventsGlobal")
  -- vim.cmd("autocmd!")
  -- vim.api.nvim_create_autocmd("BufEnter", {
  --   group = "ULGWindowEventsGlobal",
  --   pattern = "*",
  --   callback = function()
  --     -- Lazily require to avoid circular dependencies and performance hit
  --     local view_state = require("ULG.context.view_state")
  --     local s = view_state.get_state()
  --     local current_win_id = vim.api.nvim_get_current_win()
  --     
  --     -- Only update if the log window exists and the new window is different
  --     if s.win and vim.api.nvim_win_is_valid(s.win) and current_win_id ~= s.win then
  --       view_state.update_state({ original_win = current_win_id })
  --     end
  --   end,
  -- })
  -- vim.cmd("augroup END")

  if log then
    log.debug("ULG.nvim setup complete.")
  end
  setup_done = true
end

return M
