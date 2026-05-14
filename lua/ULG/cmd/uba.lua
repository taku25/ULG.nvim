-- lua/ULG/cmd/uba.lua
-- .uba build trace ファイルをピッカーで選択し、UNLスキャナーでパースして表示する

local log_finder  = require("ULG.finder.log")
local unl_picker  = require("UNL.picker")
local buf_manager = require("ULG.buf")
local log         = require("ULG.logger")

local M = {}

--- .uba ファイルを非同期でパースし、general_log タブに表示する
---@param file_path string  絶対パス
local function parse_and_display(file_path)
  local scanner = require("UNL.scanner")
  local binary  = scanner.get_binary_path()
  if not binary then
    vim.notify("ULG: unl-scanner binary not found. Please build UNL.nvim.", vim.log.levels.ERROR)
    return
  end

  local fname = vim.fs.basename(file_path)
  local lines = {}

  vim.fn.jobstart({ binary, "uba-parse", file_path }, {
    on_stdout = function(_, data)
      if data then
        for _, chunk in ipairs(data) do
          if chunk ~= "" then
            -- jobstart may embed \n; split each chunk into individual lines
            for _, line in ipairs(vim.split(chunk, "\n", { plain = true })) do
              table.insert(lines, line)
            end
          end
        end
      end
    end,
    on_stderr = function(_, data)
      if data then
        for _, line in ipairs(data) do
          if line ~= "" then
            log.get().warn("uba-parse stderr: %s", line)
          end
        end
      end
    end,
    on_exit = function(_, code)
      if code ~= 0 then
        vim.notify(("ULG: uba-parse exited with code %d"):format(code), vim.log.levels.WARN)
      end
      vim.schedule(function()
        -- まずコンソールを開く（まだ開いていない場合）
        buf_manager.open_console(nil)
        -- 少し待ってからバッファが初期化されるのを待つ
        vim.defer_fn(function()
          buf_manager.display_ubt_log({
            lines = lines,
            title = ("[[ UBA Trace: %s ]]"):format(fname),
            clear = true,
          })
        end, 50)
      end)
    end,
    stdout_buffered = false,
  })
end

--- .uba ファイルの一覧を取得し、最新ファイルを直接パース表示する
function M.execute()
  local uba_files = log_finder.find_uba_logs()
  if #uba_files == 0 then
    vim.notify("ULG: No .uba build trace files found.", vim.log.levels.INFO)
    return
  end

  -- 更新日時の新しい順にソート → 先頭が最新
  table.sort(uba_files, function(a, b)
    local sa = vim.loop.fs_stat(a)
    local sb = vim.loop.fs_stat(b)
    if sa and sb then return sa.mtime.sec > sb.mtime.sec end
    return false
  end)

  parse_and_display(uba_files[1])
end

--- Picker でファイルを選択して表示する (bang 版)
function M.execute_pick()
  local uba_files = log_finder.find_uba_logs()
  if #uba_files == 0 then
    vim.notify("ULG: No .uba build trace files found.", vim.log.levels.INFO)
    return
  end

  table.sort(uba_files, function(a, b)
    local sa = vim.loop.fs_stat(a)
    local sb = vim.loop.fs_stat(b)
    if sa and sb then return sa.mtime.sec > sb.mtime.sec end
    return false
  end)

  unl_picker.open({
    kind            = "ulg_select_uba_log",
    title           = "Select UBA Build Trace",
    preview_enabled = false,
    conf            = require("UNL.config").get("ULG"),
    items           = uba_files,
    on_submit = function(selected_file)
      if selected_file then
        parse_and_display(selected_file)
      end
    end,
  })
end

return M
