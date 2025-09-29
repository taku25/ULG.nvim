-- lua/ULG/provider/init.lua (新規作成)
local unl_log = require("UNL.logging")
local log = require("ULG.logger")

local M = {}

M.setup = function()
  local unl_api_ok, unl_api = pcall(require, "UNL.api")
  if unl_api_ok then
    local trace_provider = require("ULG.provider.trace")
    unl_api.provider.register({
      capability = "ulg.get_pending_trace_request",
      name = "ULG.nvim",
      impl = trace_provider, 
    })


    unl_api.provider.register({
      capability = "ulg.build_log",
      name = "ULG.nvim",
      impl = {
        notify = function(opts)

          local general_log = require("ULG.buf.log.general")
          opts = opts or {}

          -- generalログが開いていなければ、自動で開く
          if general_log.is_open() then
            -- 1. clearフラグがあれば、バッファをクリアする
            if opts.clear then
              general_log.clear_buffer()
              -- UBT側でタイトルも設定したければ、ここで受け取って設定も可能
              --例: if opts.title then general_log.set_title(opts.title) end
            end

            -- 2. linesがあれば、バッファに追記する
            if opts.lines and #opts.lines > 0 then
              general_log.append_lines(opts.lines)
            end

          end
        end,
     },
    })
    log.get().info("Registered ULG providers to UNL.nvim.")
  end
end

return M
