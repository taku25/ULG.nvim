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
        mode = "fzf-lua",
        prefer = { "telescope", "fzf-lua", "native", "dummy" },
      },
    },
  
  viewer = {
    position = "bottom", -- "right", "left", "bottom", "top", "tab"
    vertical_size = 80,
    horizontal_size = 15,
    win_open_command = nil,
    filetype = "unreal-log",
    auto_scroll = true,

    -- 小さい値ほどログの応答性が高まりますが、CPU負荷がわずかに増加します。
    polling_interval_ms = 500,

    -- 小さい値ほどUIは滑らかになりますが、全体の描画完了までにかかる時間は長くなる場合があります。
    render_chunk_size = 500,
    
    hide_timestamp = true,

    keymaps = {
      filter_prompt = "s",      -- 新しいキー: s (search/set filter)

      filter_clear = "<Esc>",
      toggle_timestamp = "i",
      clear_content = "c",
      category_filter_prompt = "f",
      jump_to_source = "<CR>",
      filter_toggle = "t",
      search_prompt = "h",
      jump_next_match = "]f",
      jump_prev_match = "[f",
      show_help = "?",
    },

    category_filters = {
    },
    help = {
      border = "rounded",
    },

    highlights = {

      enabled = true,
      groups = {
        -- ## 優先度: 10 (最優先) - 常にこの色にしたい要素 ##
        ULGTimestamp = {
          -- パターン: 行頭のタイムスタンプ。これは変更なし。
          pattern = '\\v^\\[[0-9\\.\\-:]+\\]\\[[ 0-9]+\\]',
          hl_group = "Comment",
          priority = 10,
        },

        -- ## 優先度: 20 - タイムスタンプ"以降"の行をハイライト ##
        ULGErrorLine = {
          -- パターン解説:
          -- (@<=): Vimの「後方参照」。この直前のパターンにマッチするが、その文字列自体はハイライトに含めない。
          -- つまり、「タイムスタンプとそれに続く空白の"後から"」という条件になる。
          -- これにより、タイムスタンプ自体をハイライト範囲から除外できる。
          pattern = '\\v(^\\[[0-9\\.\\-:]+\\]\\[[ 0-9]+\\]\\s*)@<=.*([Ee]rror|\\[[Ee]rror\\]).*',
          hl_group = "ErrorMsg",
          priority = 20,
        },
        ULGWarningLine = {
          -- 同様に、タイムスタンプ部分を除外して行末までをハイライト
          pattern = '\\v(^\\[[0-9\\.\\-:]+\\]\\[[ 0-9]+\\]\\s*)@<=.*([Ww]arning|\\[[Ww]arning\\]).*',
          hl_group = "DiagnosticWarn",
          priority = 21,
        },
        ULGSuccessLine = {
          pattern = '\\v(^\\[[0-9\\.\\-:]+\\]\\[[ 0-9]+\\]\\s*)@<=.*([Ss]uccess|\\[[Ss]uccess\\]).*',
          hl_group = "DiffAdd",
          priority = 22,
        },
        -- ## 優先度: 100 - その他のキーワード (変更なし) ##
        ULGCategory = {
          -- パターン解説:
          -- 必ずアルファベットで始まり ([a-zA-Z])、
          -- その後に英数字が続く ([a-zA-Z0-9_]*) パターンに限定する。
          -- これにより、タイムスタンプ内の "21:" のような数字始まりのパターンを除外できる。
          pattern = '\\v[a-zA-Z][a-zA-Z0-9_]*:', -- ← この行を修正
          hl_group = "Identifier",
          priority = 100,
        },
      }
    },
  },
}

return M
