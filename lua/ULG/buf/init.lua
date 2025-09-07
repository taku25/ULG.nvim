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
  
  -- ★ 設定名を変更 (general_log_enabled)
  if conf.general_log_enabled then
    general_log_handle = unl_log_engine.create(general_log_view.create_spec(conf))
  end

  -- ★ 設定名を変更 (position)
  local ue_pos = conf.position
  local ue_abs_cmd
  if ue_pos == "tab" then ue_abs_cmd = "tabnew"
  elseif ue_pos == "top" then ue_abs_cmd = "topleft new"
  elseif ue_pos == "left" then ue_abs_cmd = "topleft vnew"
  elseif ue_pos == "right" then ue_abs_cmd = "botright vnew"
  else ue_abs_cmd = "botright new" end

  if not conf.general_log_enabled then
    handles_to_open = { ue_log_handle }
    layout_cmd = ue_abs_cmd
  else
    -- ★ 設定名を変更 (general_log_position)
    local general_pos = conf.general_log_position
    if general_pos == 'primary' or general_pos == 'secondary' then
      local base_cmd, relative_cmd
      local base_handle, relative_handle
      local is_base_horizontal = (ue_pos == "top" or ue_pos == "bottom")

      if general_pos == 'primary' then
        base_handle = general_log_handle -- ★ 変数名を変更
        relative_handle = ue_log_handle
        base_cmd = ue_abs_cmd
        relative_cmd = is_base_horizontal and "aboveleft vnew" or "aboveleft new"
      else -- 'secondary'
        base_handle = ue_log_handle
        relative_handle = general_log_handle -- ★ 変数名を変更
        base_cmd = ue_abs_cmd
        relative_cmd = is_base_horizontal and "rightbelow vnew" or "rightbelow new"
      end
      handles_to_open = { base_handle, relative_handle }
      layout_cmd = base_cmd .. " | " .. relative_cmd
    else
      local general_abs_cmd
      if general_pos == "tab" then general_abs_cmd = "tabnew"
      elseif general_pos == "top" then general_abs_cmd = "topleft new"
      elseif general_pos == "left" then general_abs_cmd = "topleft vnew"
      elseif general_pos == "right" then general_abs_cmd = "botright vnew"
      else general_abs_cmd = "botright new" end
      handles_to_open = { ue_log_handle, general_log_handle } -- ★ 変数名を変更
      layout_cmd = ue_abs_cmd .. " | " .. general_abs_cmd
    end
  end
  
  unl_log_engine.batch_open(handles_to_open, layout_cmd, function(opened_handles)
    if ue_log_handle and ue_log_handle:is_open() then
      ue_log_view.start_tailing(ue_log_handle, filepath, conf)
    end
    -- ★ 変数名と参照先を変更
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
