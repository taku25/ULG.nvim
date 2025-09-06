-- lua/ULG/cmd/start.lua (司令室・最終完成版)

local unl_finder = require("UNL.finder")
local unl_picker = require("UNL.backend.picker")
local buf_manager = require("ULG.buf") -- ★ 新しい司令官をrequire
local log = require("ULG.logger")

local M = {}

-- (find_log_files ヘルパーは変更なし)
local function find_log_files(dir)
  if vim.fn.executable("fd") == 1 then
    local cmd = { "fd", "--type", "f", "--absolute-path", ".", dir }
    local output = vim.fn.system(cmd)
    if vim.v.shell_error == 0 and output and output:match("%S") then
      return vim.split(output, "\n", { plain = true, trimempty = true })
    end
  end
  local files = {}
  local function find_recursive(current_dir)
    local iter = vim.fs.dir(current_dir, { on_error = function() end })
    if not iter then return end
    for file, type in iter do
      local full_path = vim.fs.joinpath(current_dir, file)
      if type == "file" then table.insert(files, full_path)
      elseif type == "directory" then find_recursive(full_path) end
    end
  end
  find_recursive(dir)
  return files
end

function M.execute(opts)
  opts = opts or {}
  
  -- ★ このコマンドは、常にUEログを開くためのものである、という責務が明確になった
  local function start_with_file(filepath)
    -- ★★★ 司令官の `open_console` を呼び出す ★★★
    buf_manager.open_console(filepath)
  end

  local project_root = unl_finder.project.find_project_root(vim.loop.cwd())
  if not project_root then return log.get().error("Not in an Unreal Engine project.") end
  local logs_dir = project_root .. "/Saved/Logs/"

  if opts.has_bang then
    local log_files = find_log_files(logs_dir)
    if #log_files == 0 then return log.get().warn("No log files found in %s", logs_dir) end
    table.sort(log_files, function(a, b)
      local stat_a, stat_b = vim.loop.fs_stat(a), vim.loop.fs_stat(b)
      if stat_a and stat_b then return stat_a.mtime.sec > stat_b.mtime.sec end
      return false
    end)
    unl_picker.pick({
      kind = "ulg_select_log_file", title = "Select Log File to View",
      conf = require("UNL.config").get("ULG"), items = log_files,
      on_submit = function(selected_file)
        if selected_file then start_with_file(selected_file) end
      end,
    })
  else
    local uproject_path = unl_finder.project.find_project_file(project_root)
    if not uproject_path then
      log.get().warn("Could not find .uproject file. Opening picker instead.")
      M.execute({ has_bang = true }); return
    end
    local project_name = vim.fn.fnamemodify(uproject_path, ":t:r")
    local default_log_file = logs_dir .. project_name .. ".log"
    start_with_file(default_log_file)
  end
end

return M
