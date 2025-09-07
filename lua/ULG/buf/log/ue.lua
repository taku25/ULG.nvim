-- lua/ULG/buf/log/ue.lua (マネージャー対応・最終完成版)

local unl_picker = require("UNL.backend.picker")
local view_state = require("ULG.context.view_state")
local help_window = require("ULG.window.help")
local unl_api = require("UNL.api")
local tail = require("ULG.core.tail")
local filter = require("ULG.core.filter")
local log = require("ULG.logger")

local M = {}
local handle, tailer, master_lines

-- =============================================================================
-- Private Helper: View Refresh Logic
-- =============================================================================
local function refresh_view()
  if not (handle and handle:is_open()) then return end
  local s = view_state.get_state()
  local buf_id = vim.api.nvim_win_get_buf(handle:get_win_id())
  local processed_lines = {}
  if s.hide_timestamp then
    for _, line in ipairs(master_lines) do
      table.insert(processed_lines, (line:gsub("%[%d+%.%d+%.%d+%-%d+%.%d+%.%d+:%d+%]%[%s*%d+%]%s*", "")))
    end
  else
    processed_lines = master_lines
  end
  local final_lines = filter.apply(processed_lines, {
    filters_enabled = s.filters_enabled,
    category_filters = s.category_filters,
    filter_query = s.filter_query,
  })
  vim.api.nvim_set_option_value("modifiable", true, { buf = buf_id })
  vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, final_lines)
  vim.api.nvim_set_option_value("modifiable", false, { buf = buf_id })
end

-- =============================================================================
-- Keymap Callbacks (省略一切なし)
-- =============================================================================
function M.prompt_remote_command()
  local conf = require("UNL.config").get("ULG")
  vim.ui.input({ prompt = "UE Remote Command: ", completion = "customlist,ULG_CompleteRemoteCommands_VimFunc" }, function(input)
    if not input or input == "" then return end
    unl_api.kismet_command({
      command = input, host = (conf.remote and conf.remote.host), port = (conf.remote and conf.remote.port),
      on_success = function() log.get().info("UE Command Sent: %s", input) end,
      on_error = function(err) log.get().error("UE Command Failed: %s", err) end,
    })
  end)
end
function M.jump_to_source()
  if not (handle and handle:is_open()) then
    return
  end
  local line = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(handle:get_win_id()), vim.api.nvim_win_get_cursor(handle:get_win_id())[1] - 1, vim.api.nvim_win_get_cursor(handle:get_win_id())[1], false)[1]
  if not line then
    return
  end
  local filepath, lnum = line:match('([%~%a]:?[/\\][^%(%)"]+%.%w+)%((%d+)%)')
  if not filepath then
    filepath = line:match('([%~%a]:?[/\\][^%(%)"]+%.%w+)')
  end
  if filepath then vim.cmd("edit +" .. (lnum or 1) .. " " .. vim.fn.fnameescape(vim.trim(filepath)))
  else
    log.get().info("No source location found on this line.")
  end
end
function M.prompt_filter()
  vim.ui.input({ prompt = "Filter Log (regex):", default = view_state.get_state().filter_query or "" }, function(input)
    if input == nil then
      return
    end
    view_state.update_state({ filter_query = input, filters_enabled = true }); refresh_view()
  end)
end
function M.clear_filter()
  view_state.update_state({ filter_query = nil, category_filters = {}, search_query = nil, filters_enabled = true }); refresh_view()
end
function M.toggle_timestamp()
  view_state.update_state({ hide_timestamp = not view_state.get_state().hide_timestamp }); refresh_view()
end
function M.clear_content()
  master_lines = {}
  refresh_view()
  log.get().info("Log content cleared.")
end

function M.prompt_category_filter()
  local categories_set = {}
  for _, line in ipairs(master_lines) do
    local category = line:match("%s*([a-zA-Z][a-zA-Z0-9_]*):")
    if category and #category > 1 then categories_set[category] = true end
  end
  local categories_list = {
  }
  for category, _ in pairs(categories_set) do table.insert(categories_list, category) end
  table.sort(categories_list)
  if #categories_list == 0 then
    return log.get().info("No log categories found yet.")
  end
  unl_picker.pick({
    kind = "ulg_category_filter", title = "Filter by Categories", conf = require("UNL.config").get("ULG"),
    items = categories_list, multi_select = true,
    on_submit = function(selected)
      if not selected then return end
      view_state.update_state({ category_filters = selected, filters_enabled = true }); refresh_view()
    end,
  })
end
function M.toggle_filters()
  view_state.update_state({ filters_enabled = not view_state.get_state().filters_enabled }); refresh_view()
end
function M.prompt_search()
  vim.ui.input({ prompt = "Highlight in View (regex):", default = view_state.get_state().search_query or "" }, function(input)
    if input == nil then return end
    view_state.update_state({ search_query = input }); log.get().debug("Search highlighting not fully implemented yet.")
  end)
end
function M.jump_next()
  log.get().debug("Jump to next match (not implemented yet)")
end
function M.jump_prev()
  log.get().debug("Jump to prev match (not implemented yet)")
end
function M.show_help()
  help_window.toggle()
end

-- =============================================================================
-- Module Public API
-- =============================================================================

function M.create_spec(conf)
  local keymaps = { ["q"] = "<cmd>lua require('ULG.api').close()<cr>" }
  local keymap_name_to_func = {
    filter_prompt = "prompt_filter", filter_clear = "clear_filter", toggle_timestamp = "toggle_timestamp",
    clear_content = "clear_content", category_filter_prompt = "prompt_category_filter",
    jump_to_source = "jump_to_source", filter_toggle = "toggle_filters", search_prompt = "prompt_search",
    remote_command_prompt = "prompt_remote_command", jump_next_match = "jump_next",
    jump_prev_match = "jump_prev", show_help = "show_help",
  }
  for name, key in pairs(conf.keymaps.log or {}) do
    local func_name = keymap_name_to_func[name]
    if func_name and key then
      keymaps[key] = string.format("<cmd>lua require('ULG.buf.log.ue').%s()<cr>", func_name)
    end
  end
  if conf.build_log_enabled and conf.keymaps.log.toggle_build_log then
    keymaps[conf.keymaps.log.toggle_build_log] = "<cmd>lua require('ULG.buf.log.build').toggle()<cr>"
  end
  return {
    id = "ue_log",
    title = "[[ Unreal Engine LOG ]]",
    filetype = "unreal-log",
    auto_scroll = true,
    positioning = {
      strategy = 'primary',
      location = conf.position,
      size = conf.size },
    keymaps = keymaps,
  }
end

function M.start_tailing(h, filepath, conf)
  handle = h
  master_lines = vim.fn.filereadable(filepath) == 1 and vim.fn.readfile(filepath) or {}
  refresh_view()
  tailer = tail.start(filepath, conf.polling_interval_ms or 500, function(new_lines)
    vim.list_extend(master_lines, new_lines); refresh_view()
  end)
end

function M.stop_tailing()
  if tailer then tailer:stop(); tailer = nil end
  handle = nil
end

return M
