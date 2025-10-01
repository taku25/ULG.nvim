-- lua/ULG/buf/log/general.lua (修正版)

local unl_log_engine = require("UNL.backend.buf.log")
local log = require("ULG.logger")
-- local tail = require("ULG.core.tail") -- REMOVE: 不要なrequire
local open_util = require("UNL.buf.open")

local M = {}
local handle = nil

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

function M.create_spec(conf)
  -- (この関数は変更なし)
  local keymaps = { ["q"] = "<cmd>lua require('ULG.api').close()<cr>" }
  local keymap_name_to_func = {
    jump_to_source = "open_file_from_log",
  }
  for name, key in pairs(conf.keymaps.general_log or {}) do
    local func_name = keymap_name_to_func[name]
    if func_name and key then
      keymaps[key] = string.format("<cmd>lua require('ULG.buf.log.general').%s()<cr>", func_name)
    end
  end
  return {
    id = "ulg_general_log",
    title = "[[ General Log ]]",
    filetype = "ulg-general-log",
    auto_scroll = true,
    keymaps = keymaps,
  }
end

---
-- 現在のカーソル行からファイルパスと行番号を抽出し、ファイルを開く
function M.open_file_from_log()
  local line = vim.api.nvim_get_current_line()
  
  -- vim.fn.matchlist用にVimの正規表現を定義
  -- 1. ファイルパス全体 / 2. 拡張子 / 3. 行番号 / 4. 桁番号(任意) をキャプチャ
  local pattern = [[\v([A-Z]:[\\/].*(cpp|h|c))\((\d+)(,\d+)?\)]]
  local result = vim.fn.matchlist(line, pattern)
  
  -- matchlistは成功すると空でないテーブルを返す
  if #result > 0 then
    -- result[1] = 全体マッチ
    -- result[2] = 1番目のキャプチャ(ファイルパス)
    -- result[3] = 2番目のキャプチャ(拡張子)
    -- result[4] = 3番目のキャプチャ(行番号)
    local filepath = result[2]
    local line_nr = tonumber(result[4])

    if vim.fn.filereadable(filepath) == 1 then
      require("UNL.buf.open").safe({ file_path = filepath, open_cmd = "edit", plugin_name = "ULG" })
      
      vim.schedule(function()
        vim.api.nvim_win_set_cursor(0, { line_nr, 0 })
      end)
    else
      vim.notify("File not found: " .. filepath, vim.log.levels.WARN)
    end
  else
    vim.notify("No file path found on this line.", vim.log.levels.INFO)
  end
end

-- (set_handle, set_title, clear_buffer, is_open, append_lines は変更なし)
function M.set_handle(h)
  handle = h
end
function M.set_title(title)
  if handle and handle:is_open() then
    vim.api.nvim_set_option_value("statusline", title, { win = handle:get_win_id() })
  end
end
function M.clear_buffer()
  if handle and handle:is_open() then
    vim.api.nvim_set_option_value("modifiable", true, { buf = handle._buf })
    vim.api.nvim_buf_set_lines(handle._buf, 0, -1, false, {})
    vim.api.nvim_set_option_value("modifiable", false, { buf = handle._buf })
  end
end
function M.is_open()
  return handle and handle:is_open()
end
function M.append_lines(lines)
  if not M.is_open() then return end
  if type(lines) == "string" then
    lines = { lines }
  end
  if #lines > 0 then
    handle:add_lines(lines)
  end
end

return M
