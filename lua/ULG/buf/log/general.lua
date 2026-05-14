-- lua/ULG/buf/log/general.lua (ステートマネージャー対応版)

local log = require("ULG.logger")
local view_state = require("ULG.context.view_state")

local M = {}

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

-- Error/Warning フィルターの状態 (バッファごと)
local filter_state = {
  enabled = false,
  original_lines = nil, -- フィルター有効化時に元行を保存
}

local ERROR_PAT   = [[\v[Ee]rror[: ]|\[ERROR\]|^ERROR]]
local WARNING_PAT = [[\v[Ww]arning[: ]|\[WARNING\]|^WARNING]]

function M.create_spec(conf)
  local keymaps = { ["q"] = "<cmd>lua require('ULG.api').close()<cr>" }
  local keymap_name_to_func = {
    jump_to_source       = "open_file_from_log",
    send_to_quickfix     = "send_to_quickfix",
    toggle_error_filter  = "toggle_error_filter",
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

function M.open_file_from_log()
  local line = vim.api.nvim_get_current_line()
  local pattern = [[\v([A-Z]:[\\/].*(cpp|h|c))\((\d+)(,\d+)?\)]]
  local result = vim.fn.matchlist(line, pattern)
  if #result > 0 then
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

function M.set_title(title)
  local s = view_state.get_state("general_log_view")
  if s.handle then
    local win_id = s.handle:get_win_id()
    if win_id and vim.api.nvim_win_is_valid(win_id) then
      vim.api.nvim_set_option_value("statusline", title, { win = win_id })
    end
  end
end

function M.clear_buffer()
  local s = view_state.get_state("general_log_view")
  if s.handle then
    local buf_id = s.handle._buf
    if buf_id and vim.api.nvim_buf_is_valid(buf_id) then
      vim.api.nvim_set_option_value("modifiable", true, { buf = buf_id })
      vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, {})
      vim.api.nvim_set_option_value("modifiable", false, { buf = buf_id })
    end
    -- フィルター状態もリセット
    filter_state.enabled = false
    filter_state.original_lines = nil
    M.set_title("[[ General Log ]]")
  end
end

function M.is_open()
  local s = view_state.get_state("general_log_view")
  return s.handle ~= nil
end

function M.send_to_quickfix()
  local s = view_state.get_state("general_log_view")
  if not s.handle then
    vim.notify("ULG: general log is not open.", vim.log.levels.WARN)
    return
  end
  local buf_id = s.handle._buf
  if not buf_id or not vim.api.nvim_buf_is_valid(buf_id) then return end

  local all_lines = vim.api.nvim_buf_get_lines(buf_id, 0, -1, false)

  -- MSVC: "C:\path\file.cpp(10): error C2065: ..."
  -- MSVC: "C:\path\file.cpp(10,5): error ..."
  local msvc_pat = "([A-Za-z]:[/\\].-)%((%d+)[,%d]*%):%s*(.*)"
  -- UBT: "ERROR: message (no file info)"
  local ubt_error_pat = "^ERROR%s*:%s*(.*)"

  local qf_items = {}
  for _, line in ipairs(all_lines) do
    local filepath, lnum, text = line:match(msvc_pat)
    if filepath and lnum then
      local type_char = "E"
      if line:lower():match("warning") then type_char = "W" end
      table.insert(qf_items, {
        filename = filepath,
        lnum     = tonumber(lnum),
        col      = 1,
        text     = text or line,
        type     = type_char,
      })
    else
      local msg = line:match(ubt_error_pat)
      if msg then
        table.insert(qf_items, {
          filename = "",
          lnum     = 0,
          col      = 0,
          text     = msg,
          type     = "E",
        })
      end
    end
  end

  if #qf_items == 0 then
    vim.notify("ULG: no errors or warnings found in log.", vim.log.levels.INFO)
    return
  end

  vim.fn.setqflist({}, "r", { title = "UBT Build Errors", items = qf_items })
  vim.cmd("copen")
  vim.notify(string.format("ULG: %d item(s) sent to quickfix.", #qf_items), vim.log.levels.INFO)
end

function M.toggle_error_filter()
  local s = view_state.get_state("general_log_view")
  if not s.handle then
    vim.notify("ULG: general log is not open.", vim.log.levels.WARN)
    return
  end
  local buf_id = s.handle._buf
  if not buf_id or not vim.api.nvim_buf_is_valid(buf_id) then return end

  if filter_state.enabled then
    -- フィルター解除: 元の行を復元
    filter_state.enabled = false
    local restore = filter_state.original_lines or {}
    filter_state.original_lines = nil
    vim.api.nvim_set_option_value("modifiable", true, { buf = buf_id })
    vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, restore)
    vim.api.nvim_set_option_value("modifiable", false, { buf = buf_id })
    M.set_title("[[ General Log ]]")
    vim.notify("ULG: filter off — showing all lines.", vim.log.levels.INFO)
  else
    -- フィルター有効: Error/Warning 行だけ残す
    local all_lines = vim.api.nvim_buf_get_lines(buf_id, 0, -1, false)
    filter_state.original_lines = all_lines
    filter_state.enabled = true
    local filtered = vim.tbl_filter(function(line)
      return vim.fn.match(line, ERROR_PAT) >= 0
          or vim.fn.match(line, WARNING_PAT) >= 0
    end, all_lines)
    vim.api.nvim_set_option_value("modifiable", true, { buf = buf_id })
    vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, filtered)
    vim.api.nvim_set_option_value("modifiable", false, { buf = buf_id })
    local cnt = #filtered
    M.set_title(string.format("[[ General Log — ERROR/WARN filter: %d lines ]]", cnt))
    vim.notify(string.format("ULG: filter on — %d error/warning line(s) shown.", cnt), vim.log.levels.INFO)
  end
end

function M.is_filter_enabled()
  return filter_state.enabled
end

function M.append_lines(lines)
  local s = view_state.get_state("general_log_view")
  if not s.handle then return end

  if type(lines) == "string" then
    lines = { lines }
  end
  if #lines == 0 then return end

  if filter_state.enabled then
    -- フィルター中は原本リストに追記し、Error/Warning 行のみバッファに反映
    for _, l in ipairs(lines) do
      table.insert(filter_state.original_lines, l)
    end
    local new_errors = vim.tbl_filter(function(l)
      return vim.fn.match(l, ERROR_PAT) >= 0
          or vim.fn.match(l, WARNING_PAT) >= 0
    end, lines)
    if #new_errors > 0 then
      s.handle:add_lines(new_errors)
      local buf_id = s.handle._buf
      local total = buf_id and vim.api.nvim_buf_is_valid(buf_id)
          and #vim.api.nvim_buf_get_lines(buf_id, 0, -1, false) or 0
      M.set_title(string.format("[[ General Log — ERROR/WARN filter: %d lines ]]", total))
    end
  else
    s.handle:add_lines(lines)
  end
end

return M
