local unl_log = require("UNL.logging")
local ulg_defaults = require("ULG.config.defaults")

local M = {}

local setup_done = false

function M.setup(user_opts)
  if setup_done then return end

  unl_log.setup("ULG", ulg_defaults, user_opts or {})
  local log = unl_log.get("ULG")

  -- ガントチャート用のカスタムハイライトグループを定義
  local gantt_colors = {
    -- 良い感じの色のリスト (https://github.com/sainnhe/gruvbox-material/blob/master/autoload/gruvbox_material.vim などを参考に)
    "#ea6962", -- red
    "#e78a4e", -- orange
    "#d8a657", -- yellow
    "#a9b665", -- green
    "#89b482", -- aqua
    "#7daea3", -- blue
    "#d3869b", -- purple
    "#bd93f9", -- (dracula purple)
    "#ff79c6", -- (dracula pink)
    "#50fa7b", -- (dracula green)
  }
  for i, color in ipairs(gantt_colors) do
    -- fg と bg に同じ色を設定すると、ブロックが見やすくなる
    vim.api.nvim_set_hl(0, "ULGGanttColor" .. i, { fg = color, bg = color })
  end

  local buf_manager = require("ULG.buf")
  buf_manager.setup()

  if log then
    log.debug("ULG.nvim setup complete.")
  end
  
  require("ULG.event.hub").setup()

  setup_done = true
end

return M
