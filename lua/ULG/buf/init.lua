local unl_log_engine = require("UNL.backend.buf.log")
local ue_log_view = require("ULG.buf.log.ue")
local unl_finder = require("UNL.finder")
local general_log_view = require("ULG.buf.log.general")
local log = require("ULG.logger")
local tail = require("ULG.core.tail")
local view_state = require("ULG.context.view_state")
local unl_config = require("UNL.config")
local M = {}

-- 現在のアクティブなタブ ("ue" or "general")
local current_tab = "ue"
local main_win_id = nil

--------------------------------------------------------------------------------
-- 内部ヘルパー関数
--------------------------------------------------------------------------------

local function get_live_coding_log_path()
  local candidate_paths = {}
  if vim.fn.has("win32") == 1 then
    local project = unl_finder.project.find_project(vim.loop.cwd())
    if project and project.uproject then
      local engine_root = unl_finder.engine.find_engine_root(project.uproject, {
        engine_override_path = unl_config.get("ULG").engine_path,
      })
      if engine_root then
        table.insert(candidate_paths, engine_root .. "/Engine/Programs/UnrealBuildTool/Log.txt")
      end
    end
    local local_appdata = os.getenv("LOCALAPPDATA")
    if not local_appdata then return nil, "Could not get LOCALAPPDATA environment variable." end
    table.insert(candidate_paths, local_appdata .. "\\UnrealBuildTool\\Log.txt")
  elseif vim.fn.has("mac") == 1 then
    local home = os.getenv("HOME")
    if not home then return nil, "Could not get HOME directory." end
    return home .. "/Library/Logs/UnrealBuildTool/Log.txt"
  else
    local home = os.getenv("HOME")
    if not home then return nil, "Could not get HOME directory." end
    return home .. "/.config/UnrealBuildTool/Log.txt"
  end
  for _, path in ipairs(candidate_paths) do
    if vim.fn.filereadable(path) == 1 then
      return path, nil
    end
  end
  return nil, "Live Coding log file not found."
end

-- Winbarを更新する関数
local function update_winbar()
    if not main_win_id or not vim.api.nvim_win_is_valid(main_win_id) then return end
    
    local hl_active   = "%#UNXTabActive#"   
    local hl_inactive = "%#UNXTabInactive#"
    local hl_sep      = "%#UNXTabSeparator#"
    
    if vim.fn.hlexists("UNXTabActive") == 0 then
        hl_active = "%#TabLineSel#"; hl_inactive = "%#TabLine#"; hl_sep = "%#NonText#"
    end

    local text = " "
    
    -- UE Log Tab
    if current_tab == "ue" then
        text = text .. hl_active .. " Unreal Engine Log "
    else
        text = text .. hl_inactive .. " Unreal Engine Log "
    end
    
    text = text .. hl_sep .. " | "
    
    -- General Log Tab
    if current_tab == "general" then
        text = text .. hl_active .. " General/Build Log "
    else
        text = text .. hl_inactive .. " General/Build Log "
    end
    
    pcall(vim.api.nvim_win_set_option, main_win_id, "winbar", text)
end

-- タブを切り替える関数
local function switch_tab(target)
    if current_tab == target then return end
    if not main_win_id or not vim.api.nvim_win_is_valid(main_win_id) then return end
    
    local ue_s = view_state.get_state("ue_log_view")
    local gen_s = view_state.get_state("general_log_view")
    
    if target == "ue" and ue_s.handle then
        ue_s.handle:attach_to_win(main_win_id)
        current_tab = "ue"
    elseif target == "general" and gen_s.handle then
        gen_s.handle:attach_to_win(main_win_id)
        current_tab = "general"
    end
    
    update_winbar()
end

-- ★★★ クリックハンドラ (位置計算) ★★★
local function handle_tab_click()
    local mouse = vim.fn.getmousepos()
    
    -- メインウィンドウのWinBar(line=0)以外は無視
    if mouse.winid ~= main_win_id or mouse.line ~= 0 then return end
    
    local col = mouse.wincol
    local strwidth = vim.fn.strdisplaywidth

    -- テキスト構成要素の幅を計算
    -- (update_winbar で設定している文字列と同じ内容で計算)
    local padding_w = strwidth(" ")
    local tab1_text = " Unreal Engine Log "
    local tab1_w = strwidth(tab1_text)
    
    local sep_text = " | "
    local sep_w = strwidth(sep_text)
    
    local tab2_text = " General/Build Log "
    local tab2_w = strwidth(tab2_text)

    -- 判定ロジック
    local current_x = padding_w
    
    -- UE Log タブの範囲: start ~ start + width
    if col >= current_x and col < (current_x + tab1_w) then
        switch_tab("ue")
        return
    end
    
    current_x = current_x + tab1_w + sep_w
    
    -- General Log タブの範囲
    if col >= current_x and col < (current_x + tab2_w) then
        switch_tab("general")
        return
    end
end

-- タブ切り替え用のキーマップを設定
local function setup_tab_keymaps(buf)
    local opts = { noremap = true, silent = true, buffer = buf }
    
    -- Tabキーでトグル
    vim.keymap.set("n", "<Tab>", function()
        local next_tab = (current_tab == "ue") and "general" or "ue"
        switch_tab(next_tab)
    end, opts)
    
    -- ★修正: クリック対応
    vim.keymap.set("n", "<LeftMouse>", handle_tab_click, opts)
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

function M.stop_general_tail()
  local s = view_state.get_state("general_log_view")
  if s.tailer then
    s.tailer:stop()
    view_state.update_state("general_log_view", { tailer = nil })
    log.get().debug("Stopped general log tailer.")
  end
end

function M.display_ubt_log(opts)
  opts = opts or {}
  M.stop_general_tail()
  local s = view_state.get_state("general_log_view")
  
  if s.handle then
    if opts.clear then
      general_log_view.clear_buffer()
      general_log_view.set_title("[[ UBT Build LOG ]]")
    end
    if opts.lines and #opts.lines > 0 then
      general_log_view.append_lines(opts.lines)
    end
    
    -- ビルドログが流れてきたら自動的にタブを切り替える (お好みで有効化)
    -- if current_tab ~= "general" then switch_tab("general") end
  end
end

function M.start_live_coding_log()
  M.stop_general_tail()
  local log_path, err = get_live_coding_log_path()
  if err then
    log.get().debug(err)
    return
  end

  local s = view_state.get_state("general_log_view")
  if not s.handle then return end

  local on_new_lines = function(lines)
    for _, line in ipairs(lines) do
      if line:find("Log started at", 1, true) then
        general_log_view.clear_buffer()
        general_log_view.set_title("[[ Live Coding LOG ]]")
        general_log_view.append_lines("--- Live Coding Patch Started ---")
      end
      general_log_view.append_lines(line)
    end
  end

  log.get().info("Starting to tail Live Coding log: %s", log_path)
  local new_tailer = tail.start(log_path, 200, on_new_lines)
  view_state.update_state("general_log_view", { tailer = new_tailer })
end

function M.setup()
  local conf = require("UNL.config").get("ULG")
  if conf.enable_auto_close then
    local function check_and_close()
      if main_win_id and not vim.api.nvim_win_is_valid(main_win_id) then
           M.close_console()
      end
    end
    local augroup = vim.api.nvim_create_augroup("ULGAutoClose", { clear = true })
    vim.api.nvim_create_autocmd({ "WinClosed", "BufWipeout" }, {
      group = augroup,
      pattern = "*",
      callback = function() vim.schedule(check_and_close) end,
    })
  end
  log.get().debug("ULG Buffer Manager initialized.")
end

function M.open_console(filepath)
  if main_win_id and vim.api.nvim_win_is_valid(main_win_id) then
    vim.api.nvim_set_current_win(main_win_id)
    return
  end

  local conf = require("UNL.config").get("ULG")
  
  if not unl_log_engine then
      log.get().error("UNL log engine not loaded.")
      return
  end

  local new_ue_log_handle = unl_log_engine.create(ue_log_view.create_spec(conf))
  local ue_buf = new_ue_log_handle:setup_buffer()
  setup_tab_keymaps(ue_buf)

  local new_general_log_handle = nil
  if conf.general_log_enabled then
    new_general_log_handle = unl_log_engine.create(general_log_view.create_spec(conf))
    local gen_buf = new_general_log_handle:setup_buffer()
    setup_tab_keymaps(gen_buf)
  end

  local pos = conf.position or "bottom"
  local size = conf.row_number or 15
  local cmd = "botright " .. size .. "new"
  if pos == "right" then cmd = "botright vertical 40new" end

  vim.cmd(cmd)
  main_win_id = vim.api.nvim_get_current_win()
  
  vim.api.nvim_set_option_value("number", false, { win = main_win_id })
  vim.api.nvim_set_option_value("relativenumber", false, { win = main_win_id })
  
  view_state.update_state("ue_log_view", { handle = new_ue_log_handle })
  view_state.update_state("general_log_view", { handle = new_general_log_handle })
  view_state.update_state("ULG", { is_active = true })

  current_tab = "ue"
  new_ue_log_handle:attach_to_win(main_win_id)
  update_winbar()

  if filepath then
      ue_log_view.start_tailing(filepath, conf)
  end
  if conf.general_log_enabled then
      M.start_live_coding_log()
  end
end

function M.close_console()
  if main_win_id and vim.api.nvim_win_is_valid(main_win_id) then
    vim.api.nvim_win_close(main_win_id, true)
  end
  main_win_id = nil

  local ue_s = view_state.get_state("ue_log_view")
  local gen_s = view_state.get_state("general_log_view")

  if gen_s.tailer then gen_s.tailer:stop() end
  if ue_s.tailer then ue_s.tailer:stop() end

  if ue_s.handle then ue_s.handle:close() end
  if gen_s.handle then gen_s.handle:close() end

  view_state.reset_all_states()
end

function M.stop_all_tailing()
  local ue_s = view_state.get_state("ue_log_view")
  if ue_s.tailer then
    ue_s.tailer:stop()
    view_state.update_state("ue_log_view", { tailer = nil, is_watching = false })
  end
  M.stop_general_tail()
end

return M
