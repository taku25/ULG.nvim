-- lua/ULG/buf/log/build.lua (ハンドル設定関数を追加した最終版)

local unl_log_engine = require("UNL.backend.buf.log")
local log = require("ULG.logger")
local tail = require("ULG.core.tail")

local M = {}
local handle, tailer -- この handle は、set_handle を通じて外部から設定される

-- Keymap Callback (変更なし)
function M.jump_to_error()
  if not (handle and handle:is_open()) then return end
  local line = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(handle:get_win_id()), vim.api.nvim_win_get_cursor(handle:get_win_id())[1] - 1, vim.api.nvim_win_get_cursor(handle:get_win_id())[1], false)[1]
  if not line then return end
  local filepath, lnum = line:match('^%s*([A-Za-z]:[\\/].-%.%w+)%((%d+)%)')
  if filepath and lnum then vim.cmd("edit +" .. lnum .. " " .. vim.fn.fnameescape(filepath))
  else log.get().info("No source location found on this build log line.") end
end

-- Module Public API
function M.create_spec(conf)
  return {
    id = "build_log",
    title = "[[ UBT Build LOG ]]",
    filetype = "ubt-log",
    auto_scroll = true,
    keymaps = {
      ["q"] = "<cmd>lua require('ULG.api').close()<cr>",
      ["<CR>"] = "<cmd>lua require('ULG.buf.log.build').jump_to_error()<cr>",
    },
  }
end

-- ★★★ 新設：情報伝達路 ★★★
-- 司令官から、このモジュールが操作すべきハンドルを受け取る
function M.set_handle(h)
  handle = h
end

function M.start_tailing(filepath)
  if not (handle and handle:is_open()) then
    log.get().info("Build log window is not open. Cannot start tailing.")
    return 
  end
  
  if tailer then tailer:stop() end

  -- バッファをクリア
  vim.api.nvim_set_option_value("modifiable", true, { buf = handle._buf })
  vim.api.nvim_buf_set_lines(handle._buf, 0, -1, false, {})
  vim.api.nvim_set_option_value("modifiable", false, { buf = handle._buf })

  local conf = require("UNL.config").get("ULG")
  
  -- 新しくなった tail.start を呼び出す
  tailer = tail.start(filepath, conf.polling_interval_ms or 200, function(new_lines, is_initial)
    -- is_initial フラグはここでは使わないが、将来的に利用可能
    handle:add_lines(new_lines)
  end)
end

-- stop と toggle も、set_handle で設定された handle を使うので、自動的に正しく動作する
function M.stop_tailing()
  if tailer then
    tailer:stop()
    tailer = nil
    log.get().debug("Build log tailer stopped.")
  end
end

-- ★★★ stopをcloseに改名し、責務を明確化 ★★★
function M.close()
  M.stop_tailing() -- 閉じる前に必ずtailingを止める
  if handle and handle:is_open() then
    handle:close()
    handle = nil
  end
end

function M.toggle()
  if handle and handle:is_open() then M.stop() else M.open() end
end

return M
