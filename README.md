# ULG.nvim

# Unreal Engine Log 💓 Neovim

<table>
  <tr>
    <td><div align=center><img width="100%" alt="ULG.nvim Log Viewer" src="https://raw.githubusercontent.com/taku25/ULG.nvim/images/assets/main.png" /></div></td>
  </tr>
</table>

`ULG.nvim` is a log viewer designed to integrate the Unreal Engine log workflow into Neovim.

Built upon the [`UNL.nvim`](https://github.com/taku25/UNL.nvim) library, it provides real-time log tracking, powerful filtering, and the ability to jump from logs directly to your source code.
It also supports a powerful multi-window feature that works with [`UBT.nvim`](https://github.com/taku25/UBT.nvim) to display Unreal Build Tool logs simultaneously.

This plugin is part of a suite of tools designed to enhance Unreal Engine development, including ([`UEP.nvim`](https://github.com/taku25/UEP.nvim), [`UBT.nvim`](https://github.com/taku25/UBT.nvim), [`UCM.nvim`](https://github.com/taku25/UCM.nvim)).

[English](./README.md) | [日本語 (Japanese)](./README_ja.md)

---

## ✨ Features

*   **Real-time Log Tailing**: Monitors file changes and automatically displays new logs (`tail`).
*   **Build Log Integration**: Seamlessly works with [`UBT.nvim`](https://github.com/taku25/UBT.nvim) to show UE logs and build logs together in intelligently split windows. Jumping from build errors is also supported.
*   **Syntax Highlighting**: Improves visibility by colorizing log levels like `Error` and `Warning`, as well as categories, timestamps, and file paths.
*   **Powerful Filtering**:
    *   Dynamic filtering with regular expressions.
    *   Multi-select filtering by log category. **Categories are collected from the log in real-time.**
    *   Toggle all filters on and off temporarily.
*   **Unreal Editor Integration (Remote Command Execution)**: Send commands like Live Coding triggers and `stat` commands directly to the Unreal Editor from the log window. (**Optional**)
*   **Source Code Integration**: Jump directly to the relevant source code location from a file path in the logs (e.g., `C:/.../File.cpp(10:20)`) with a single press of the `<CR>` key.
*   **Flexible UI**:
    *   Log windows can be split vertically or horizontally, with customizable positions and sizes.
    *   Configure the parent-child relationship between the UE and build logs (i.e., which is primary and which is secondary).
    *   Toggle the visibility of timestamps.
*   **Auto-Close Functionality**: Automatically close the ULG windows to quit Neovim when the last non-log window is closed.
*   **Highly Customizable**: Almost all behaviors, including keymaps and highlight groups, can be customized via the `setup` function.
*   **Statusline Integration**: Integrates with [lualine.nvim](https://github.com/nvim-lualine/lualine.nvim) to display an icon indicating when log monitoring is active. (**Optional**)


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
*   **[UBT.nvim](https://github.com/taku25/UBT.nvim)** (**Required** for the build log feature)
*   **Unreal Engine's Remote Control API** plugin (Optional):
    *   Must be enabled to use the remote command feature.
*   [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) or [fzf-lua](https://github.com/ibhagwan/fzf-lua) (**Recommended**)
    *   Used as the UI for selecting log files and categories.
*   [fd](https://github.com/sharkdp/fd) (**Recommended**)
    *   Speeds up log file searching. The plugin will work without it.
*   [lualine.nvim](https://github.com/nvim-lualine/lualine.nvim) (**Recommended**)
    *   Required for statusline integration.

## 🚀 Installation

Install using your preferred plugin manager.

### [lazy.nvim](https://github.com/folke/lazy.nvim)

`UNL.nvim` is a mandatory dependency. `lazy.nvim` will resolve this automatically.

```lua
-- lua/plugins/ulg.lua

return {
  'taku25/ULG.nvim',
  -- ULG.nvim depends on UNL.nvim.
  -- UBT.nvim is also required for the build log feature.
  dependencies = { 'taku25/UNL.nvim', 'taku25/UBT.nvim' },
  opts = {
    -- Place your configuration here (see details below)
  }
}
```

## ⚙️ Configuration

You can customize the plugin's behavior by passing a table to the `setup()` function (or the `opts` table in `lazy.nvim`).
The following shows all available options with their default values.

```lua
-- Inside the opts = { ... } table for ULG.nvim

{
  -- UE Log (Primary Window) Settings
  position = "bottom", -- "right", "left", "bottom", "top", "tab"
  size = 0.25,         -- Height/width ratio relative to the screen (0.0 to 1.0)

  -- Build Log Window Settings
  build_log_enabled = true,
  -- Position of the build log:
  -- "secondary": Auto-positions relative to the UE log in available space (Recommended)
  -- "primary": Places the build log where the UE log would be, and positions the UE log relatively
  -- "bottom", "top", "left", "right", "tab": Specifies an absolute position on the screen
  build_log_position = "secondary",
  build_log_size = 0.4, -- Ratio relative to the UE log (for secondary/primary) or the screen (for absolute)

  -- Whether to auto-close ULG windows when the last non-log buffer is closed
  enable_auto_close = true,

  -- Filetype set for the log buffer
  filetype = "unreal-log",

  -- Whether to automatically scroll to the end when new logs are added
  auto_scroll = true,

  -- Interval to check for log file changes (in milliseconds)
  polling_interval_ms = 500,
  -- Maximum number of lines to render at once
  render_chunk_size = 500,

  -- Whether to hide timestamps by default
  hide_timestamp = true,

  -- Keymaps within the log window
  keymaps = {
    filter_prompt = "s",          -- Input for regex filter
    filter_clear = "<Esc>",       -- Clear all filters
    toggle_timestamp = "i",       -- Toggle timestamp visibility
    clear_content = "c",          -- Clear log content
    category_filter_prompt = "f", -- Select category filter
    remote_command_prompt = "P",  -- Open prompt for remote command
    jump_to_source = "<CR>",      -- Jump to source code
    filter_toggle = "t",          -- Toggle all filters on/off
    search_prompt = "p",          -- Search (highlight) within the view
    jump_next_match = "]f",       -- Jump to next filtered line
    jump_prev_match = "[f",       -- Jump to previous filtered line
    toggle_build_log = "b",       -- (Note: This keymap is not currently used by ULG)
    show_help = "?",              -- Show the help window
  },

  -- Border for the help window
  help = {
    border = "rounded",
  },

  -- Syntax highlighting settings
  highlights = {
    enabled = true,
    groups = {
      -- You can override default highlight rules or
      -- add new ones here.
    },
  },
}
```

## ⚡ Usage

Commands should be run from within your Unreal Engine project directory.

```vim
:ULG start      " Start tailing the default log for the current UE project (+ build log).
:ULG start!     " Open a file picker to select a log file to tail.
:ULG stop       " Stop tailing log files (leaves the windows open).
:ULG close      " Close all log viewer windows.
```
### In the Log Window
*   `P` key (default): Opens an input prompt to send a remote command to the Unreal Editor. Completion for configured commands is available.

To close the log window, focus it and press the `q` key (default) or run `:ULG close`.

## 🤝 Integrations

### lualine.nvim

Integrates with [lualine.nvim](https://github.com/nvim-lualine/lualine.nvim) to show the log-watching status in your statusline.

<div align=center><img width="60%" alt="lualine integration" src="https://raw.githubusercontent.com/taku25/ULG.nvim/main/assets/lualine.png" /></div>

Add the following to your lualine configuration.

```lua
-- lualine.lua

-- Define the lualine component
local ulg_component = {
  -- 1. A function that returns the content to display
  function()
    local ok, view_state = pcall(require, "ULG.context.view_state")
    if not ok then return "" end

    local s = view_state.get_state()
    if s and s.is_watching == true and s.filepath then
      return "👀 ULG: " .. vim.fn.fnamemodify(s.filepath, ":t")
    end
    return ""
  end,
  -- 2. A 'cond' (condition) function that determines if the component should be shown
  cond = function()
    local ok, view_state = pcall(require, "ULG.context.view_state")
    if not ok then return false end
    local s = view_state.get_state()
    return s and s.is_watching == true
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

## Other

Related Unreal Engine Plugins:
*   [UEP.nvim](https://github.com/taku25/UEP.nvim) - Unreal Engine Project Manager
*   [UBT.nvim](https://github.com/taku25/UBT.nvim) - Unreal Build Tool Integration
*   [UCM.nvim](https://github.com/taku25/UCM.nvim) - Unreal Engine Class Manager

## 📜 License
MIT License

Copyright (c) 2025 taku25

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
