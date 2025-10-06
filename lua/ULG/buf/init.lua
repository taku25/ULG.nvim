-- lua/ULG/buf/init.lua (ステートマネージャー対応版)

local unl_log_engine = require("UNL.backend.buf.log")
local ue_log_view = require("ULG.buf.log.ue")
local unl_finder = require("UNL.finder")
local general_log_view = require("ULG.buf.log.general")
local log = require("ULG.logger")
local tail = require("ULG.core.tail")
local view_state = require("ULG.context.view_state")

local M = {}

--------------------------------------------------------------------------------
-- 内部ヘルパー関数
--------------------------------------------------------------------------------

--- OSを判別して、Live Codingのログファイルパスを返す
local function get_live_coding_log_path()
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

--- General Logの監視を停止する
function M.stop_general_tail()
  local s = view_state.get_state("general_log_view")
  if s.tailer then
    s.tailer:stop()
    view_state.update_state("general_log_view", { tailer = nil })
    log.get().debug("Stopped general log tailer.")
  end
end

--- Provider経由で呼び出され、UBTビルドログのデータを表示する
function M.display_ubt_log(opts)
  opts = opts or {}
  M.stop_general_tail()

  local s = view_state.get_state("general_log_view")
  if not (s.handle and s.handle:is_open()) then
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
  M.stop_general_tail()

  local log_path, err = get_live_coding_log_path()
  if err then
    log.get().error(err)
    return
  end

  local s = view_state.get_state("general_log_view")
  if not (s.handle and s.handle:is_open()) then
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
  local new_tailer = tail.start(log_path, 200, on_new_lines)
  view_state.update_state("general_log_view", { tailer = new_tailer })
end

function M.setup()
  local conf = require("UNL.config").get("ULG")
  if conf.enable_auto_close then
    local function check_and_close()
      local ue_s = view_state.get_state("ue_log_view")
      local gen_s = view_state.get_state("general_log_view")
      if not (ue_s.handle and ue_s.handle:is_open()) then return end
      local ue_win_id = ue_s.handle:get_win_id()
      local general_win_id = (gen_s.handle and gen_s.handle:get_win_id()) or -1
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
  local s = view_state.get_state("ue_log_view")
  if s.handle and s.handle:is_open() then
    vim.api.nvim_set_current_win(s.handle:get_win_id())
    return
  end

  local ue_tailer = view_state.get_state("ue_log_view").tailer
  if ue_tailer then ue_tailer:stop() end
  M.stop_general_tail()
  view_state.update_state("ue_log_view", { tailer = nil })

  local conf = require("UNL.config").get("ULG")
  local handles_to_open = {}
  local layout_cmd

  local new_ue_log_handle = unl_log_engine.create(ue_log_view.create_spec(conf))
  local new_general_log_handle
  if conf.general_log_enabled then
    new_general_log_handle = unl_log_engine.create(general_log_view.create_spec(conf))
  end

  local function build_single_window_command(position, size)
    local is_fixed_size = size and size >= 1
    local size_prefix = is_fixed_size and tostring(math.floor(size)) or ""
    local pos_cmd_map = { top = "topleft new", left = "topleft vnew", right = "botright vnew", tab = "tabnew" }
    local pos_cmd = pos_cmd_map[position] or "botright new"
    return size_prefix .. " " .. pos_cmd
  end

  if not conf.general_log_enabled then
    handles_to_open = { new_ue_log_handle }
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
    handles_to_open = { new_ue_log_handle, new_general_log_handle }
  end

  unl_log_engine.batch_open(handles_to_open, layout_cmd, function(opened_handles)
    view_state.update_state("ue_log_view", { handle = new_ue_log_handle })
    view_state.update_state("general_log_view", { handle = new_general_log_handle })
    view_state.update_state("ULG", { is_active = true })

    if filepath and new_ue_log_handle and new_ue_log_handle:is_open() then
      ue_log_view.start_tailing(filepath, conf)
    end
    if conf.general_log_enabled and new_general_log_handle and new_general_log_handle:is_open() then
      M.start_live_coding_log()
    end
    if new_ue_log_handle and new_ue_log_handle:is_open() then
      local ue_win_id = new_ue_log_handle:get_win_id()
      if ue_win_id then
        vim.api.nvim_set_current_win(ue_win_id)
      end
    end
  end)
end

function M.close_console()
  local ue_s = view_state.get_state("ue_log_view")
  local gen_s = view_state.get_state("general_log_view")

  if gen_s.tailer then gen_s.tailer:stop() end
  if ue_s.tailer then ue_s.tailer:stop() end

  if gen_s.handle and gen_s.handle:is_open() then
    gen_s.handle:close()
  end
  if ue_s.handle and ue_s.handle:is_open() then
    ue_s.handle:close()
  end

  view_state.reset_all_states()
end

return M
