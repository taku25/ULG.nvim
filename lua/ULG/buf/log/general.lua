-- lua/ULG/buf/log/general.lua (ステートマネージャー対応版)

local log = require("ULG.logger")
local view_state = require("ULG.context.view_state")

local M = {}

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

function M.create_spec(conf)
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
  if s.handle and s.handle:is_open() then
    vim.api.nvim_set_option_value("statusline", title, { win = s.handle:get_win_id() })
  end
end

function M.clear_buffer()
  local s = view_state.get_state("general_log_view")
  if s.handle and s.handle:is_open() then
    local buf_id = s.handle._buf
    vim.api.nvim_set_option_value("modifiable", true, { buf = buf_id })
    vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, {})
    vim.api.nvim_set_option_value("modifiable", false, { buf = buf_id })
  end
end

function M.is_open()
  local s = view_state.get_state("general_log_view")
  return s.handle and s.handle:is_open()
end

function M.append_lines(lines)
  local s = view_state.get_state("general_log_view")
  if not (s.handle and s.handle:is_open()) then return end

  if type(lines) == "string" then
    lines = { lines }
  end
  if #lines > 0 then
    s.handle:add_lines(lines)
  end
end

return M
