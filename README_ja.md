# ULG.nvim

# Unreal Engine Log 💓 Neovim

<table>
  <tr>
    <td><div align=center><img width="100%" alt="ULG.nvim Log Viewer" src="https://raw.githubusercontent.com/taku25/ULG.nvim/main/assets/main.gif" /></div></td>
  </tr>
</table>

`ULG.nvim` は、Unreal Engine のログフローを Neovim に統合するための、ログビューアです。

[`UNL.nvim`](https://github.com/taku25/UNL.nvim) ライブラリを基盤として構築されており、リアルタイムでのログ追跡、強力なフィルタリング、ログからのソースコードへのジャンプ機能などを提供します。

その他、Unreal Engine開発を強化するためのプラグイン群 ([`UEP.nvim`](https://github.com/taku25/UEP.nvim), [`UBT.nvim`](https://github.com/taku25/UBT.nvim),[`UCM.nvim`](https://github.com/taku25/UCM.nvim)) があります。

[English](./README.md) | [日本語](./README_ja.md)

---

## ✨ 機能 (Features)

*   **リアルタイムログ追跡**: ファイルの変更を監視し、新しいログを自動的に表示します (`tail`)。
*   **シンタックスハイライト**: `Error`, `Warning` などのログレベルや、カテゴリ、タイムスタンプ、ファイルパスを色付けして視認性を向上させます。
*   **強力なフィルタリング**:
    *   正規表現による動的な絞り込み。
    *   ログカテゴリによる複数選択フィルタリング。
        **リアルタイムでログのカテゴリーを収集して選択できます**
    *   全フィルターの一時的なON/OFF切り替え。
*   **ソースコード連携**: ログに出力されたファイルパス (`C:/.../File.cpp(10:20)` など) から、`<CR>` キー一発で該当箇所にジャンプします。
*   **柔軟なUI**:
    *   ログウィンドウは垂直/水平分割で、表示位置やサイズを自由に設定可能。
    *   タイムスタンプの表示/非表示を切り替え。
*   **高いカスタマイズ性**: キーマップやハイライトグループなど、ほとんどの動作を `setup` 関数でカスタマイズできます。
*   **ステータスライン連携**: [lualine.nvim](https://github.com/nvim-lualine/lualine.nvim) と連携し、ログ監視中であることをアイコンで表示します。(**オプション**)

<table>
  <tr>
    <td>
      <div align=center>
        <img width="100%" alt="Jump to source from log" src="https://raw.githubusercontent.com/taku25/ULG.nvim/main/assets/jump-to-source.gif" />
        ログからソースへジャンプ
      </div>
    </td>
    <td>
      <div align=center>
        <img width="100%" alt="Filter by category" src="https://raw.githubusercontent.com/taku25/ULG.nvim/main/assets/filter.gif" />
        カテゴリによるフィルタリング
      </div>
    </td>
  </tr>
</table>

## 🔧 必要要件 (Requirements)

*   Neovim (v0.11.3 以降を推奨)
*   **[UNL.nvim](https://github.com/taku25/UNL.nvim)** (**必須**)
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
  dependencies = { 'taku25/UNL.nvim' },
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
  -- ログウィンドウの表示位置: "bottom", "top", "left", "right"
  position = "bottom",

  -- 垂直分割時のウィンドウ幅
  vertical_size = 80,
  -- 水平分割時のウィンドウの高さ
  horizontal_size = 15,

  -- ウィンドウを開くコマンドを直接指定することもできます (例: "tabnew")
  win_open_command = nil,

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

  -- ログウィンドウ内でのキーマップ
  keymaps = {
    filter_prompt = "s",          -- 正規表現フィルターの入力
    filter_clear = "<Esc>",       -- 全フィルターのクリア
    toggle_timestamp = "i",       -- タイムスタンプ表示の切り替え
    clear_content = "c",          -- ログ内容のクリア
    category_filter_prompt = "f", -- カテゴリフィルターの選択
    jump_to_source = "<CR>",      -- ソースコードへジャンプ
    filter_toggle = "t",          -- 全フィルターの有効/無効を切り替え
    search_prompt = "h",          -- 表示内検索 (ハイライト)
    jump_next_match = "]f",       -- 次のフィルター行へジャンプ
    jump_prev_match = "[f",       -- 前のフィルター行へジャンプ
    show_help = "?",              -- ヘルプウィンドウの表示
  },

  -- ヘルプウィンドウの枠線
  help = {
    border = "rounded",
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
:ULG start      " 現在のUnreal Engineプロジェクトのデフォルトログを追跡します。
:ULG start!     " ファイルピッカーを開き、追跡したいログファイルを選択します。
:ULG stop       " 現在のログの追跡を停止します（ウィンドウは開いたままです）。
```

ログウィンドウを閉じるには、ウィンドウにフォーカスして `:q` を実行してください。

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
