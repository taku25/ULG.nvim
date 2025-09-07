-- lua/ULG/window/trace_help.lua (新規作成)

local unl_config = require("UNL.config")
-- ★ 参照先を config/help.lua の "trace" セクションにする
local help_lines_template = require("ULG.config.help").trace

local M = {}

-- このヘルプウィンドウの状態を管理するローカル変数
local help_win_info = {
    win = nil,
    buf = nil,
}

--- ヘルプウィンドウを閉じる
function M.close()
  if help_win_info.win and vim.api.nvim_win_is_valid(help_win_info.win) then
    vim.api.nvim_win_close(help_win_info.win, true)
  end
  if help_win_info.buf and vim.api.nvim_buf_is_valid(help_win_info.buf) then
    vim.api.nvim_buf_delete(help_win_info.buf, { force = true })
  end
  help_win_info.win, help_win_info.buf = nil, nil
end

--- ヘルプウィンドウを開く
function M.open()
  if help_win_info.win and vim.api.nvim_win_is_valid(help_win_info.win) then
    return
  end

  local conf = unl_config.get("ULG")
  -- ★ キーマップの参照先を conf.keymaps.trace にする
  local trace_keymaps = conf.keymaps.trace or {}
  
  local final_help_lines = {}
  for _, line in ipairs(help_lines_template) do
    table.insert(
      final_help_lines,
      (line:gsub("{([%w_]+)}", function(key) return trace_keymaps[key] or "N/A" end))
    )
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"; vim.bo[buf].bufhidden = "hide"; vim.bo[buf].swapfile = false
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, final_help_lines)
  vim.api.nvim_set_option_value("modifiable", false, { buf = buf })

  -- フローティングウィンドウの設定
  local width = math.floor(vim.o.columns * 0.8); if width > 80 then width = 80 end
  local height = #final_help_lines
  local row = math.floor((vim.o.lines - height) / 2 - 2)
  local col = math.floor((vim.o.columns - width) / 2)
  
  local win_opts = {
      relative = "editor", width = width, height = height, row = row, col = col,
      style = "minimal", border = (conf.help and conf.help.border) or "rounded"
  }

  local win = vim.api.nvim_open_win(buf, true, win_opts)
  help_win_info.win, help_win_info.buf = win, buf

  local close_cmd = "<cmd>lua require('ULG.window.help.trace').close()<cr>"
  local map_opts = { noremap = true, silent = true }
  vim.api.nvim_buf_set_keymap(buf, "n", "q", close_cmd, map_opts)
  vim.api.nvim_buf_set_keymap(buf, "n", "<Esc>", close_cmd, map_opts)
  vim.api.nvim_buf_set_keymap(buf, "n", "?", close_cmd, map_opts)
end

--- ヘルプウィンドウの表示/非表示を切り替える
function M.toggle()
  if help_win_info.win and vim.api.nvim_win_is_valid(help_win_info.win) then
    M.close()
  else
    M.open()
  end
end

return M
