-- lua/ULG/buf/init.lua

local unl_log_engine = require("UNL.backend.buf.log")
local ue_log_view = require("ULG.buf.log.ue")
local unl_finder = require("UNL.finder")
local general_log_view = require("ULG.buf.log.general")
local log = require("ULG.logger")
local tail = require("ULG.core.tail")
local view_state = require("ULG.context.view_state")

local M = {}

local ue_log_handle
local general_log_handle
local current_tailer = nil

--------------------------------------------------------------------------------
-- 内部ヘルパー関数
--------------------------------------------------------------------------------

--- OSを判別して、Live Codingのログファイルパスを返す
local function get_live_coding_log_path()
   -- local candidate_paths = {}
  local candidate_paths = {}
  if vim.fn.has("win32") == 1 then
    local project = unl_finder.project.find_project(vim.loop.cwd())
    if project and project.uproject then
      local engine_root = unl_finder.engine.find_engine_root(project.uproject)
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
      print(path)
      log.get().debug("Auto-detected Live Coding log path: %s", path)
      return path, nil
    end
  end
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

--- 現在実行中のログ監視があれば停止する
function M.stop_current_tail()
  if current_tailer then
    current_tailer:stop()
    current_tailer = nil
    log.get().debug("Stopped current log tailer.")
  end
end

--- Provider経由で呼び出され、UBTビルドログのデータを表示する
function M.display_ubt_log(opts)
  opts = opts or {}
  M.stop_current_tail()

  if not (general_log_handle and general_log_handle:is_open()) then
    return
  end

  if opts.clear then
    general_log_view.clear_buffer()
    general_log_view.set_title("[[ UBT Build LOG ]]")
  end
  if opts.lines and #opts.lines > 0 then
    general_log_view.append_lines(opts.lines)
  end
end

--- Live Codingログの監視を開始する
function M.start_live_coding_log()
  M.stop_current_tail()

  local log_path, err = get_live_coding_log_path()
  if err then
    log.get().error(err); return
  end


  if not (general_log_handle and general_log_handle:is_open()) then
    return
  end

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
  current_tailer = tail.start(log_path, 200, on_new_lines)
end

function M.setup()
  local conf = require("UNL.config").get("ULG")
  if conf.enable_auto_close then
    local function check_and_close()
      if not (ue_log_handle and ue_log_handle:is_open()) then return end
      local ue_win_id = ue_log_handle:get_win_id()
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

function M.open_console(filepath) -- filepath は nil の可能性がある
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
    local pos_cmd_map = { top = "topleft new", left = "topleft vnew", right = "botright vnew", tab = "tabnew" }
    local pos_cmd = pos_cmd_map[position] or "botright new"
    return size_prefix .. " " .. pos_cmd
  end

  if not conf.general_log_enabled then
    handles_to_open = { ue_log_handle }
    layout_cmd = build_single_window_command(conf.position, conf.size)
  else
    local commands = {}
    local height = (conf.row_number and conf.row_number >= 1) and tostring(math.floor(conf.row_number)) or ""
    table.insert(commands, " botright " .. height .. " new")
    table.insert(commands, "vsplit")
    if conf.general_log_size and conf.general_log_size >= 1 then
      table.insert(commands, "wincmd l")
      table.insert(commands, "vertical resize " .. tostring(math.floor(conf.general_log_size)))
    end
    layout_cmd = table.concat(commands, " | ")
    handles_to_open = { ue_log_handle, general_log_handle }
  end

  unl_log_engine.batch_open(handles_to_open, layout_cmd, function(opened_handles)
    if filepath and ue_log_handle and ue_log_handle:is_open() then
      ue_log_view.start_tailing(ue_log_handle, filepath, conf)
    end
    if conf.general_log_enabled and general_log_handle and general_log_handle:is_open() then
      general_log_view.set_handle(general_log_handle)
      M.start_live_coding_log()
    end
    if ue_log_handle and ue_log_handle:is_open() then
      local ue_win_id = ue_log_handle:get_win_id()
      if ue_win_id then
        vim.api.nvim_set_current_win(ue_win_id)
      end
    end
  end)
end

function M.close_console()
  M.stop_current_tail()
  if general_log_handle and general_log_handle:is_open() then
    general_log_handle:close()
  end
  if ue_log_handle and ue_log_handle:is_open() then
    ue_log_handle:close()
  end
  general_log_handle, ue_log_handle, current_tailer = nil, nil, nil
  view_state.update_state({ is_watching = false });
end

return M
