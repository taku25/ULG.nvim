-- lua/ULG/window/log.lua
-- Handles the log viewer window, file tailing, filtering, and user interactions.

local log = require("ULG.logger")
local view_state = require("ULG.context.view_state")
local help_window = require("ULG.window.help")
local event_types = require("UNL.event.types")
local events = require("UNL.event.events")
local tail = require("ULG.core.tail")
local filter = require("ULG.core.filter")

local M = {}

-- Forward declarations for local functions
local refresh_view
local process_line_queue
local apply_search_highlight
local close_log_window

-- Private helper function to jump between filtered lines
local function jump_to_match(direction)
  local s = view_state.get_state()
  if not (s.win and vim.api.nvim_win_is_valid(s.win) and s.view_buf and vim.api.nvim_buf_is_valid(s.view_buf)) then return end

  if not s.filters_enabled or (#s.category_filters == 0 and (not s.filter_query or s.filter_query == "")) then
    log.get().info("No active filters to jump between.")
    return
  end

  local cursor_line = vim.api.nvim_win_get_cursor(s.win)[1]
  local line_count = vim.api.nvim_buf_line_count(s.view_buf)

  local start_line, end_line, increment
  if direction == "next" then
    start_line, end_line, increment = cursor_line, line_count - 1, 1
  else
    start_line, end_line, increment = cursor_line - 2, 0, -1
  end

  for i = start_line, end_line, increment do
    if i >= 0 and i < line_count then
      vim.api.nvim_win_set_cursor(s.win, { i + 1, 0 })
      return
    end
  end
  log.get().info("No more filtered lines in this direction.")
end

-- Private helper to apply search term highlighting
apply_search_highlight = function()
  local s = view_state.get_state()
  if not (s.win and vim.api.nvim_win_is_valid(s.win)) then return end

  if s.search_hl_id then
    pcall(vim.fn.matchdelete, s.search_hl_id, s.win)
    view_state.update_state({ search_hl_id = nil })
  end

  if s.search_query and s.search_query ~= "" then
    local ok, id = pcall(vim.fn.matchadd, "Search", s.search_query, 9, -1, { window = s.win })
    if ok then
      view_state.update_state({ search_hl_id = id })
    else
      log.get().warn("Invalid regex for search highlight: %s", s.search_query)
    end
  end
end

-- Private helper to redraw the view buffer based on current state
refresh_view = function()
  local s = view_state.get_state()
  if not (s.master_buf and vim.api.nvim_buf_is_valid(s.master_buf) and s.view_buf and vim.api.nvim_buf_is_valid(s.view_buf)) then return end

  local all_lines = vim.api.nvim_buf_get_lines(s.master_buf, 0, -1, false)
  local processed_lines = {}
  if s.hide_timestamp then
    for _, line in ipairs(all_lines) do table.insert(processed_lines, (line:gsub("%[%d+%.%d+%.%d+%-%d+%.%d+%.%d+:%d+%]%[%s*%d+%]%s*", ""))) end
  else
    processed_lines = all_lines
  end

  local final_lines
  local ok, _ = pcall(vim.regex, s.filter_query or "")
  if not ok then
    final_lines = { "ERROR: Invalid regular expression. Press assigned key to clear." }
  else
    final_lines = filter.apply(processed_lines, {
      filters_enabled = s.filters_enabled,
      category_filters = s.category_filters,
      filter_query = s.filter_query,
    })
  end

  vim.api.nvim_set_option_value("modifiable", true, { buf = s.view_buf })
  vim.api.nvim_buf_set_lines(s.view_buf, 0, -1, false, final_lines)
  vim.api.nvim_set_option_value("modifiable", false, { buf = s.view_buf })
  apply_search_highlight()
end

-- Private helper to process the queue of new log lines
process_line_queue = function()
  local s = view_state.get_state()
  if s.is_processing or #s.line_queue == 0 then return end
  if not (s.master_buf and vim.api.nvim_buf_is_valid(s.master_buf) and s.view_buf and vim.api.nvim_buf_is_valid(s.view_buf)) then return end

  view_state.update_state({ is_processing = true })
  local chunk_size = s.render_chunk_size or 500
  local lines_to_process = {}
  for i = 1, chunk_size do local line = table.remove(s.line_queue, 1); if not line then break end; table.insert(lines_to_process, line) end

  if #lines_to_process > 0 then
    vim.api.nvim_buf_set_lines(s.master_buf, -1, -1, false, lines_to_process)
    local processed_lines = {}
    if s.hide_timestamp then
      for _, line in ipairs(lines_to_process) do table.insert(processed_lines, (line:gsub("%[%d+%.%d+%.%d+%-%d+%.%d+%.%d+:%d+%]%[%s*%d+%]%s*", ""))) end
    else
      processed_lines = lines_to_process
    end

    local filtered_lines = filter.apply(processed_lines, {
      filters_enabled = s.filters_enabled,
      category_filters = s.category_filters,
      filter_query = s.filter_query,
    })

    if #filtered_lines > 0 then
      local is_at_bottom = false
      if s.win and vim.api.nvim_win_is_valid(s.win) then local lc = vim.api.nvim_buf_line_count(s.view_buf); local cl = vim.api.nvim_win_get_cursor(s.win)[1]; is_at_bottom = (cl >= lc) end
      vim.api.nvim_set_option_value("modifiable", true, { buf = s.view_buf })
      vim.api.nvim_buf_set_lines(s.view_buf, -1, -1, false, filtered_lines)
      vim.api.nvim_set_option_value("modifiable", false, { buf = s.view_buf })
      if s.auto_scroll and is_at_bottom and s.win and vim.api.nvim_win_is_valid(s.win) then vim.api.nvim_win_set_cursor(s.win, { vim.api.nvim_buf_line_count(s.view_buf), 0 }) end
    end
  end

  view_state.update_state({ is_processing = false, line_queue = s.line_queue })
  if #s.line_queue > 0 then vim.schedule(process_line_queue) end
end

-- Stops tailing the file, but leaves the window open
local function stop_tailing()
  local s = view_state.get_state()
  if s.watcher then
    s.watcher:stop()
    view_state.update_state({ watcher = nil })
    log.get().info("Stopped tailing log file: %s", s.filepath)
  end
end

-- Completely tear down the log viewer UI and state
close_log_window = function()
  local s = view_state.get_state()
  -- Prevent this from running twice if called manually then by BufUnload
  if not s.win then return end

  local was_active = s.win and true or false
  local closed_filepath = s.filepath

  help_window.close()
  stop_tailing() -- Ensure watcher is stopped

  if s.win and vim.api.nvim_win_is_valid(s.win) then
    vim.api.nvim_win_close(s.win, true)
  end
  if s.view_buf and vim.api.nvim_buf_is_valid(s.view_buf) then
    -- BufUnload will trigger this, so we don't want to delete it here
    -- It will be deleted automatically upon window close
  end
  if s.master_buf and vim.api.nvim_buf_is_valid(s.master_buf) then
    vim.api.nvim_buf_delete(s.master_buf, { force = true })
  end

  view_state.reset_state()

  if was_active then
    events.publish(event_types.VIEWER_STOPPED, { filepath = closed_filepath })
  end
end

-- Create and set up the log viewer window and start tailing
local function start_log_window(log_file_path)
  -- If a viewer is already open, clean it up before starting a new one
  close_log_window()

  local conf_root = require("UNL.config").get("ULG")
  view_state.update_state(conf_root)
  -- The original_win is managed by the global autocmd. Just set the filepath.
  view_state.update_state({ filepath = log_file_path })

  local s = view_state.get_state()
  local master_buf = vim.api.nvim_create_buf(false, true)
  local view_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[view_buf].buflisted = false
  vim.bo[view_buf].swapfile = false
  vim.bo[view_buf].filetype = s.filetype
  view_state.update_state({ master_buf = master_buf, view_buf = view_buf })

  local cmd = s.win_open_command
  if not cmd then
    if s.position == "right" then cmd = "vertical botright " .. s.vertical_size .. " new"
    elseif s.position == "left" then cmd = "vertical topleft " .. s.vertical_size .. " new"
    elseif s.position == "top" then cmd = "topleft " .. s.horizontal_size .. " new"
    else cmd = "botright " .. s.horizontal_size .. " new" end
  end
  vim.cmd(cmd)

  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, view_buf)
  view_state.update_state({ win = win })

  -- Call cleanup when the viewer buffer is closed by the user
  vim.api.nvim_create_autocmd("BufUnload", {
    buffer = view_buf,
    once = true,
    callback = function()
      close_log_window()
    end,
  })

  local keymaps = s.keymaps or {}
  if keymaps.filter_prompt then vim.api.nvim_buf_set_keymap(view_buf, "n", keymaps.filter_prompt, "<cmd>lua require('ULG.window.log').prompt_filter()<cr>", { noremap = true, silent = true }) end
  if keymaps.filter_clear then vim.api.nvim_buf_set_keymap(view_buf, "n", keymaps.filter_clear, "<cmd>lua require('ULG.window.log').clear_filter()<cr>", { noremap = true, silent = true }) end
  if keymaps.toggle_timestamp then vim.api.nvim_buf_set_keymap(view_buf, "n", keymaps.toggle_timestamp, "<cmd>lua require('ULG.window.log').toggle_timestamp()<cr>", { noremap = true, silent = true }) end
  if keymaps.clear_content then vim.api.nvim_buf_set_keymap(view_buf, "n", keymaps.clear_content, "<cmd>lua require('ULG.window.log').clear_content()<cr>", { noremap = true, silent = true }) end
  if keymaps.category_filter_prompt then vim.api.nvim_buf_set_keymap(view_buf, "n", keymaps.category_filter_prompt, "<cmd>lua require('ULG.window.log').prompt_category_filter()<cr>", { noremap = true, silent = true }) end
  if keymaps.jump_to_source then vim.api.nvim_buf_set_keymap(view_buf, "n", keymaps.jump_to_source, "<cmd>lua require('ULG.window.log').jump_to_source()<cr>", { noremap = true, silent = true }) end
  if keymaps.filter_toggle then vim.api.nvim_buf_set_keymap(view_buf, "n", keymaps.filter_toggle, "<cmd>lua require('ULG.window.log').toggle_filters()<cr>", { noremap = true, silent = true }) end
  if keymaps.search_prompt then vim.api.nvim_buf_set_keymap(view_buf, "n", keymaps.search_prompt, "<cmd>lua require('ULG.window.log').prompt_search()<cr>", { noremap = true, silent = true }) end
  if keymaps.jump_next_match then vim.api.nvim_buf_set_keymap(view_buf, "n", keymaps.jump_next_match, "<cmd>lua require('ULG.window.log').jump_next()<cr>", { noremap = true, silent = true }) end
  if keymaps.jump_prev_match then vim.api.nvim_buf_set_keymap(view_buf, "n", keymaps.jump_prev_match, "<cmd>lua require('ULG.window.log').jump_prev()<cr>", { noremap = true, silent = true }) end
  if keymaps.show_help then vim.api.nvim_buf_set_keymap(view_buf, "n", keymaps.show_help, "<cmd>lua require('ULG.window.log').show_help()<cr>", { noremap = true, silent = true }) end

  local highlights_conf = s.highlights
  if highlights_conf and highlights_conf.enabled then
    for name, rule in pairs(highlights_conf.groups or {}) do
      local p, g, prio = rule.pattern, rule.hl_group, rule.priority or 100
      if p and g then
        local ok, res = pcall(vim.fn.matchadd, g, p, prio, -1, { window = win })
        if not ok then log.get().error("Failed to add highlight for rule '%s'. Error: %s", name, tostring(res)) end
      end
    end
  end

  if vim.fn.filereadable(log_file_path) == 1 then
    vim.api.nvim_buf_set_lines(master_buf, 0, -1, false, vim.fn.readfile(log_file_path))
  end
  refresh_view()
  vim.api.nvim_set_option_value("modifiable", false, { buf = view_buf })

  local interval = s.polling_interval_ms or 500
  local tailer_handle = tail.start(log_file_path, interval, function(new_lines)
    local current_s = view_state.get_state()
    vim.list_extend(current_s.line_queue, new_lines)
    view_state.update_state({ line_queue = current_s.line_queue })
    process_line_queue()
  end)
  view_state.update_state({ watcher = tailer_handle })

  log.get().info("Started tailing log file: %s", log_file_path)
  events.publish(event_types.VIEWER_STARTED, { filepath = log_file_path, bufnr = view_buf })
end

-------------------
-- Public API
-------------------
M.start = start_log_window
M.stop = stop_tailing

M.prompt_filter = function()
  vim.ui.input({ prompt = "Filter Log (regex):", default = view_state.get_state().filter_query or "" }, function(input)
    if input == nil then return end
    view_state.update_state({ filter_query = input, filters_enabled = true })
    refresh_view()
  end)
end

M.clear_filter = function()
  local s = view_state.get_state()
  if s.filter_query or #s.category_filters > 0 or s.search_query then
    view_state.update_state({ filter_query = nil, category_filters = {}, search_query = nil, filters_enabled = true })
    log.get().info("All log filters and search highlights cleared.")
    refresh_view()
  end
end

M.prompt_category_filter = function()
  local s = view_state.get_state()
  if not (s.master_buf and vim.api.nvim_buf_is_valid(s.master_buf)) then return end

  local categories_set = {}
  local all_lines = vim.api.nvim_buf_get_lines(s.master_buf, 0, -1, false)
  for _, line in ipairs(all_lines) do
    local category = line:match("%s*([a-zA-Z][a-zA-Z0-9_]*):")
    if category and #category > 1 then categories_set[category] = true end
  end
  local user_defined = s.category_filters or {}
  for _, category in ipairs(user_defined) do categories_set[category] = true end

  local categories_list = {}
  for category, _ in pairs(categories_set) do table.insert(categories_list, category) end
  table.sort(categories_list)
  if #categories_list == 0 then
    log.get().info("No log categories found yet.")
    return
  end

  require("UNL.backend.picker").pick({
    kind = "ulg_select_category",
    title = "Filter by Categories (<Tab> to select, <CR> to confirm)",
    conf = require("UNL.config").get("ULG"),
    items = categories_list,
    multi_select = true,
    preview_enabled = false,
    on_submit = function(selected_categories)
      if not selected_categories then return end
      view_state.update_state({ category_filters = selected_categories, filters_enabled = true })
      if #selected_categories > 0 then
        log.get().info("Category filters set to: [%s]", table.concat(selected_categories, ", "))
      else
        log.get().info("Category filters cleared.")
      end
      refresh_view()
    end,
  })
end

M.toggle_filters = function()
  local s = view_state.get_state()
  view_state.update_state({ filters_enabled = not s.filters_enabled })
  if not s.filters_enabled then
    log.get().info("Log filters ENABLED.")
  else
    log.get().info("Log filters DISABLED. Showing all logs.")
  end
  refresh_view()
end

M.prompt_search = function()
  vim.ui.input({ prompt = "Highlight in View (regex):", default = view_state.get_state().search_query or "" }, function(input)
    if input == nil then return end
    view_state.update_state({ search_query = input })
    apply_search_highlight()
  end)
end

function M.jump_to_source()
  local s = view_state.get_state()
  if not (s.win and vim.api.nvim_win_is_valid(s.win) and s.view_buf and vim.api.nvim_buf_is_valid(s.view_buf)) then return end

  local cursor_pos = vim.api.nvim_win_get_cursor(s.win)
  local line_content = vim.api.nvim_buf_get_lines(s.view_buf, cursor_pos[1] - 1, cursor_pos[1], false)[1]

  if not line_content then return end

  local filepath, lnum, col = line_content:match(
    '([%~%a]:?[/\\][^%(%)"]+%.%w+)%((%d+):(%d+)%)'
  )

  if not filepath then
    filepath = line_content:match('([%~%a]:?[/\\][^%(%)"]+%.%w+)')
  end

  lnum = lnum or 1
  col = col or 1

  if filepath then
      -- 1. Sanitize and prepare the path
      filepath = vim.trim(filepath)
      filepath = vim.fn.expand(filepath)
      local escaped_path = vim.fn.fnameescape(filepath)

      lnum = lnum or "1"
      col = col or "1"
      log.get().info("Jumping to: %s:%s:%s", filepath, lnum, col)

      -- 2. Get the original window ID from state
      local original_win = s.original_win

      -- 3. Check if the original window is still valid and switch to it
      if original_win and vim.api.nvim_win_is_valid(original_win) then
          vim.api.nvim_set_current_win(original_win)
      else
          -- If the original window is gone, create a new vertical split
          vim.cmd("vsplit")
      end

      -- 4. Open the file in the now-active window
      vim.cmd("edit +" .. lnum .. " " .. escaped_path)
      vim.api.nvim_win_set_cursor(0, { tonumber(lnum), math.max(0, tonumber(col) - 1) })
  else
      log.get().info("No source location found on this line.")
  end
end


M.jump_next = function() jump_to_match("next") end
M.jump_prev = function() jump_to_match("prev") end

M.toggle_timestamp = function()
  local s = view_state.get_state()
  view_state.update_state({ hide_timestamp = not s.hide_timestamp })
  log.get().info("Timestamp display toggled: %s", (not s.hide_timestamp) and "OFF" or "ON")
  refresh_view()
end

M.clear_content = function()
  local s = view_state.get_state()
  if not (s.master_buf and vim.api.nvim_buf_is_valid(s.master_buf)) then return end

  log.get().info("Log buffer content cleared.")
  vim.api.nvim_buf_set_lines(s.master_buf, 0, -1, false, {})
  view_state.update_state({ line_queue = {} })

  if s.filepath and vim.fn.filereadable(s.filepath) == 1 then
    local stat = vim.loop.fs_stat(s.filepath)
    if stat then
      -- No need to update state, tailer will handle it
    end
  end
  refresh_view()
end

M.show_help = function()
  help_window.toggle()
end

return M

