-- lua/ULG/window/help/ue.lua (ステートマネージャー対応版)

local unl_config = require("UNL.config")
local help_lines_template = require("ULG.config.help")
local view_state = require("ULG.context.view_state") -- 位置計算のために必要
local window_state = require("ULG.context.window_state") -- 自身の状態管理のため

local M = {}

--- ヘルプウィンドウを閉じる
function M.close()
  local s = window_state.get_state("help_ue")
  if s.win and vim.api.nvim_win_is_valid(s.win) then
    vim.api.nvim_win_close(s.win, true)
  end
  if s.buf and vim.api.nvim_buf_is_valid(s.buf) then
    vim.api.nvim_buf_delete(s.buf, { force = true })
  end
  window_state.reset_state("help_ue")
end

--- ヘルプウィンドウを開く
function M.open()
  local s = window_state.get_state("help_ue")
  if s.win and vim.api.nvim_win_is_valid(s.win) then
    return
  end

  local conf = unl_config.get("ULG")
  local final_help_lines = {}
  for _, line in ipairs(help_lines_template.ue) do
    table.insert(
      final_help_lines,
      (line:gsub("{([%w_]+)}", function(key) return (conf.keymaps and conf.keymaps.log[key]) or "N/A" end))
    )
  end

  local help_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[help_buf].buftype = "nofile"
  vim.bo[help_buf].bufhidden = "hide"
  vim.bo[help_buf].swapfile = false
  vim.api.nvim_buf_set_lines(help_buf, 0, -1, false, final_help_lines)
  vim.api.nvim_set_option_value("modifiable", false, { buf = help_buf })

  -- メインのログビューの状態を取得して、ウィンドウ位置を計算
  local ue_log_s = view_state.get_state("ue_log_view")
  local log_win_id = ue_log_s and ue_log_s.handle and ue_log_s.handle:get_win_id()

  local win_opts = { style = "minimal", border = (conf.help and conf.help.border) or "rounded" }
  local height = #final_help_lines

  if log_win_id and vim.api.nvim_win_is_valid(log_win_id) then
    local log_win_width = vim.api.nvim_win_get_width(log_win_id)
    local log_win_height = vim.api.nvim_win_get_height(log_win_id)
    local width = math.min(math.floor(log_win_width * 0.9), 80)
    win_opts.relative = "win"
    win_opts.win = log_win_id
    win_opts.width = width
    win_opts.height = height
    win_opts.row = math.floor((log_win_height - height) / 2)
    win_opts.col = math.floor((log_win_width - width) / 2)
  else
    local width = math.min(math.floor(vim.o.columns * 0.8), 80)
    win_opts.relative = "editor"
    win_opts.width = width
    win_opts.height = height
    win_opts.row = math.floor((vim.o.lines - height) / 2 - 2)
    win_opts.col = math.floor((vim.o.columns - width) / 2)
  end

  local help_win = vim.api.nvim_open_win(help_buf, true, win_opts)
  
  -- 自身の状態を更新
  window_state.update_state("help_ue", { win = help_win, buf = help_buf })

  local close_cmd = "<cmd>lua require('ULG.window.help.ue').close()<cr>"
  local map_opts = { noremap = true, silent = true }
  vim.api.nvim_buf_set_keymap(help_buf, "n", "q", close_cmd, map_opts)
  vim.api.nvim_buf_set_keymap(help_buf, "n", "<Esc>", close_cmd, map_opts)
  vim.api.nvim_buf_set_keymap(help_buf, "n", "?", close_cmd, map_opts)
  vim.api.nvim_buf_set_keymap(help_buf, "n", "<CR>", close_cmd, map_opts)
end

--- ヘルプウィンドウの表示/非表示を切り替える
function M.toggle()
  local s = window_state.get_state("help_ue")
  if s.win and vim.api.nvim_win_is_valid(s.win) then
    M.close()
  else
    M.open()
  end
end

return M
