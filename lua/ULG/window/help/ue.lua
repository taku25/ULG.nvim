-- lua/ULG/window/help.lua
-- ヘルプウィンドウの表示に特化したUIコンポーネント

local view_state = require("ULG.context.view_state")
local help_lines_template = require("ULG.config.help")
local unl_config = require("UNL.config")

local M = {}

--- ヘルプウィンドウを閉じる
function M.close()
  local s = view_state.get_state()
  if s.help_win and vim.api.nvim_win_is_valid(s.help_win) then
    vim.api.nvim_win_close(s.help_win, true)
  end
  if s.help_buf and vim.api.nvim_buf_is_valid(s.help_buf) then
    vim.api.nvim_buf_delete(s.help_buf, { force = true })
  end
  view_state.update_state({ help_win = nil, help_buf = nil })
end

--- ヘルプウィンドウを開く
function M.open()
  local s = view_state.get_state()
  if s.help_win and vim.api.nvim_win_is_valid(s.help_win) then
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

  -- ★★★ ここからがウィンドウ位置計算の修正箇所です ★★★

  local log_win_id = s.win
  local win_opts = { style = "minimal", border = (conf.help and conf.help.border) or "rounded" }

  local height = #final_help_lines

  if log_win_id and vim.api.nvim_win_is_valid(log_win_id) then
    -- ログウィンドウが有効な場合、その上に中央表示する
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
    -- フォールバック：エディタ全体の中央に表示
    local width = math.min(math.floor(vim.o.columns * 0.8), 80)
    win_opts.relative = "editor"
    win_opts.width = width
    win_opts.height = height
    win_opts.row = math.floor((vim.o.lines - height) / 2 - 2)
    win_opts.col = math.floor((vim.o.columns - width) / 2)
  end

  -- ★★★ 修正箇所ここまで ★★★

  local help_win = vim.api.nvim_open_win(help_buf, true, win_opts)
  view_state.update_state({ help_win = help_win, help_buf = help_buf })

  local close_cmd = "<cmd>lua require('ULG.window.help').close()<cr>"
  local map_opts = { noremap = true, silent = true }
  vim.api.nvim_buf_set_keymap(help_buf, "n", "q", close_cmd, map_opts)
  vim.api.nvim_buf_set_keymap(help_buf, "n", "<Esc>", close_cmd, map_opts)
  vim.api.nvim_buf_set_keymap(help_buf, "n", "?", close_cmd, map_opts)
  vim.api.nvim_buf_set_keymap(help_buf, "n", "<CR>", close_cmd, map_opts)
end

--- ヘルプウィンドウの表示/非表示を切り替える
function M.toggle()
  local s = view_state.get_state()
  if s.help_win and vim.api.nvim_win_is_valid(s.help_win) then
    M.close()
  else
    M.open()
  end
end

return M
