local unl_finder = require("UNL.finder")
local unl_picker = require("UNL.backend.picker")
local viewer = require("ULG.viewer")
local log = require("ULG.logger")

local M = {}

function M.execute(opts)
  opts = opts or {}
  
  -- ★★★ 変更点: find_projectではなく、find_project_rootを先に呼び出す ★★★
  local project_root = unl_finder.project.find_project_root(vim.loop.cwd())
  if not project_root then
    return log.get().error("Not in an Unreal Engine project.")
  end
  
  local logs_dir = project_root .. "/Saved/Logs/"

  -- Case 1: `!`付きの場合 -> ピッカーで選択
  if opts.has_bang then
    unl_picker.pick({
      kind = "ulg_select_log_file",
      title = "Select Log File to View",
      conf = require("UNL.config").get("ULG"),
      exec_cmd = { "fd", "--type", "f", ".", logs_dir },
      on_submit = function(selected_file)
        if selected_file then
          viewer.start(selected_file)
        end
      end,
    })
  -- Case 2: `!`なしの場合 -> デフォルトのログをテイル
  else
    -- ★★★ 変更点: プロジェクト名を安全に取得 ★★★
    local uproject_path = unl_finder.project.find_project_file(project_root)
    if not uproject_path then
      log.get().warn("Could not find .uproject file to determine default log. Opening picker instead.")
      M.execute({ has_bang = true }) -- フォールバック
      return
    end
    
    local project_name = vim.fn.fnamemodify(uproject_path, ":t:r")
    local default_log_file = logs_dir .. project_name .. ".log"
    
    viewer.start(default_log_file)
  end
end

return M
