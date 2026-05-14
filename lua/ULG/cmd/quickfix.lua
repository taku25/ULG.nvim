-- lua/ULG/cmd/quickfix.lua
-- ビルドログ / UE ログのエラー・警告行を Quickfix リストに投入する

local log = require("ULG.logger")
local view_state = require("ULG.context.view_state")

local M = {}

-- MSVC:  C:\path\file.cpp(10): error C2065: ...
-- UBT:   ERROR: something failed
local ERROR_PATTERN   = [[\v([A-Za-z]:[/\\][^()]+)\((\d+)\):\s*(error\s+\w+:.+)]]
local WARNING_PATTERN = [[\v([A-Za-z]:[/\\][^()]+)\((\d+)\):\s*(warning\s+\w+:.+)]]

local function parse_line(line)
  -- ファイルパス付きエラー
  local result = vim.fn.matchlist(line, ERROR_PATTERN)
  if #result > 0 then
    return { filename = result[2], lnum = tonumber(result[3]) or 1, col = 1,
             type = "E", text = vim.trim(result[4]) }
  end
  result = vim.fn.matchlist(line, WARNING_PATTERN)
  if #result > 0 then
    return { filename = result[2], lnum = tonumber(result[3]) or 1, col = 1,
             type = "W", text = vim.trim(result[4]) }
  end
  -- ファイルパスなし ERROR:/WARNING: 行
  if line:match("^ERROR%s*:") then
    return { filename = "", lnum = 1, col = 1, type = "E", text = vim.trim(line) }
  end
  if line:match("^WARNING%s*:") then
    return { filename = "", lnum = 1, col = 1, type = "W", text = vim.trim(line) }
  end
  return nil
end

local function collect_from_buf(buf_id)
  if not (buf_id and vim.api.nvim_buf_is_valid(buf_id)) then return {} end
  local lines = vim.api.nvim_buf_get_lines(buf_id, 0, -1, false)
  local items = {}
  for _, line in ipairs(lines) do
    local item = parse_line(line)
    if item then table.insert(items, item) end
  end
  return items
end

function M.execute()
  local items = {}

  -- general_log (ビルドログ) を優先
  local gs = view_state.get_state("general_log_view")
  if gs and gs.handle then
    local buf_id = gs.handle._buf
    local found = collect_from_buf(buf_id)
    vim.list_extend(items, found)
  end

  -- UE ログからも補完
  local us = view_state.get_state("ue_log_view")
  if us and us.handle and us.handle:is_open() then
    local win_id = us.handle:get_win_id()
    if win_id and vim.api.nvim_win_is_valid(win_id) then
      local buf_id = vim.api.nvim_win_get_buf(win_id)
      local found = collect_from_buf(buf_id)
      vim.list_extend(items, found)
    end
  end

  if #items == 0 then
    log.get().info("No errors or warnings found in log buffers.")
    return
  end

  vim.fn.setqflist({}, "r", { title = "ULG Diagnostics", items = items })
  vim.cmd("copen")
  log.get().info("Quickfix populated: %d item(s).", #items)
end

return M
