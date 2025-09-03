
local log = require("ULG.logger")
local unl_picker = require("UNL.backend.picker")
local M = {}

local state = {
  master_buf = nil, view_buf = nil, win = nil,
  watcher = nil, filepath = nil, last_size = 0,
  -- フィルター関連の状態
  filter_query = nil,
  category_filters = {},
  -- ★★★ フィルターのトグル機能のための状態 ★★★
  filters_enabled = true,
  saved_filters = nil,
  -- ★★★ 検索ハイライト機能のための状態 ★★★
  search_query = nil,
  search_hl_id = nil,
  -- 非同期処理の状態
  line_queue = {}, is_processing = false,
  -- コンフィグ
  conf = nil,
}

-- 関数の前方宣言
local refresh_view
local process_line_queue
local apply_search_highlight

local function jump_to_match(direction)
  if not (state.win and vim.api.nvim_win_is_valid(state.win) and state.view_buf and vim.api.nvim_buf_is_valid(state.view_buf)) then return end

  -- フィルターが有効でない、またはフィルターが設定されていない場合は何もしない
  if not state.filters_enabled or (#state.category_filters == 0 and (not state.filter_query or state.filter_query == "")) then
    log.get().info("No active filters to jump between.")
    return
  end

  local cursor_line = vim.api.nvim_win_get_cursor(state.win)[1]
  local line_count = vim.api.nvim_buf_line_count(state.view_buf)
  
  local start_line, end_line, increment
  if direction == "next" then
    start_line = cursor_line -- 現在行の次から検索
    end_line = line_count -1
    increment = 1
  else -- "prev"
    start_line = cursor_line - 2 -- 現在行の前から検索
    end_line = 0
    increment = -1
  end

  -- NOTE: このジャンプは、ビューバッファ内の可視行に対して行われます。
  --       フィルターにマッチする行はビューバッファにしか存在しないため、これで正しい動作となります。
  for i = start_line, end_line, increment do
    -- ループ内で毎回チェックする必要はないが、安全のため
    if i >= 0 and i < line_count then
      -- ジャンプするだけで、再フィルタリングは不要なので、ここでは単純に次の行に移動
      vim.api.nvim_win_set_cursor(state.win, { i + 1, 0 })
      return
    end
  end

  -- 最後/最初のマッチに到達したことを通知
  log.get().info("No more filtered lines in this direction.")
end

--公開API (Mテーブルに追加される関数群)
--
function M.prompt_filter()
  vim.ui.input({ prompt = "Filter Log (regex):", default = state.filter_query or "" }, function(input)
    if input == nil then return end
    state.filter_query = input
    state.filters_enabled = true -- フィルターを入力したら、必ず有効にする
    refresh_view()
  end)
end

function M.clear_filter()
  if state.filter_query or #state.category_filters > 0 or state.search_query then
    state.filter_query = nil
    state.category_filters = {}
    state.search_query = nil
    state.filters_enabled = true
    state.saved_filters = nil
    log.get().info("All log filters and search highlights cleared.")
    refresh_view()
  end
end

function M.prompt_category_filter()
  if not (state.master_buf and vim.api.nvim_buf_is_valid(state.master_buf)) then return end

  local categories_set = {}
  local all_lines = vim.api.nvim_buf_get_lines(state.master_buf, 0, -1, false)
  for _, line in ipairs(all_lines) do
    local category = line:match("%s*([a-zA-Z][a-zA-Z0-9_]*):")
    if category and #category > 1 then
      categories_set[category] = true
    end
  end
  local user_defined = (state.conf and state.conf.category_filters) or {}
  for _, category in ipairs(user_defined) do
    categories_set[category] = true
  end

  local categories_list = {}
    for category, _ in pairs(categories_set) do
      table.insert(categories_list, category)
    end
  table.sort(categories_list)
  if #categories_list == 0 then
    log.get().info("No log categories found yet.")
    return
  end
  
  unl_picker.pick({
    kind = "ulg_select_category",
    title = "Filter by Categories (<Tab> to select, <CR> to confirm)",
    conf = require("UNL.config").get("ULG"),
    items = categories_list,
    multi_select = true,
    preview_enabled = false,

    on_submit = function(selected_categories)
      -- ★★★ ここからがデバッグコードです ★★★
      if selected_categories then
        -- vim.inspect() はLuaのテーブルを人間が読める文字列に変換します
        local debug_message = "Picker returned: " .. vim.inspect(selected_categories)
        vim.notify(debug_message, vim.log.levels.INFO, { title = "[ULG Debug]" })
      else
        vim.notify("Picker returned nil", vim.log.levels.WARN, { title = "[ULG Debug]" })
      end
      -- ★★★ デバッグコードここまで ★★★

      if not selected_categories then return end
      
      state.category_filters = selected_categories
      state.filters_enabled = true
      if #selected_categories > 0 then
        log.get().info("Category filters set to: [%s]", table.concat(selected_categories, ", "))
      else
        log.get().info("Category filters cleared.")
      end
      refresh_view()
    end,
  })
end

function M.toggle_filters()
  state.filters_enabled = not state.filters_enabled
  if state.filters_enabled then
    log.get().info("Log filters ENABLED.")
  else
    log.get().info("Log filters DISABLED. Showing all logs.")
  end
  refresh_view()
end

function M.prompt_search()
  vim.ui.input({ prompt = "Highlight in View (regex):", default = state.search_query or "" }, function(input)
    if input == nil then return end
    state.search_query = input
    apply_search_highlight()
  end)
end

function M.jump_to_source()
  if not (state.win and vim.api.nvim_win_is_valid(state.win) and state.view_buf and vim.api.nvim_buf_is_valid(state.view_buf)) then return end
  
  local cursor_pos = vim.api.nvim_win_get_cursor(state.win)
  local line_content = vim.api.nvim_buf_get_lines(state.view_buf, cursor_pos[1] - 1, cursor_pos[1], false)[1]

  if not line_content then return end

  -- Unrealの様々なパス形式にマッチさせる正規表現
  -- 例: C:\Path\To\File.cpp(123)
  -- 例: C:\Path\To\File.h:123
  local filepath, lnum = line_content:match([[\b([a-zA-Z]:\\[^:]+%.[ch]pp)[(:](\d+)\)?]])
  
  if filepath and lnum then
    log.get().info("Jumping to: %s:%s", filepath, lnum)
    -- ウィンドウを閉じる前にジャンプすることで、ユーザーは元の場所に戻りやすい
    vim.cmd("edit +" .. lnum .. " '" .. filepath .. "'")
  else
    log.get().info("No source location found on this line.")
  end
end 

function M.jump_next()
  jump_to_match("next")
end

function M.jump_prev()
  jump_to_match("prev")
end

function M.toggle_timestamp()
  local conf = require("UNL.config").get("ULG")
  conf.viewer.hide_timestamp = not conf.viewer.hide_timestamp
  log.get().info("Timestamp display toggled: %s", conf.viewer.hide_timestamp and "OFF" or "ON")
  refresh_view()
end

function M.clear_content()
  if not (state.master_buf and vim.api.nvim_buf_is_valid(state.master_buf)) then
    return
  end
  log.get().info("Log buffer content cleared.")
  vim.api.nvim_buf_set_lines(state.master_buf, 0, -1, false, {})
  state.line_queue = {}
  if state.filepath and vim.fn.filereadable(state.filepath) == 1 then
    local stat = vim.loop.fs_stat(state.filepath)
    if stat then
      state.last_size = stat.size
    end
  end
  refresh_view()
end

-- ★★★ こちらが、あなたの哲学を反映した、最終的な整形版です ★★★
function M.close_help_window()
  if state.help_win and vim.api.nvim_win_is_valid(state.help_win) then
    vim.api.nvim_win_close(state.help_win, true)
  end
  if state.help_buf and vim.api.nvim_buf_is_valid(state.help_buf) then
    vim.api.nvim_buf_delete(state.help_buf, { force = true })
  end
  state.help_win = nil
  state.help_buf = nil
end

-- ★★★ この関数の中の1行だけが変更されます ★★★
function M.show_help()
  if state.help_win and vim.api.nvim_win_is_valid(state.help_win) then M.close_help_window(); return end
  local help_conf = state.conf and state.conf.help
  local help_lines_template = require("ULG.config.help")
  local current_keymaps = state.conf.keymaps or {}
  local final_help_lines = {}; for _, line in ipairs(help_lines_template) do table.insert(final_help_lines, (line:gsub("{([%w_]+)}", function(key) return current_keymaps[key] or "N/A" end))) end

  state.help_buf = vim.api.nvim_create_buf(false, true); vim.bo[state.help_buf].buftype = "nofile"; vim.bo[state.help_buf].bufhidden = "hide"; vim.bo[state.help_buf].swapfile = false
  vim.api.nvim_buf_set_lines(state.help_buf, 0, -1, false, final_help_lines); vim.api.nvim_set_option_value("modifiable", false, { buf = state.help_buf })
  
  local width = math.min(math.floor(vim.o.columns * 0.8), 80); local height = #final_help_lines; local row = math.floor((vim.o.lines - height) / 2 - 2); local col = math.floor((vim.o.columns - width) / 2)
  local win_opts = { style = "minimal", relative = "editor", width = width, height = height, row = row, col = col, border = help_conf and help_conf.border or "rounded" }
  state.help_win = vim.api.nvim_open_win(state.help_buf, true, win_opts)

  -- ★★★ ユーザーが直感的に「閉じる」と期待する全てのキーをマップする ★★★
  local close_cmd = "<cmd>lua require('ULG.viewer').close_help_window()<cr>"
  local map_opts = { noremap = true, silent = true }
  vim.api.nvim_buf_set_keymap(state.help_buf, "n", "q", close_cmd, map_opts)
  vim.api.nvim_buf_set_keymap(state.help_buf, "n", "<Esc>", close_cmd, map_opts)
  vim.api.nvim_buf_set_keymap(state.help_buf, "n", "?", close_cmd, map_opts)
  vim.api.nvim_buf_set_keymap(state.help_buf, "n", "<CR>", close_cmd, map_opts)
end
--
-- 内部処理用のローカル関数群
--
apply_search_highlight = function()
  if not (state.win and vim.api.nvim_win_is_valid(state.win)) then return end

  -- 既存のハイライトをクリア
  if state.search_hl_id then
    pcall(vim.fn.matchdelete, state.search_hl_id, state.win)
    state.search_hl_id = nil
  end

  -- 新しいクエリがあればハイライトを追加
  if state.search_query and state.search_query ~= "" then
    -- pcallで不正な正規表現エラーを握りつぶす
    local ok, id = pcall(vim.fn.matchadd, "Search", state.search_query, 9, -1, { window = state.win })
    if ok then
      state.search_hl_id = id
    else
      log.get().warn("Invalid regex for search highlight: %s", state.search_query)
    end
  end
end

-- ★★★ フィルター適用ロジックを更新 (トグル機能を考慮) ★★★
-- ★★★ こちらがバグを完全に修正した、最終版のapply_filters関数です ★★★
local function apply_filters(lines_to_filter)
  -- フィルターが無効なら、何もせず全ての行を返す
  if not state.filters_enabled then
    return lines_to_filter
  end

  local lines = lines_to_filter

  -- ステップ1: カテゴリフィルターを適用する (もしあれば)
  if #state.category_filters > 0 then
    local filtered_by_category = {}
    for _, line in ipairs(lines) do
      for _, category in ipairs(state.category_filters) do
        -- あなたの提案通り、安全なプレーンテキスト検索を使用
        if string.find(line, category .. ":", 1, true) then
          table.insert(filtered_by_category, line)
          break -- OR条件なので、一度マッチしたら次の行へ
        end
      end
    end
    -- 次のステップへの入力を、カテゴリで絞り込んだ結果に置き換える
    lines = filtered_by_category
  end

  -- ステップ2: 正規表現フィルターを適用する (もしあれば)
  if state.filter_query and state.filter_query ~= "" then
    local filtered_by_regex = {}
    for _, line in ipairs(lines) do
      if line:match(state.filter_query) then
        table.insert(filtered_by_regex, line)
      end
    end
    -- 次のステップへの入力を、正規表現でさらに絞り込んだ結果に置き換える
    lines = filtered_by_regex
  end

  -- 全てのフィルターステップを終えた最終結果を返す
  return lines
end

process_line_queue = function()
  if state.is_processing or #state.line_queue == 0 then return end
  if not (state.master_buf and vim.api.nvim_buf_is_valid(state.master_buf) and state.view_buf and vim.api.nvim_buf_is_valid(state.view_buf)) then return end
  state.is_processing = true
  local chunk_size = (state.conf and state.conf.render_chunk_size) or 500
  local lines_to_process = {}
  for i = 1, chunk_size do local line = table.remove(state.line_queue, 1); if not line then break end; table.insert(lines_to_process, line) end

  if #lines_to_process > 0 then
    vim.api.nvim_buf_set_lines(state.master_buf, -1, -1, false, lines_to_process)
    local processed_lines = {}
    if state.conf and state.conf.hide_timestamp then
      for _, line in ipairs(lines_to_process) do table.insert(processed_lines, (line:gsub("%[%d+%.%d+%.%d+%-%d+%.%d+%.%d+:%d+%]%[%s*%d+%]%s*", ""))) end
    else
      processed_lines = lines_to_process
    end
    local filtered_lines = apply_filters(processed_lines)
    if #filtered_lines > 0 then
      local is_at_bottom = false
      if state.win and vim.api.nvim_win_is_valid(state.win) then local lc = vim.api.nvim_buf_line_count(state.view_buf); local cl = vim.api.nvim_win_get_cursor(state.win)[1]; is_at_bottom = (cl >= lc) end
      vim.api.nvim_set_option_value("modifiable", true, { buf = state.view_buf })
      vim.api.nvim_buf_set_lines(state.view_buf, -1, -1, false, filtered_lines)
      vim.api.nvim_set_option_value("modifiable", false, { buf = state.view_buf })
      if state.conf and state.conf.auto_scroll and is_at_bottom and state.win and vim.api.nvim_win_is_valid(state.win) then vim.api.nvim_win_set_cursor(state.win, { vim.api.nvim_buf_line_count(state.view_buf), 0 }) end
    end
  end
  state.is_processing = false
  if #state.line_queue > 0 then vim.schedule(process_line_queue) end
end

refresh_view = function()
  if not (state.master_buf and vim.api.nvim_buf_is_valid(state.master_buf) and state.view_buf and vim.api.nvim_buf_is_valid(state.view_buf)) then return end
  local all_lines = vim.api.nvim_buf_get_lines(state.master_buf, 0, -1, false)
  local processed_lines = {}
  if state.conf and state.conf.hide_timestamp then
    for _, line in ipairs(all_lines) do table.insert(processed_lines, (line:gsub("%[%d+%.%d+%.%d+%-%d+%.%d+%.%d+:%d+%]%[%s*%d+%]%s*", ""))) end
  else
    processed_lines = all_lines
  end
  local final_lines
  local ok, _ = pcall(vim.regex, state.filter_query or "")
  if not ok then
    final_lines = { "ERROR: Invalid regular expression in '/'. Press <Esc> to clear." }
  else
    final_lines = apply_filters(processed_lines)
  end
  vim.api.nvim_set_option_value("modifiable", true, { buf = state.view_buf })
  vim.api.nvim_buf_set_lines(state.view_buf, 0, -1, false, final_lines)
  vim.api.nvim_set_option_value("modifiable", false, { buf = state.view_buf })
end

local function cleanup_viewer()
  -- 常にヘルプウィンドウを先に閉じる
  M.close_help_window()

  if state.watcher then
    state.watcher:stop()
    state.watcher:close()
  end
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_close(state.win, true)
  end
  if state.view_buf and vim.api.nvim_buf_is_valid(state.view_buf) then
    vim.api.nvim_buf_delete(state.view_buf, { force = true })
  end
  if state.master_buf and vim.api.nvim_buf_is_valid(state.master_buf) then
    vim.api.nvim_buf_delete(state.master_buf, { force = true })
  end
  
  -- 全ての状態変数をリセットする
  state = {
    master_buf = nil,
    view_buf = nil,
    win = nil,
    watcher = nil,
    filepath = nil,
    last_size = 0,
    filter_query = nil,
    category_filters = {},
    filters_enabled = true,
    search_query = nil,
    search_hl_id = nil,
    line_queue = {},
    is_processing = false,
    conf = nil,
    help_win = nil,
    help_buf = nil,
  }
end

local function stop_viewer()
  if not state.watcher then
    log.get().warn("Log viewer is not currently tailing a file.")
    return
  end
  log.get().info("Stopping log file watch. The viewer buffer remains open.")
  state.watcher:stop()
  state.watcher:close()
  state.watcher = nil
end

local function start_viewer(log_file_path)
  cleanup_viewer()

  local conf_root = require("UNL.config").get("ULG")
  state.conf = conf_root.viewer
  state.filepath = log_file_path
  
  state.master_buf = vim.api.nvim_create_buf(false, true)
  state.view_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[state.view_buf].buflisted = false
  vim.bo[state.view_buf].swapfile = false
  vim.bo[state.view_buf].filetype = state.conf.filetype

  local cmd = state.conf.win_open_command
  if not cmd then
    if state.conf.position == "right" then cmd = "vertical botright " .. state.conf.vertical_size .. " new"
    elseif state.conf.position == "left" then cmd = "vertical topleft " .. state.conf.vertical_size .. " new"
    elseif state.conf.position == "top" then cmd = "topleft " .. state.conf.horizontal_size .. " new"
    else cmd = "botright " .. state.conf.horizontal_size .. " new" end
  end
  vim.cmd(cmd)
  
  state.win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(state.win, state.view_buf)
  
  local keymaps = state.conf.keymaps or {}
  if keymaps.filter_prompt then vim.api.nvim_buf_set_keymap(state.view_buf, "n", keymaps.filter_prompt, "<cmd>lua require('ULG.viewer').prompt_filter()<cr>", { noremap = true, silent = true }) end
  if keymaps.filter_clear then vim.api.nvim_buf_set_keymap(state.view_buf, "n", keymaps.filter_clear, "<cmd>lua require('ULG.viewer').clear_filter()<cr>", { noremap = true, silent = true }) end
  if keymaps.toggle_timestamp then vim.api.nvim_buf_set_keymap(state.view_buf, "n", keymaps.toggle_timestamp, "<cmd>lua require('ULG.viewer').toggle_timestamp()<cr>", { noremap = true, silent = true }) end
  if keymaps.clear_content then vim.api.nvim_buf_set_keymap(state.view_buf, "n", keymaps.clear_content, "<cmd>lua require('ULG.viewer').clear_content()<cr>", { noremap = true, silent = true }) end
  if keymaps.category_filter_prompt then vim.api.nvim_buf_set_keymap(state.view_buf, "n", keymaps.category_filter_prompt, "<cmd>lua require('ULG.viewer').prompt_category_filter()<cr>", { noremap = true, silent = true }) end
  if keymaps.jump_to_source then vim.api.nvim_buf_set_keymap(state.view_buf, "n", keymaps.jump_to_source, "<cmd>lua require('ULG.viewer').jump_to_source()<cr>", { noremap = true, silent = true }) end
  if keymaps.filter_toggle then vim.api.nvim_buf_set_keymap(state.view_buf, "n", keymaps.filter_toggle, "<cmd>lua require('ULG.viewer').toggle_filters()<cr>", { noremap = true, silent = true }) end
  if keymaps.search_prompt then vim.api.nvim_buf_set_keymap(state.view_buf, "n", keymaps.search_prompt, "<cmd>lua require('ULG.viewer').prompt_search()<cr>", { noremap = true, silent = true }) end
  if keymaps.jump_next_match then vim.api.nvim_buf_set_keymap(state.view_buf, "n", keymaps.jump_next_match, "<cmd>lua require('ULG.viewer').jump_next()<cr>", { noremap = true, silent = true }) end
  if keymaps.jump_prev_match then vim.api.nvim_buf_set_keymap(state.view_buf, "n", keymaps.jump_prev_match, "<cmd>lua require('ULG.viewer').jump_prev()<cr>", { noremap = true, silent = true }) end
  if keymaps.show_help then vim.api.nvim_buf_set_keymap(state.view_buf, "n", keymaps.show_help, "<cmd>lua require('ULG.viewer').show_help()<cr>", { noremap = true, silent = true }) end;

  local highlights_conf = state.conf.highlights
  if highlights_conf and highlights_conf.enabled then
    for name, rule in pairs(highlights_conf.groups or {}) do
      local p, g, prio = rule.pattern, rule.hl_group, rule.priority or 100
      if p and g then
        local ok, res = pcall(vim.fn.matchadd, g, p, prio, -1, { window = state.win })
        if not ok then log.get().error("Failed to add highlight for rule '%s'. Error: %s", name, tostring(res)) end
      end
    end
  end

  if vim.fn.filereadable(log_file_path) == 1 then
    state.last_size = vim.loop.fs_stat(log_file_path).size
    vim.api.nvim_buf_set_lines(state.master_buf, 0, -1, false, vim.fn.readfile(log_file_path))
  end
  refresh_view()
  vim.api.nvim_set_option_value("modifiable", false, { buf = state.view_buf })

  local interval = state.conf.polling_interval_ms or 500
  state.watcher = vim.loop.new_fs_poll()
  state.watcher:start(log_file_path, interval, function(err, stat)
    if err or not stat or stat.size <= state.last_size then return end
    local new_size, old_size = stat.size, state.last_size; state.last_size = new_size
    vim.schedule(function()
      local f = io.open(log_file_path, "r"); if not f then return end
      f:seek("set", old_size); local new_content = f:read("*a"); f:close()
      local lines = vim.split(new_content, "\n", { plain = true, trimempty = true })
      if #lines > 0 then for _, line in ipairs(lines) do table.insert(state.line_queue, line) end; process_line_queue() end
    end)
  end)
  
  log.get().info("Started tailing log file: %s", log_file_path)
end

M.start = start_viewer
M.stop = stop_viewer

return M
