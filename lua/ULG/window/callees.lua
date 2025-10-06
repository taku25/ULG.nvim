-- lua/ULG/window/callees.lua (ステートマネージャー対応版)

local window_state = require("ULG.context.window_state")

local M = {}

local function format_events_to_lines(events, depth)
  depth = depth or 0
  local lines = {}
  local indent = string.rep("  ", depth)
  for _, event in ipairs(events) do
    local duration_ms = (event.e - event.s) * 1000
    local line = string.format("%s> %s (%.3fms)", indent, event.name or "Unknown", duration_ms)
    table.insert(lines, line)
    if event.children and #event.children > 0 then
      vim.list_extend(lines, format_events_to_lines(event.children, depth + 1))
    end
  end
  return lines
end

function M.open(frame_data)
  local s = window_state.get_state("callees")
  if s.win and vim.api.nvim_win_is_valid(s.win) then
    vim.api.nvim_set_current_win(s.win)
    return
  end

  local lines = format_events_to_lines(frame_data.events_tree)
  
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "ulg-trace"

  vim.api.nvim_set_option_value("modifiable", true, { buf = buf })
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_set_option_value("modifiable", false, { buf = buf })

  local width = math.floor(vim.o.columns * 0.8)
  local height = math.floor(vim.o.lines * 0.8)
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor", width = width, height = height,
    row = row, col = col, style = "minimal", border = "rounded",
  })
  
  -- 状態を更新
  window_state.update_state("callees", { win = win, buf = buf })
  
  vim.api.nvim_buf_set_keymap(buf, "n", "q", "", {
    noremap = true, silent = true,
    callback = function()
      local current_s = window_state.get_state("callees")
      if current_s.win and vim.api.nvim_win_is_valid(current_s.win) then
        vim.api.nvim_win_close(current_s.win, true)
      end
      -- 状態をリセット
      window_state.reset_state("callees")
    end
  })
end

return M
