-- lua/ULG/config/defaults.lua (general logに対応した最終版)

local M = {
  -- (ロギング、キャッシュ、UI設定は変更ありません)
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

  safe_open = {
    -- A list of buffer types to avoid.
    -- See `:help buftype` for more options.
    prevent_in_buftypes = {
      "nofile",
      "quickfix",
      "help",
      "terminal",
      "prompt",
      "unreal-log",
      "build-log",
      "ulg-trace",
      "ulg-log",
    },
    -- A list of file types to avoid.
    prevent_in_filetypes = {
      "neo-tree",
      "NvimTree",
      "TelescopePrompt",
      "fugitive",
      "lazy",
    },
  },

  -- UEログ (主ウィンドウ) の設定
  position = "bottom", -- "right", "left", "bottom", "top", "tab"
  row_number = 15,         -- 画面全体に対する高さの行

  -- 汎用ログ (General Log) ウィンドウの設定
  general_log_enabled = true,
  -- 汎用ログの表示位置:
  -- "secondary": UEログに対し、空いているスペースに自動配置 (推奨)
  -- "primary": UEログが本来表示される位置に汎用ログを配置し、UEログを相対的に配置
  -- "bottom", "top", "left", "right", "tab": 画面に対し絶対位置で指定
  general_log_position = "secondary", 
  general_log_size = 50, -- "secondary" "primary"時はUEログに対する割合、絶対指定時は画面全体に対する割合

  -- ログ以外の最後のウィンドウを閉じたら、ULGウィンドウも自動で閉じるか
  enable_auto_close = true,


  filetype = "unreal-log",
  auto_scroll = true,
  polling_interval_ms = 500,
  render_chunk_size = 500,
  hide_timestamp = true,

  --trace_log position
  trace_position = "top", -- "right", "left", "bottom", "top", "tab"

 -- spark_chars = { " ", "▂", "▃", "▄", "▅", "▆", "▇" },
 spark_chars = { " ", "▂", "▃", "▄", "▅", "▆", "▇" },

  keymaps = {
    log = {
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
      toggle_build_log = "b", -- (このキーマップは将来的に general_log の toggle になる可能性がある)
      show_help = "?",
    },
        -- トレースサマリービューワー用のキーマップ
    trace = {
      show_callees_tree = "<cr>",
      show_callees = "c",          -- フレーム詳細をフローティングウィンドウで表示
      show_gantt_chart= "t",
      scroll_right_page = "L",     -- 1ページ右へスクロール
      scroll_left_page = "H",      -- 1ページ左へスクロール
      scroll_right = "l",          -- 1フレーム右へ
      scroll_left = "h",           -- 1フレーム左へ
      toggle_scale_mode = "m",     -- スパークラインのスケールモードを切り替え
      next_spike = "]",            -- 次のスパイクへジャンプ
      prev_spike = "[",            -- 前のスパイクへジャンプ
      first_spike = "g[",          -- 最初のスパイクへジャンプ
      last_spike = "g]",           -- 最後のスパイクへジャンプ
      first_frame = "gg",          -- 最初のフレームへジャンプ
      last_frame = "G",            -- 最後のフレームへジャンプ
      show_help = "?", -- ★ この行を追加
    },
  },

  gantt = {
    -- ガントチャートでデフォルト表示するスレッド名のリスト。
    -- GameThread, RenderThread, RHIThread はパフォーマンス分析で特に重要。
    default_threads = {
      "GameThread",
      "RHIThread",
      "RenderThread 0",
    },
  },

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
        pattern = [[\v[a-zA-Z][a-zA-Z0-9_]+:]],
        hl_group = "Identifier",
        priority = 100,
      },
      ULGFilePath = {
        pattern = [[\v(\~|[A-Z]:)[\/\\][^()\[\]\r\n]+\.\w+]] ,
        hl_group = "Underlined",
        priority = 110,
      },
    },
    gantt_chart = {
      color_palette = {
        "ULGGanttColor1", "ULGGanttColor2", "ULGGanttColor3", "ULGGanttColor4",
        "ULGGanttColor5", "ULGGanttColor6", "ULGGanttColor7", "ULGGanttColor8",
        "ULGGanttColor9", "ULGGanttColor10",
      },
      
      -- ★★★ 待機イベント用のハイライトグループ ★★★
      wait_hl_group = "SpecialComment",
    },
    trace_sparkline = {
      -- スパークラインの各ブロック（高さ）に対応するハイライトグループを定義。
      -- 1番目が一番低いブロック（パフォーマンスが良い）、8番目が一番高いブロック。
      groups = {
        "Comment",       --  
        "Comment",       -- ▂
        "DiagnosticInfo",-- ▃ (青系)
        "DiagnosticOk",  -- ▄ (緑系)
        "DiagnosticWarn",-- ▅ (黄系)
        "DiagnosticWarn",-- ▆
        "ErrorMsg",      -- ▇ (赤系)
        "ErrorMsg",      -- ▇
      }
    }
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
    additional_search_dirs = {},
  },
}

return M
