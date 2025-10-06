-- lua/ULG/window/help/trace.lua (ステートマネージャー対応版)

local unl_config = require("UNL.config")
local help_lines_template = require("ULG.config.help").trace
local window_state = require("ULG.context.window_state") -- 自身の状態管理のため

local M = {}

--- ヘルプウィンドウを閉じる
function M.close()
  local s = window_state.get_state("help_trace")
  if s.win and vim.api.nvim_win_is_valid(s.win) then
    vim.api.nvim_win_close(s.win, true)
  end
  if s.buf and vim.api.nvim_buf_is_valid(s.buf) then
    vim.api.nvim_buf_delete(s.buf, { force = true })
  end
  window_state.reset_state("help_trace")
end

--- ヘルプウィンドウを開く
function M.open()
  local s = window_state.get_state("help_trace")
  if s.win and vim.api.nvim_win_is_valid(s.win) then
    return
  end

  local conf = unl_config.get("ULG")
  local trace_keymaps = conf.keymaps.trace or {}
  
  local final_help_lines = {}
  for _, line in ipairs(help_lines_template) do
    table.insert(
      final_help_lines,
      (line:gsub("{([%w_]+)}", function(key) return trace_keymaps[key] or "N/A" end))
    )
  end

  local help_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[help_buf].buftype = "nofile"; vim.bo[help_buf].bufhidden = "hide"; vim.bo[help_buf].swapfile = false
  vim.api.nvim_buf_set_lines(help_buf, 0, -1, false, final_help_lines)
  vim.api.nvim_set_option_value("modifiable", false, { buf = help_buf })

  local width = math.floor(vim.o.columns * 0.8); if width > 80 then width = 80 end
  local height = #final_help_lines
  local row = math.floor((vim.o.lines - height) / 2 - 2)
  local col = math.floor((vim.o.columns - width) / 2)
  
  local win_opts = {
      relative = "editor", width = width, height = height, row = row, col = col,
      style = "minimal", border = (conf.help and conf.help.border) or "rounded"
  }

  local help_win = vim.api.nvim_open_win(help_buf, true, win_opts)
  
  -- 自身の状態を更新
  window_state.update_state("help_trace", { win = help_win, buf = help_buf })

  local close_cmd = "<cmd>lua require('ULG.window.help.trace').close()<cr>"
  local map_opts = { noremap = true, silent = true }
  vim.api.nvim_buf_set_keymap(help_buf, "n", "q", close_cmd, map_opts)
  vim.api.nvim_buf_set_keymap(help_buf, "n", "<Esc>", close_cmd, map_opts)
  vim.api.nvim_buf_set_keymap(help_buf, "n", "?", close_cmd, map_opts)
end

--- ヘルプウィンドウの表示/非表示を切り替える
function M.toggle()
  local s = window_state.get_state("help_trace")
  if s.win and vim.api.nvim_win_is_valid(s.win) then
    M.close()
  else
    M.open()
  end
end

return M
