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

  -- viewerテーブルをトップレベルに展開
  position = "right", -- "right", "left", "bottom", "top", "tab"
  vertical_size = 80,
  horizontal_size = 15,
  win_open_command = nil,
  filetype = "unreal-log",
  auto_scroll = true,

  polling_interval_ms = 500,
  render_chunk_size = 500,
  hide_timestamp = true,

  keymaps = {
    filter_prompt = "s",
    filter_clear = "<Esc>",
    toggle_timestamp = "i",
    clear_content = "c",
    category_filter_prompt = "f",
    jump_to_source = "<CR>",
    filter_toggle = "t",
    search_prompt = "p",
    jump_next_match = "]f",
    jump_prev_match = "[f",
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
      -- ULGFilePathView = {
      --   -- NEW: A rule for non-jumpable file paths, often found in quotes.
      --   pattern = '\\v"[a-zA-Z]:[/\\][^"]*"',
      --   hl_group = "String",
      --   priority = 105,
      -- },
    },
  },
}

return M
