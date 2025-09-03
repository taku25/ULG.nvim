-- lua/ULG/core/tail.lua
-- ファイルの末尾を監視し、変更をコールバックで通知するモジュール

local M = {}

--- tail処理を開始する
-- @param filepath string 監視対象のファイルパス
-- @param interval_ms number ポーリング間隔(ミリ秒)
-- @param on_new_lines function(lines: string[]) 新しい行が見つかったときに呼ばれるコールバック
-- @return table|nil tailerハンドル、またはエラー時にnil
function M.start(filepath, interval_ms, on_new_lines)
  if not vim.fn.filereadable(filepath) == 1 then
    -- ファイルが存在しない場合でも、後から作成される可能性を考慮し、監視は開始する
    vim.notify(("ULG: Log file not found, but will watch for creation: %s"):format(filepath), vim.log.levels.INFO)
  end

  local last_size = (vim.loop.fs_stat(filepath) or { size = 0 }).size

  local watcher = vim.loop.new_fs_poll()
  watcher:start(filepath, interval_ms, function(err, stat)
    if err or not stat or stat.size <= last_size then
      return
    end

    local new_size = stat.size
    local old_size = last_size
    last_size = new_size

    vim.schedule(function()
      local f = io.open(filepath, "r")
      if not f then return end

      f:seek("set", old_size)
      local new_content = f:read("*a")
      f:close()

      local lines = vim.split(new_content, "\n", { plain = true, trimempty = true })
      if #lines > 0 and type(on_new_lines) == "function" then
        on_new_lines(lines)
      end
    end)
  end)

  local handle = {
    stop = function()
      if watcher then
        watcher:stop()
        watcher:close()
        watcher = nil
      end
    end,
    filepath = filepath,
  }
  return handle
end

return M
