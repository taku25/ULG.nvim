-- lua/ULG/cmd/save.lua
-- 現在の UE ログバッファ内容（フィルター適用後）をファイルに書き出す

local log = require("ULG.logger")
local view_state = require("ULG.context.view_state")

local M = {}

function M.execute(opts)
  opts = opts or {}

  local s = view_state.get_state("ue_log_view")
  if not (s.handle and s.handle:is_open()) then
    log.get().warn("ULG log window is not open.")
    return
  end

  local win_id = s.handle:get_win_id()
  if not (win_id and vim.api.nvim_win_is_valid(win_id)) then
    log.get().warn("ULG log window is not valid.")
    return
  end

  local buf_id = vim.api.nvim_win_get_buf(win_id)
  local lines = vim.api.nvim_buf_get_lines(buf_id, 0, -1, false)

  if #lines == 0 then
    log.get().info("Log buffer is empty, nothing to save.")
    return
  end

  local function write_to(filepath)
    local ok, err = pcall(vim.fn.writefile, lines, filepath)
    if ok then
      log.get().info("Log saved to: %s (%d lines)", filepath, #lines)
    else
      log.get().error("Failed to save log: %s", tostring(err))
    end
  end

  if opts.filepath and opts.filepath ~= "" then
    write_to(opts.filepath)
  else
    -- ファイルパスが指定されていなければ入力を求める
    local default = vim.fn.expand("%:p:h") .. "/ulg_export.log"
    vim.ui.input({ prompt = "Save log to: ", default = default }, function(input)
      if input and input ~= "" then
        write_to(input)
      end
    end)
  end
end

return M
