-- lua/ULG/context/view_state.lua
-- Manages the viewer's state using UNL.context

local unl_context = require("UNL.context")

-- Use a specific key within the "ULG" namespace
local state_handle = unl_context.use("ULG"):key("viewer_state")

local M = {}

local function get_default_state()
  return {
    master_buf = nil,
    view_buf = nil,
    win = nil,
    watcher = nil,
    filepath = nil,
    filter_query = nil,
    category_filters = {},
    filters_enabled = true,
    search_query = nil,
    search_hl_id = nil,
    line_queue = {},
    is_processing = false,
    help_win = nil,
    help_buf = nil,
    original_win = nil, -- The window to return to
    -- Pulled from config
    position = "bottom",
    vertical_size = 80,
    horizontal_size = 15,
    win_open_command = nil,
    filetype = "unreal-log",
    auto_scroll = true,
    polling_interval_ms = 500,
    render_chunk_size = 500,
    hide_timestamp = true,
    keymaps = {},
    help = {},
    highlights = {},
    is_watching = false
  }
end

-- Get the current state, or the default if it doesn't exist yet
function M.get_state()
  return state_handle:get("main") or get_default_state()
end

-- Update the state with new values
function M.update_state(new_values)
  if not new_values then return end
  local current_state = M.get_state()
  -- Merge the new values into the current state
  local updated = vim.tbl_deep_extend("force", current_state, new_values)
  state_handle:set("main", updated)
end

-- Reset the state to its default values
function M.reset_state()
  state_handle:set("main", get_default_state())
end

-- Initialize the state when the module is first loaded
M.reset_state()

return M
