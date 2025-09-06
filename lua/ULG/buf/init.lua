-- lua/ULG/buf/init.lua (真の監視システムを搭載した最終版)

local unl_log_engine = require("UNL.backend.buf.log")
local ue_log_view = require("ULG.buf.log.ue")
local build_log_view = require("ULG.buf.log.build")
local log = require("ULG.logger")

local M = {}

local ue_log_handle
local build_log_handle

function M.setup()
  local conf = require("UNL.config").get("ULG")

  -- イベントの購読 (変更なし)
  local unl_events = require("UNL.event.events")
  local unl_event_types = require("UNL.event.types")
  unl_events.subscribe(unl_event_types.ON_BEFORE_BUILD, function(payload)
    if payload and payload.log_file_path then build_log_view.start_tailing(payload.log_file_path) end
  end)

  -- ★★★ ここが、監視システムの正しい設置場所です ★★★
  if conf.enable_auto_close then
    local function check_and_close()
      if not (ue_log_handle and ue_log_handle:is_open()) then return end

      local ue_win_id = ue_log_handle:get_win_id()
      local build_win_id = (build_log_handle and build_log_handle:get_win_id()) or -1

      for _, win_id in ipairs(vim.api.nvim_list_wins()) do
        if win_id ~= ue_win_id and win_id ~= build_win_id then
          -- 作業ウィンドウが一つでも見つかったら、何もしない
          return
        end
      end
      
      -- ULGウィンドウしか残っていなければ、帰港命令を発する
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
  -- ★★★ 監視システム、設置完了 ★★★

  log.get().debug("ULG Buffer Manager initialized.")
end

-- (open_console と close_console は、あなたの最新版のままで変更ありません)
function M.open_console(filepath)
  if ue_log_handle and ue_log_handle:is_open() then
    vim.api.nvim_set_current_win(ue_log_handle:get_win_id()); return
  end

  local conf = require("UNL.config").get("ULG")
  local handles_to_open = {}
  local layout_cmd

  ue_log_handle = unl_log_engine.create(ue_log_view.create_spec(conf))
  if conf.build_log_enabled then
    build_log_handle = unl_log_engine.create(build_log_view.create_spec(conf))
  end

  local ue_pos = conf.position
  local ue_abs_cmd
  if ue_pos == "tab" then ue_abs_cmd = "tabnew"
  elseif ue_pos == "top" then ue_abs_cmd = "topleft new"
  elseif ue_pos == "left" then ue_abs_cmd = "topleft vnew"
  elseif ue_pos == "right" then ue_abs_cmd = "botright vnew"
  else ue_abs_cmd = "botright new" end

  if not conf.build_log_enabled then
    handles_to_open = { ue_log_handle }
    layout_cmd = ue_abs_cmd
  else
    local build_pos = conf.build_log_position
    if build_pos == 'primary' or build_pos == 'secondary' then
      local base_cmd, relative_cmd
      local base_handle, relative_handle
      local is_base_horizontal = (ue_pos == "top" or ue_pos == "bottom")

      if build_pos == 'primary' then
        base_handle = build_log_handle
        relative_handle = ue_log_handle
        base_cmd = ue_abs_cmd
        relative_cmd = is_base_horizontal and "aboveleft vnew" or "aboveleft new"
      else -- 'secondary'
        base_handle = ue_log_handle
        relative_handle = build_log_handle
        base_cmd = ue_abs_cmd
        relative_cmd = is_base_horizontal and "rightbelow vnew" or "rightbelow new"
      end
      handles_to_open = { base_handle, relative_handle }
      layout_cmd = base_cmd .. " | " .. relative_cmd
    else
      local build_abs_cmd
      if build_pos == "tab" then build_abs_cmd = "tabnew"
      elseif build_pos == "top" then build_abs_cmd = "topleft new"
      elseif build_pos == "left" then build_abs_cmd = "topleft vnew"
      elseif build_pos == "right" then build_abs_cmd = "botright vnew"
      else build_abs_cmd = "botright new" end
      handles_to_open = { ue_log_handle, build_log_handle }
      layout_cmd = ue_abs_cmd .. " | " .. build_abs_cmd
    end
  end
  
  unl_log_engine.batch_open(handles_to_open, layout_cmd, function(opened_handles)
    if ue_log_handle and ue_log_handle:is_open() then
      ue_log_view.start_tailing(ue_log_handle, filepath, conf)
    end
    if conf.build_log_enabled and build_log_handle and build_log_handle:is_open() then
      build_log_view.set_handle(build_log_handle)
    end
  end)
end

--
function M.stop_all_tailing()
  log.get().info("Stopping all log tailing.")
  if ue_log_handle and ue_log_handle:is_open() then
    ue_log_view.stop_tailing()
  end
  if build_log_handle and build_log_handle:is_open() then
    build_log_view.stop_tailing()
  end
end

-- ★★★ この関数が「全艦、帰投せよ！」の役割を担う ★★★
function M.close_console()
  if build_log_handle and build_log_handle:is_open() then
    -- build.luaのcloseを呼ぶのではなく、直接ハンドルから閉じるのが司令官の役割
    build_log_handle:close()
  end
  if ue_log_handle and ue_log_handle:is_open() then
    ue_log_handle:close()
  end
  build_log_handle, ue_log_handle = nil, nil
end
return M
