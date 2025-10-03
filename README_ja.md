# ULG.nvim

# Unreal Engine Log 💓 Neovim

<table>
  <tr>
    <td>
      <div align=center>
      <img width="100%" alt="ULG.nvim Log Viewer" src="https://raw.githubusercontent.com/taku25/ULG.nvim/images/assets/main.png" />
      </div>
    </td>
    <td>
      <div align=center>
      <img width="100%" alt="ULG.nvim Log Viewer" src="https://raw.githubusercontent.com/taku25/ULG.nvim/images/assets/trace_gantt.png" />
      </div>
    </td>
  </tr>
</table>

`ULG.nvim` は、Unreal Engine のログフローを Neovim に統合するための、ログビューアです。
Unreal-insightsの表示にも対応しており、スパークラインで各フレームの重さを確認、また['neo-tree-unl'](https://github.com/taku25/neo-tree-unl)を使えばinsightsの情報から関数に直接ジャンプできます。


[`UNL.nvim`](https://github.com/taku25/UNL.nvim) ライブラリを基盤として構築されており、リアルタイムでのログ追跡、強力なフィルタリング、ログからのソースコードへのジャンプ機能などを提供します。

その他、Unreal Engine開発を強化するためのプラグイン群 ([`UEP.nvim`](https://github.com/taku25/UEP.nvim), [`UBT.nvim`](https://github.com/taku25/UBT.nvim),[`UCM.nvim`](https://github.com/taku25/UCM.nvim)) があります。

[English](./README.md) | [日本語](./README_ja.md)

---

## ✨ 機能 (Features)

*   **リアルタイムログ追跡**: ファイルの変更を監視し、新しいログを自動的に表示します (`tail`)。
    **ビルドログ連携**: [`UBT.nvim`](https://github.com/taku25/UBT.nvim)とシームレスに連携し、UEログとビルドログをインテリジェントに分割されたウィンドウで同時に表示。ビルドエラーからのジャンプも可能です。
*   **シンタックスハイライト**: `Error`, `Warning` などのログレベルや、カテゴリ、タイムスタンプ、ファイルパスを色付けして視認性を向上させます。
*   **強力なフィルタリング**:
    *   正規表現による動的な絞り込み。
    *   ログカテゴリによる複数選択フィルタリング。
        **リアルタイムでログのカテゴリーを収集して選択できます**
    *   全フィルターの一時的なON/OFF切り替え。
*   **Unreal Editor連携 (リモートコマンド実行)**: ログウィンドウから直接、Live CodingのトリガーやstatコマンドなどをUnreal Editorに送信できます。(**オプション**)
*   **insights対応 (utrace)**: insightsから出力されたutrace情報を解析、直感的な操作で処理負荷を見ることができます。
    * neo-tree-unlを使えば直接関数へジャンプできます(**オプション**)
*   **ソースコード連携**: ログに出力されたファイルパス (`C:/.../File.cpp(10:20)` など) から、`<CR>` キー一発で該当箇所にジャンプします。
*   **柔軟なUI**:
    *   ログウィンドウは垂直/水平分割で、表示位置やサイズを自由に設定可能。
    *   --- ★ 変更点 ★ ---
        UEログとビルドログの親子関係（どちらを主とし、どちらを従とするか）も設定できます。
    *   タイムスタンプの表示/非表示を切り替え。
    **自動閉鎖機能**: ログ以外の最後のウィンドウを閉じた際に、ULGのウィンドウを自動的に閉じてNeovimを終了できます。
*   **高いカスタマイズ性**: キーマップやハイライトグループなど、ほとんどの動作を `setup` 関数でカスタマイズできます。
*   **ステータスライン連携**: [lualine.nvim](https://github.com/nvim-lualine/lualine.nvim) と連携し、ログ監視中であることをアイコンで表示します。(**オプション**)


<table>
  <tr>
    <td>
      <div align=center>
        <img width="100%" alt="Jump to source from log" src="https://raw.githubusercontent.com/taku25/ULG.nvim/images/assets/jump_to_source.gif" />
        Jump to source from log
      </div>
    </td>
    <td>
      <div align=center>
       <img width="100%" alt="Filter by category" src="https://raw.githubusercontent.com/taku25/ULG.nvim/images/assets/pick_start.gif" />
        Filter by category
      </div>
    </td>
  </tr>
</table>

## 🔧 必要要件 (Requirements)

*   Neovim (v0.11.3 以降を推奨)
*   **[UNL.nvim](https://github.com/taku25/UNL.nvim)** (**必須**)
    **[UBT.nvim](https://github.com/taku25/UBT.nvim)** (ビルドログ機能を利用する場合に**必須**)
*   **Unreal Engine** の **Remote Control API** プラグイン (オプション):
    * リモートコマンド機能を利用する場合に必ず有効にしてください。
*   [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) または [fzf-lua](https://github.com/ibhagwan/fzf-lua) (**推奨**)
    *   ログファイルやカテゴリ選択のUIとして利用されます。
*   [fd](https://github.com/sharkdp/fd) (**推奨**)
    *   ログファイル検索を高速化します。未インストールでも動作します。
*   [lualine.nvim](https://github.com/nvim-lualine/lualine.nvim) (**推奨**)
    *   ステータスライン連携に必要です。

## 🚀 インストール (Installation)

お使いのプラグインマネージャーでインストールしてください。

### [lazy.nvim](https://github.com/folke/lazy.nvim)

`UNL.nvim` が必須の依存関係です。`lazy.nvim` はこれを自動で解決します。

```lua
-- lua/plugins/ulg.lua

return {
  'taku25/ULG.nvim',
  -- ULG.nvim は UNL.nvim に依存しています。
  -- ビルドログ機能を使うには UBT.nvim も必要です。
  dependencies = { 'taku25/UNL.nvim', 'taku25/UBT.nvim' },
  opts = {
    -- ここに設定を記述します (詳細は後述)
  }
}
```

## ⚙️ 設定 (Configuration)

`setup()` 関数（または `lazy.nvim` の `opts`）にテーブルを渡すことで、プラグインの挙動をカスタマイズできます。
以下は、すべてのオプションと、そのデフォルト値です。

```lua
-- ULG.nvim の opts = { ... } の中身

{
  -- UEログ (主ウィンドウ) の設定
  position = "bottom", -- "right", "left", "bottom", "top", "tab"
  size = 0.25,         -- 画面全体に対する高さ/幅の割合 (0.0 ~ 1.0)

  -- ビルドログウィンドウの設定
  build_log_enabled = true,
  -- ビルドログの表示位置:
  -- "secondary": UEログに対し、空いているスペースに自動配置 (推奨)
  -- "primary": UEログが本来表示される位置にビルドログを配置し、UEログを相対的に配置
  -- "bottom", "top", "left", "right", "tab": 画面に対し絶対位置で指定
  build_log_position = "secondary",
  build_log_size = 0.4, -- "secondary" "primary"時はUEログに対する割合、絶対指定時は画面全体に対する割合

  -- ログ以外の最後のバッファを閉じたら、ULGウィンドウも自動で閉じるか
  enable_auto_close = true,

  -- ログバッファに設定されるファイルタイプ
  filetype = "unreal-log",

  -- 新しいログが追加されたときに自動で末尾までスクロールするか
  auto_scroll = true,

  -- ログファイルの変更をチェックする間隔 (ミリ秒)
  polling_interval_ms = 500,
  -- 一度に描画するログの最大行数
  render_chunk_size = 500,

  -- タイムスタンプをデフォルトで非表示にするか
  hide_timestamp = true,

  keymaps = {
      -- ログウィンドウ内でのキーマッ� �   
    log = {
      filter_prompt = "s",          -- 正規表現フィルターの入力
      filter_clear = "<Esc>",       -- 全フィルターのクリア
      toggle_timestamp = "i",       -- タイムスタンプ表示の切り替え
      clear_content = "c",          -- ログ内容のクリア
      category_filter_prompt = "f", -- カテゴリフィルターの選択
      remote_command_prompt = "P",  -- リモートコマンドのプロンプトを開く
      jump_to_source = "<CR>",      -- ソースコードへジャンプ
      filter_toggle = "t",          -- 全フィルターの有効/無効を切り替え
      search_prompt = "p",          -- 表示内検索 (ハイライト)
      jump_next_match = "]f",       -- 次のフィルター行へジャンプ
      jump_prev_match = "[f",       -- 前のフィルター行へジャンプ
      toggle_build_log = "b",       -- (注: このキーマップは現在ULGでは使用されません)
      show_help = "?",              -- ヘルプウィンドウの表示
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

  -- ヘルプウィンドウの枠線
  help = {
    border = "rounded",
  },

  -- traceのスパークライン
  spark_chars = { " ", "▂", "▃", "▄", "▅", "▆", "▇" },
  gantt = {
    -- ガントチャートでデフォルト表示するスレッド名のリスト。
    -- GameThread, RenderThread, RHIThread はパフォーマンス分析で特に重要。
    default_threads = {
      "GameThread",
      "RHIThread",
      "RenderThread 0",
    },
  },
  -- シンタックスハイライトの設定
  highlights = {
    enabled = true,
    groups = {
      -- ここでデフォルトのハイライトルールを上書きしたり、
      -- 新しいルールを追加したりできます。
    },
  },
}
```

## ⚡ 使い方 (Usage)

コマンドは、Unreal Engineプロジェクトのディレクトリ内で実行してください。

```vim
:ULG start      " UEログ (+ビルドログ) の追跡を開始します。
:ULG start!     " ファイルピッカーを開き、追跡したいUEログファイルを選択します。
:ULG stop       " ログの追跡を停止します（ウィンドウは開いたままです）。
:ULG close      " 全てのログウィンドウを閉じます。
:ULG crash      " ファイルピッカーを開き、クラッシュをログを選択します
:ULG trace      " saved/profiling 最も新しい.utraceを開きます。ない場合はtrace!と同じ挙動になります
:ULG trace!     " utraceピッカーを開き、情報を解析＆表示を行います(キャッシュを生成するため初回は重いです)
:ULG remote     " remote command をunreal engineに送ります。遅れるコマンドはkismet ライブラリーの関数です
```
### ログウィンドウでの操作
* Pキー（デフォルト）: Unreal Editorに送信するリモートコマンドの入力プロンプトを開きます。プロンプトでは設定したコマンドの補完が利用できます。

ログウィンドウを閉じるには、ウィンドウにフォーカスして `q` キー（デフォルト）を押すか、`:ULG close` を実行してください。

## 🤝 連携 (Integrations)

### lualine.nvim

[lualine.nvim](https://github.com/nvim-lualine/lualine.nvim) と連携し、`ULG.nvim`がログを監視しているかどうかをステータスラインに表示できます。

<div align=center><img width="60%" alt="lualine integration" src="https://raw.githubusercontent.com/taku25/ULG.nvim/main/assets/lualine.png" /></div>

以下の設定をあなたのlualine設定に追加してください。

```lua
-- lualine.lua

-- lualineコンポーネントの定義
local ulg_component = {
  -- 1. 表示する内容を返す関数
  function()
    local ok, view_state = pcall(require, "ULG.context.view_state")
    if not ok then return "" end

    local s = view_state.get_state()
    if s and s.is_watching == true and s.filepath then
      return "👀 ULG: " .. vim.fn.fnamemodify(s.filepath, ":t")
    end
    return ""
  end,
  -- 2. コンポーネントを表示するかどうかを決定する `cond` (condition) 関数
  cond = function()
    local ok, view_state = pcall(require, "ULG.context.view_state")
    if not ok then return false end
    local s = view_state.get_state()
    return s and s.is_watching == true
  end,
}

-- lualine設定の例
require('lualine').setup({
  options = {
    -- ...
  },
  sections = {
    -- ...
    lualine_x = { 'diagnostics', ulg_component },
    -- ...
  }
})
```

## その他

Unreal Engine 関連プラグイン:
*   [UEP.nvim](https://github.com/taku25/UEP.nvim) - Unreal Engine プロジェクトマネージャー
*   [UBT.nvim](https://github.com/taku25/UBT.nvim) - Unreal Build Tool 連携
*   [UCM.nvim](https://github.com/taku25/UBT.nvim) - Unreal Engine クラスマネージャー
*   [tree-sitter for Unreal Engine](https://github.com/taku25/tree-sitter-unreal-cpp) - unreal cpp用tree-sitter

## 📜 ライセンス (License)
MIT License

Copyright (c) 2025 taku25

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```
