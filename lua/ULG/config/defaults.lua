local M = {
  logging = {
    level = "info",
    echo = { level = "warn" },
    notify = { level = "error", prefix = "[ULG]" },
    file = { enable = true, max_kb = 512, rotate = 3, filename = "ulg.log" },
    perf = { enabled = false, patterns = { "^refresh" }, level = "trace" },
  },
  cache = { dirname = "ULG" },
  ui = {
    picker = {
      mode = "auto",
      prefer = { "telescope", "fzf-lua", "native", "dummy" },
    },
  },

  vertical_size = 80,
  horizontal_size = 15,
  win_open_command = nil,
  filetype = "unreal-log",
  auto_scroll = true,

  -- ★ UEログ (Primary) の配置設定
  position = "bottom", -- "right", "left", "bottom", "top", "tab"
  size = 0.25, -- 画面全体に対する高さ/幅の割合 (0.0 ~ 1.0)

  -- ★ ビルドログ (Secondary) の配置設定
  build_log_enabled = true,
  -- "primary", "secondary",  (相対指定)
  -- または "bottom", "top", "left", "right", "tab" (絶対指定) が可能
  build_log_position = "secondary", 
  build_log_size = 0.4, -- ue_logウィンドウ(相対)または画面全体(絶対)に対する割合

  polling_interval_ms = 500,
  render_chunk_size = 500,
  hide_timestamp = true,

  enable_auto_close = true,
  keymaps = {
    filter_prompt = "s",
    filter_clear = "<Esc>",
    toggle_timestamp = "i",
    clear_content = "c",
    category_filter_prompt = "f",
    jump_to_source = "<CR>",
    filter_toggle = "t",
    search_prompt = "p",
    remote_command_prompt = "P",
    jump_next_match = "]f",
    jump_prev_match = "[f",
    toggle_build_log = "b",
    show_help = "?",
  },

  category_filters = {},
  help = {
    border = "rounded",
  },


  highlights = {
    enabled = true,
    groups = {
      ULGTimestamp = {
        pattern = '\\v^\\[[0-9\\.\\-:]+\\]\\[[ 0-9]+\\]',
        hl_group = "Comment",
        priority = 30,
      },
      ULGErrorLine = {
        pattern = [[\v.*([Ee]rror|\[[Ee]rror\]).*]],
        hl_group = "ErrorMsg",
        priority = 20,
      },
      ULGWarningLine = {
        pattern = [[\v.*([Ww]arning|\[[Ww]arning\]).*]],
        hl_group = "DiagnosticWarn",
        priority = 21,
      },
      ULGSuccessLine = {
        pattern = [[\v.*([Ss]uccess|\[[Ss]uccess\]).*]],
        hl_group = "DiffAdd",
        priority = 22,
      },
      ULGCategory = {
        -- MODIFIED: Require at least two characters to avoid matching drive letters like "C:"
        pattern = [[\v[a-zA-Z][a-zA-Z0-9_]+:]],
        hl_group = "Identifier",
        priority = 100,
      },
      ULGFilePath = {
        -- This rule is for JUMPABLE file paths with line and column numbers.
        pattern = [[\v(\~|[A-Z]:)[\/\\][^()\[\]\r\n]+\.\w+]] ,
        hl_group = "Underlined",
        priority = 110,
      },
    },
  },

  remote = {
    host = "127.0.0.1",
    port = 30010,
    commands = {
      "livecoding.compile",
      "stat fps",
      "stat unit",
      "stat gpu",
      "stat cpu",
      "stat none",
    },
  },

  profiling = {
    -- .utrace ファイルを検索する追加のディレクトリをここに指定します。
    -- 絶対パスでの指定を推奨します。
    -- 例: additional_search_dirs = { "D:/UE_Traces", "/mnt/shared/profiling" }
    additional_search_dirs = {},
  },
}

return M
