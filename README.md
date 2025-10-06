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

`ULG.nvim` is a log viewer designed to integrate Unreal Engine's log flow directly into Neovim.
It also supports displaying Unreal Insights data, allowing you to check the performance of each frame with a sparkline. Furthermore, by using ['neo-tree-unl'](https://github.com/taku25/neo-tree-unl), you can jump directly to functions from the Insights information.

Built upon the [`UNL.nvim`](https://github.com/taku25/UNL.nvim) library, it offers real-time log tailing, powerful filtering capabilities, and the ability to jump to source code from log entries.

This plugin is part of a suite of tools designed to enhance Unreal Engine development, including ([`UEP.nvim`](https://github.com/taku25/UEP.nvim), [`UBT.nvim`](https://github.com/taku25/UBT.nvim), and [`UCM.nvim`](https://github.com/taku25/UCM.nvim)).

[English](./README.md) | [日本語 (Japanese)](./README_ja.md)

---

## ✨ Features

*   **Real-time Log Tailing**: Monitors log files for changes and automatically displays new entries (`tail`).
*   **Build Log Integration**: Seamlessly works with [`UBT.nvim`](https://github.com/taku25/UBT.nvim) to display UE logs and build logs simultaneously in intelligently split windows. You can also jump from build errors.
*   **Syntax Highlighting**: Enhances readability by colorizing log levels like `Error`, `Warning`, as well as categories, timestamps, and file paths.
*   **Powerful Filtering**:
    *   Dynamic filtering with regular expressions.
    *   Multi-select filtering by log category.
        **Categories are collected in real-time for selection.**
    *   Toggle all filters on/off temporarily.
*   **Unreal Editor Integration (Remote Command Execution)**: Send commands like triggering Live Coding or `stat` commands directly to the Unreal Editor from the log window. (**Optional**)
*   **Insights (utrace) Support**: Analyzes `.utrace` files exported from Unreal Insights, allowing you to intuitively inspect performance loads.
    * With `neo-tree-unl`, you can jump directly to functions. (**Optional**)
*   **Jump to Source**: Instantly jump to the corresponding source code location from a file path in the logs (e.g., `C:/.../File.cpp(10:20)`) with a single key press (`<CR>`).
*   **Flexible UI**:
    *   Log windows can be opened in vertical or horizontal splits, with customizable positions and sizes.
    *   You can configure the parent-child relationship between the UE log and build log windows (which one is primary).
    *   Toggle timestamp visibility.
*   **Auto-Close Functionality**: Automatically closes the ULG windows and exits Neovim when the last non-log window is closed.
*   **Highly Customizable**: Almost every aspect, including keymaps and highlight groups, can be customized via the `setup` function.
*   **Statusline Integration**: Integrates with [lualine.nvim](https://github.com/nvim-lualine/lualine.nvim) to display an icon indicating that log monitoring is active. (**Optional**)


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

## 🔧 Requirements

*   Neovim (v0.11.3 or later recommended)
*   **[UNL.nvim](https://github.com/taku25/UNL.nvim)** (**Required**)
*   **[UBT.nvim](https://github.com/taku25/UBT.nvim)** (**Required** for build log features)
*   **Unreal Engine's** **Remote Control API** plugin (**Optional**):
    *   Must be enabled to use the remote command execution feature.
*   [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) or [fzf-lua](https://github.com/ibhagwan/fzf-lua) (**Recommended**)
    *   Used as the UI for selecting log files and categories.
*   [fd](https://github.com/sharkdp/fd) (**Recommended**)
    *   Speeds up log file searching. The plugin will work without it.
*   [lualine.nvim](https://github.com/nvim-lualine/lualine.nvim) (**Recommended**)
    *   Required for statusline integration.

## 🚀 Installation

Install using your favorite plugin manager.

### [lazy.nvim](https://github.com/folke/lazy.nvim)

`UNL.nvim` is a mandatory dependency. `lazy.nvim` will handle this automatically.

```lua
-- lua/plugins/ulg.lua

return {
  'taku25/ULG.nvim',
  -- ULG.nvim depends on UNL.nvim.
  -- UBT.nvim is also required for build log features.
  dependencies = { 'taku25/UNL.nvim', 'taku25/UBT.nvim' },
  opts = {
    -- Place your configuration here (see details below)
  }
}
```

## ⚙️ Configuration

You can customize the plugin's behavior by passing a table to the `setup()` function (or the `opts` table in `lazy.nvim`).
Below are all available options with their default values.

```lua
-- Inside the opts = { ... } table for ULG.nvim

{
  -- Settings for the main UE log window
  position = "bottom", -- "right", "left", "bottom", "top", "tab"
  size = 0.25,         -- Percentage of the screen height/width (0.0 to 1.0)

  -- Settings for the build log window
  build_log_enabled = true,
  -- Position of the build log:
  -- "secondary": Automatically placed in the remaining space relative to the UE log (Recommended)
  -- "primary": Places the build log where the UE log would normally go, and positions the UE log relatively
  -- "bottom", "top", "left", "right", "tab": Specifies an absolute position on the screen
  build_log_position = "secondary",
  build_log_size = 0.4, -- As a ratio to the UE log for "secondary"/"primary", or to the screen for absolute positions

  -- Automatically close ULG windows when the last non-log buffer is closed
  enable_auto_close = true,

  -- Filetype for the log buffer
  filetype = "unreal-log",

  -- Automatically scroll to the end when new logs are added
  auto_scroll = true,

  -- Interval to check for log file changes (in milliseconds)
  polling_interval_ms = 500,
  -- Maximum number of log lines to render at once
  render_chunk_size = 500,

  -- Hide timestamps by default
  hide_timestamp = true,

  keymaps = {
    -- Keymaps for the log window
    log = {
      filter_prompt = "s",          -- Input for regex filter
      filter_clear = "<Esc>",       -- Clear all filters
      toggle_timestamp = "i",       -- Toggle timestamp visibility
      clear_content = "c",          -- Clear log content
      category_filter_prompt = "f", -- Select category filter
      remote_command_prompt = "P",  -- Open remote command prompt
      jump_to_source = "<CR>",      -- Jump to source code
      filter_toggle = "t",          -- Toggle all filters on/off
      search_prompt = "p",          -- Search within the view (highlight)
      jump_next_match = "]f",       -- Jump to the next filtered line
      jump_prev_match = "[f",       -- Jump to the previous filtered line
      toggle_build_log = "b",       -- (Note: This keymap is not currently used by ULG)
      show_help = "?",              -- Show help window
    },

    -- Keymaps for the Trace Summary viewer
    trace = {
      show_callees_tree = "<cr>",
      show_callees = "c",          -- Show frame details in a floating window
      show_gantt_chart = "t",
      scroll_right_page = "L",     -- Scroll one page right
      scroll_left_page = "H",      -- Scroll one page left
      scroll_right = "l",          -- Scroll one frame right
      scroll_left = "h",           -- Scroll one frame left
      toggle_scale_mode = "m",     -- Toggle sparkline scale mode
      next_spike = "]",            -- Jump to the next spike
      prev_spike = "[",            -- Jump to the previous spike
      first_spike = "g[",          -- Jump to the first spike
      last_spike = "g]",           -- Jump to the last spike
      first_frame = "gg",          -- Jump to the first frame
      last_frame = "G",            -- Jump to the last frame
      show_help = "?",
    },
  },

  -- Border style for the help window
  help = {
    border = "rounded",
  },

  -- Characters for the trace sparkline
  spark_chars = { " ", "▂", "▃", "▄", "▅", "▆", "▇" },
  gantt = {
    -- List of thread names to display by default in the Gantt chart.
    -- GameThread, RenderThread, and RHIThread are particularly important for performance analysis.
    default_threads = {
      "GameThread",
      "RHIThread",
      "RenderThread 0",
    },
  },
  -- Syntax highlighting settings
  highlights = {
    enabled = true,
    groups = {
      -- You can override default highlight rules or add new ones here.
    },
  },
}
```

## ⚡ Usage

Run these commands inside your Unreal Engine project directory.

```vim
:ULG start      " Start tailing the UE log (+ build log).
:ULG start!     " Open a file picker to select a UE log file to tail.
:ULG stop       " Stop tailing logs (keeps the windows open).
:ULG close      " Close all log windows.
:ULG crash      " Open the file picker to select a crash log.
:ULG trace      " Open the most recent .utrace file in Saved/Profiling. Falls back to trace! if not found.
:ULG trace!     " Open a .utrace picker to analyze and display information (can be slow on the first run as it generates a cache).
:ULG remote     " Send a remote command to Unreal Engine using a function from the Kismet library.
```
### In the Log Window
*   Press `P` (by default) to open an input prompt for sending remote commands to the Unreal Editor. Completion for configured commands is available.

To close a log window, focus it and press `q` (by default), or run `:ULG close`.

## 🤝 Integrations

### lualine.nvim

Integrate with [lualine.nvim](https://github.com/nvim-lualine/lualine.nvim) to display the `ULG.nvim` monitoring status in your statusline.

<div align=center><img width="60%" alt="lualine integration" src="https://raw.githubusercontent.com/taku25/ULG.nvim/main/assets/lualine.png" /></div>

Add the following to your `lualine` configuration:

```lua
-- lualine.lua

-- Define the lualine component
  local ulg_component = {
    -- 1. 表示する内容を返す関数
    function()
      if require("lazy.core.config").plugins["ULG.nvim"]._.loaded then
        local ok, view_state = pcall(require, "ULG.context.view_state")
        if not ok then return "" end


        local s = view_state.get_state("ULG")
        if s and s.is_active == true then
          return "👀 ULG: " .. vim.fn.fnamemodify(s.filepath, ":t")
        end
      end
      return ""
    end,
    cond = function()
      if require("lazy.core.config").plugins["ULG.nvim"]._.loaded then
        local ok, view_state = pcall(require, "ULG.context.view_state")
        if not ok then return false end
        local s = view_state.get_state("ULG")
        if s and s.is_active == true then
          return true
        end
        return false
      end
      return false
    end,
  }

-- Example lualine setup
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

## See Also

Other Unreal Engine related plugins:
*   [UEP.nvim](https://github.com/taku25/UEP.nvim) - Unreal Engine Project Manager
*   [UBT.nvim](https://github.com/taku25/UBT.nvim) - Unreal Build Tool Integration
*   [UCM.nvim](https://github.com/taku25/UBT.nvim) - Unreal Engine Class Manager
*   [tree-sitter-unreal-cpp](https://github.com/taku25/tree-sitter-unreal-cpp) - Unreal Engine tree-sitter

## 📜 License
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
SOFTWARE.```
