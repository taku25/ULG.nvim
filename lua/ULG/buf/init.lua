-- lua/ULG/buf/init.lua (general.luaに対応した最終版)

local unl_log_engine = require("UNL.backend.buf.log")
local ue_log_view = require("ULG.buf.log.ue")
local general_log_view = require("ULG.buf.log.general") -- ★ 参照先を変更
local log = require("ULG.logger")

local M = {}

local ue_log_handle
local general_log_handle -- ★ 変数名を変更

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

function M.setup()
  local conf = require("UNL.config").get("ULG")

  -- TODO: UBT.nvim側で、このイベントのペイロードにファイルパスを含めるようにする
  local unl_events = require("UNL.event.events")
  local unl_event_types = require("UNL.event.types")
  unl_events.subscribe(unl_event_types.ON_BEFORE_BUILD, function(payload)
    -- general.lua を使ってビルドログの追跡を開始する
    if payload and payload.log_file_path and general_log_handle and general_log_handle:is_open() then
      general_log_view.set_title("[[ UBT Build LOG ]]")
      general_log_view.start_tailing(payload.log_file_path)
    end
  end)

  -- 自動閉鎖機能 (変更なし)
  if conf.enable_auto_close then
    local function check_and_close()
      if not (ue_log_handle and ue_log_handle:is_open()) then return end

      local ue_win_id = ue_log_handle:get_win_id()
      -- ★ 変数名を変更
      local general_win_id = (general_log_handle and general_log_handle:get_win_id()) or -1

      for _, win_id in ipairs(vim.api.nvim_list_wins()) do
        if win_id ~= ue_win_id and win_id ~= general_win_id then
          return
        end
      end
      
      log.get().debug("Last normal window closed. Auto-closing ULG console.")
      M.close_console()
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
  if ue_log_handle and ue_log_handle:is_open() then
    vim.api.nvim_set_current_win(ue_log_handle:get_win_id()); return
  end

  local conf = require("UNL.config").get("ULG")
  local handles_to_open = {}
  local layout_cmd

  ue_log_handle = unl_log_engine.create(ue_log_view.create_spec(conf))
  if conf.general_log_enabled then
    general_log_handle = unl_log_engine.create(general_log_view.create_spec(conf))
  end

  local function build_single_window_command(position, size)
    local is_fixed_size = size and size >= 1
    local size_prefix = is_fixed_size and tostring(math.floor(size)) or ""
    local pos_cmd_map = {
      top = "topleft new", left = "topleft vnew",
      right = "botright vnew", tab = "tabnew"
    }
    local pos_cmd = pos_cmd_map[position] or "botright new"
    return size_prefix .. " " .. pos_cmd
  end

  if not conf.general_log_enabled then
    -- UEログ単体の場合
    handles_to_open = { ue_log_handle }
    layout_cmd = build_single_window_command(conf.position, conf.size)
  else
    -- UEログとGeneralログを両方開く場合の、正しいコマンド組み立て
    local commands = {}
    
    -- 1. コンテナとなる水平ウィンドウを作成
    local height = (conf.row_number and conf.row_number >= 1) and tostring(math.floor(conf.row_number)) or ""
    table.insert(commands, " botright "..height .." new" )
    
    -- 2. そのウィンドウを垂直分割
    table.insert(commands, "vsplit")
    
    -- 3. 右側のウィンドウのサイズを指定 (固定サイズの場合のみ)
    if conf.general_log_size and conf.general_log_size >= 1 then
      table.insert(commands, "wincmd l") -- 右に移動
      table.insert(commands, "vertical resize " .. tostring(math.floor(conf.general_log_size)))
    end
    
    layout_cmd = table.concat(commands, " | ")

    -- unl_log_engineは作成順にハンドルを割り当てると仮定
    -- vsplitは左に新しいウィンドウを作るので、左がUE、右がGeneral
    handles_to_open = { ue_log_handle, general_log_handle }
  end

  unl_log_engine.batch_open(handles_to_open, layout_cmd, function(opened_handles)
    if ue_log_handle and ue_log_handle:is_open() then
      ue_log_view.start_tailing(ue_log_handle, filepath, conf)
    end
    if conf.general_log_enabled and general_log_handle and general_log_handle:is_open() then
      general_log_view.set_handle(general_log_handle)
    end
  end)
end

function M.close_console()
  -- ★ 変数名を変更
  if general_log_handle and general_log_handle:is_open() then
    general_log_handle:close()
  end
  if ue_log_handle and ue_log_handle:is_open() then
    ue_log_handle:close()
  end
  general_log_handle, ue_log_handle = nil, nil
end

return M
