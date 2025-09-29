-- lua/ULG/buf/log/general.lua (汎用ログビューアとしての最終版)

local unl_log_engine = require("UNL.backend.buf.log")
local log = require("ULG.logger")
local tail = require("ULG.core.tail")
local open_util = require("UNL.buf.open")

local M = {}
local handle = nil

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------
---
-- この汎用ビューアの仕様書(spec)を作成する
-- @param conf table プラグインの設定テーブル
-- @return table UNL.backend.buf.log.createに渡すためのspec
function M.create_spec(conf)

  local keymaps = { ["q"] = "<cmd>lua require('ULG.api').close()<cr>" }
  local keymap_name_to_func = {
    jump_to_source = "open_file_from_log",
  }
  
  -- 2. ユーザー設定 (conf.keymaps.general_log) をループしてキーマップを構築
  -- "general_log" という新しいセクションを読むようにします
  for name, key in pairs(conf.keymaps.general_log or {}) do
    local func_name = keymap_name_to_func[name]
    if func_name and key then
      -- ★★★ 呼び出すモジュールを 'ulg.actions' に変更 ★★★
      keymaps[key] = string.format("<cmd>lua require('ULG.buf.log.general').%s()<cr>", func_name)
    end
  end

  return {
    id = "ulg_general_log", -- IDを汎用的な名前に
    title = "[[ General Log ]]", -- タイトルは通常、set_titleで上書きされる
    filetype = "ulg-general-log", -- 汎用的な"log"ファイルタイプ
    auto_scroll = true,
    keymaps = keymaps,
  }
end


---
-- ★★★ ここにアクション関数を移動 ★★★
-- 現在のカーソル行からファイルパスと行番号を抽出し、ファイルを開く
function M.open_file_from_log()
  local line = vim.api.nvim_get_current_line()
  local filepath, line_nr, col_nr
  local result = vim.fn.matchlist(line, [[\v([A-Z]:[\\/].*(cpp|h|c))\((\d+),(\d+)\)]])
  if #result >= 4 then
    filepath = result[2]
    line_nr = tonumber(result[4])
    col_nr = tonumber(result[5])
  end
  line_nr = line_nr or 1 
  if filepath and line_nr then
    if vim.fn.filereadable(filepath) == 1 then
    
      open_util.safe({ file_path = filepath, open_cmd = "edit", plugin_name = "ULG" })
      -- require("UNL.buf.open").safe({})
      -- vim.cmd("edit " .. vim.fn.fnameescape(filepath))
      --
      vim.schedule(function()
        vim.api.nvim_win_set_cursor(0, { tonumber(line_nr), 0 })
      end);
    else
    end
  else
  end
end

---
-- 司令官から、このモジュールが操作すべきハンドルを受け取る
-- @param h table ウィンドウハンドル
function M.set_handle(h)
  handle = h
end

---
-- ウィンドウのタイトルを動的に変更する
-- @param title string 新しいタイトル
function M.set_title(title)
  if handle and handle:is_open() then
    vim.api.nvim_set_option_value("statusline", title, { win = handle:get_win_id() })
  end
end

---
-- バッファの内容を全てクリアする
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


-- 行をバッファに追記する
-- @param lines string | string[]
function M.append_lines(lines)
  if not M.is_open() then return end

  if type(lines) == "string" then
    lines = { lines }
  end
  if #lines > 0 then
    -- handleが持つAPIを呼び出して行を追加
    handle:add_lines(lines)
  end
end

return M
