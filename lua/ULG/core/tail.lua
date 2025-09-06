-- lua/ULG/core/tail.lua (vim.scheduleに対応した真の最終版)

local M = {}

--- tail処理を開始する
-- @param filepath string 監視対象のファイルパス
-- @param interval_ms number ポーリング間隔(ミリ秒)
-- @param on_new_lines function(lines: string[], is_initial: boolean) 新しい行が見つかったときに呼ばれるコールバック
-- @return table tailerハンドル
function M.start(filepath, interval_ms, on_new_lines)
  local timer = vim.loop.new_timer()
  local last_size = 0
  local attempts = 0
  local max_attempts = 15

  local function stop_tailer()
    if timer then
      timer:close()
      timer = nil
    end
  end

  local function read_and_notify(is_initial)
    local fd = vim.loop.fs_open(filepath, "r", 438)
    if not fd then return end

    local stat = vim.loop.fs_fstat(fd)
    if not stat or stat.size <= last_size then
      vim.loop.fs_close(fd)
      return
    end

    local size_to_read = stat.size - last_size
    vim.loop.fs_read(fd, size_to_read, last_size, function(err, data)
      vim.loop.fs_close(fd)
      if err or not data then return end
      
      data = data:gsub('\r\n', '\n')
      local lines = vim.split(data, "\n", { plain = true, trimempty = true })

      if #lines > 0 and type(on_new_lines) == "function" then
        -- ★★★ これが最後の仕上げだ ★★★
        -- vim.loopのコールバック(高速コンテキスト)から直接コールバックを呼ぶのではなく、
        -- vim.scheduleを介して、次の安全なタイミングで実行するよう予約する。
        vim.schedule(function()
          on_new_lines(lines, is_initial or false)
        end)
      end
      last_size = stat.size
    end)
  end

  local function poll_file()
    local stat = vim.loop.fs_stat(filepath)
    if not stat then
      if attempts < max_attempts then
        attempts = attempts + 1
      else
        vim.notify(("ULG: Log file did not appear after waiting: %s"):format(filepath), vim.log.levels.WARN)
        stop_tailer()
      end
      return
    end
    
    if stat.size > last_size then
      read_and_notify(false)
    end
  end

  if vim.fn.filereadable(filepath) == 1 then
    read_and_notify(true)
  else
    vim.notify(("ULG: Log file not found, but will watch for creation: %s"):format(filepath), vim.log.levels.INFO)
  end

  timer:start(interval_ms, interval_ms, poll_file)

  return {
    stop = stop_tailer,
    filepath = filepath,
  }
end

return M
