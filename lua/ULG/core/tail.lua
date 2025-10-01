-- lua/ULG/core/tail.lua (fs_pollを使った最終版)

local M = {}

--- tail処理を開始する
-- @param filepath string 監視対象のファイルパス
-- @param interval_ms number ポーリング間隔(ミリ秒)
-- @param on_new_lines function(lines: string[], is_initial: boolean) 新しい行が見つかったときに呼ばれるコールバック
-- @return table|nil tailerハンドル
function M.start(filepath, interval_ms, on_new_lines)
  local poll_handle = vim.loop.new_fs_poll()
  if not poll_handle then
    vim.notify("ULG: Failed to create fs_poll handle.", vim.log.levels.ERROR)
    return
  end

  local last_size = -1 -- 初回読み込みを確実に行うために-1で初期化

  -- 監視を停止するためのハンドル
  local tailer = {
    filepath = filepath,
    stop = function()
      if poll_handle and not poll_handle:is_closing() then
        poll_handle:stop()
      end
    end,
  }

  -- ファイルの新しい部分を読み込んでコールバックを呼ぶ関数
  local function read_new_content(is_initial)
    local current_size = vim.fn.getfsize(filepath)
    if current_size < 0 then return end -- ファイルが存在しない

    if last_size == -1 then -- 初回実行時
      last_size = is_initial and 0 or current_size
    end

    if current_size <= last_size then
        last_size = current_size
        return
    end

    local fd = vim.loop.fs_open(filepath, "r", 438)
    if not fd then return end

    local size_to_read = current_size - last_size
    vim.loop.fs_read(fd, size_to_read, last_size, function(err, data)
      vim.loop.fs_close(fd)
      if err or not data then return end

      data = data:gsub('\r\n', '\n')
      local lines = vim.split(data, "\n", { plain = true, trimempty = true })

      if #lines > 0 and type(on_new_lines) == "function" then
        vim.schedule(function()
          on_new_lines(lines, is_initial or false)
        end)
      end
      last_size = current_size
    end)
  end

  -- fs_pollのコールバック
  local poll_callback = function(err, stat, prev_stat)
    if err then
      -- 例: ファイルが削除されたなど
      tailer.stop()
      return
    end

    if prev_stat.size ~= stat.size then
      read_new_content(false)
    end
  end

  -- 監視を開始
  poll_handle:start(filepath, interval_ms, poll_callback)

  -- 起動時にファイルが既に存在する場合、最初の内容を読み込む
  if vim.fn.filereadable(filepath) == 1 then
    read_new_content(true)
  else
    vim.notify(("ULG: Log file not found, but will watch for creation: %s"):format(filepath), vim.log.levels.INFO)
    last_size = 0 -- ファイル作成時に最初から読めるように0に設定
  end

  return tailer
end

return M
