# ULG.nvim

# Unreal Engine Log 💓 Neovim

<table>
  <tr>
    <td><div align=center><img width="100%" alt="ULG.nvim Log Viewer" src="https://raw.githubusercontent.com/taku25/ULG.nvim/images/assets/main.png" /></div></td>
  </tr>
</table>

`ULG.nvim` is a log viewer for integrating Unreal Engine's log flow into Neovim.

Built upon the [`UNL.nvim`](https://github.com/taku25/UNL.nvim) library, it provides features like real-time log tailing, powerful filtering, and the ability to jump to source code from logs.

Check out other plugins to enhance Unreal Engine development: ([`UEP.nvim`](https://github.com/taku25/UEP.nvim), [`UBT.nvim`](https://github.com/taku25/UBT.nvim), [`UCM.nvim`](https://github.com/taku25/UCM.nvim)).

[English](./README.md) | [日本語](./README_ja.md)

---

## ✨ Features

*   **Real-time Log Tailing**: Monitors file changes and automatically displays new logs (`tail`).
*   **Syntax Highlighting**: Improves readability by coloring log levels like `Error` and `Warning`, as well as categories, timestamps, and file paths.
*   **Powerful Filtering**:
    *   Dynamic filtering with regular expressions.
    *   Multi-select filtering by log category.
        *   **Collects and lets you select log categories in real-time.**
    *   Temporarily toggle all filters ON/OFF.
*   **Unreal Editor Integration (Remote Command Execution)**: Send commands like Live Coding triggers and `stat` commands directly to the Unreal Editor from the log window. (**Optional**)
*   **Source Code Integration**: Jump to the corresponding location from a file path in the log (e.g., `C:/.../File.cpp(10:20)`) with a single press of the `<CR>` key.
*   **Flexible UI**:
    *   The log window can be split vertically or horizontally, with fully configurable position and size.
    *   Toggle the visibility of timestamps.
*   **Highly Customizable**: Customize most behaviors, such as keymaps and highlight groups, in the `setup` function.
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
*   **Unreal Engine's Remote Control API** plugin (**Optional**):
    *   You must enable this in your Unreal project to use the remote command feature.
*   [telescope.nvim](https:/*   **Unreal Engine's Remote Control API** plugin (**Optional**):
    *   You must enable this in your Unreal project to use the remote command feature./github.com/nvim-telescope/telescope.nvim) or [fzf-lua](https://github.com/ibhagwan/fzf-lua) (**Recommended**)
    *   Used as a UI for selecting log files and categories.
*   [fd](https://github.com/sharkdp/fd) (**Recommended**)
    *   Speeds up log file searching. The plugin works without it.
*   [lualine.nvim](https://github.com/nvim-lualine/lualine.nvim) (**Recommended**)
    *   Required for statusline integration.

## 🚀 Installation

Install with your favorite plugin manager.

### [lazy.nvim](https://github.com/folke/lazy.nvim)

`UNL.nvim` is a required dependency. `lazy.nvim` will resolve this automatically.

```lua
-- lua/plugins/ulg.lua

return {
  'taku25/ULG.nvim',
  -- ULG.nvim depends on UNL.nvim.
  dependencies = { 'taku25/UNL.nvim' },
  opts = {
    -- Add your settings here (details below)
  }
}
```

## ⚙️ Configuration

You can customize the plugin's behavior by passing a table to the `setup()` function (or to `opts` in `lazy.nvim`).
Below are all the available options with their default values.

```lua
-- Inside opts = { ... } for ULG.nvim

{
  -- Log window position: "bottom", "top", "left", "right"
  position = "bottom",

  -- Window width for vertical splits
  vertical_size = 80,
  -- Window height for horizontal splits
  horizontal_size = 15,

  -- You can also specify a command to open the window (e.g., "tabnew")
  win_open_command = nil,

  -- Filetype set for the log buffer
  filetype = "unreal-log",

  -- Automatically scroll to the end when new logs are added
  auto_scroll = true,

  -- Interval to check for log file changes (in milliseconds)
  polling_interval_ms = 500,
  -- Maximum number of log lines to render at once
  render_chunk_size = 500,

  -- Hide timestamps by default
  hide_timestamp = true,

  -- Keymaps within the log window
  keymaps = {
    filter_prompt = "s",          -- Input for regex filter
    filter_clear = "<Esc>",       -- Clear all filters
    toggle_timestamp = "i",       -- Toggle timestamp visibility
    clear_content = "c",          -- Clear log content
    category_filter_prompt = "f", -- Select category filter
    jump_to_source = "<CR>",      -- Jump to source code
    filter_toggle = "t",          -- Toggle all filters on/off
    remote_command_prompt = "P",  -- Open the remote command prompt
    search_prompt = "p",          -- Search within visible logs (highlight)
    jump_next_match = "]f",       -- Jump to the next filtered line
    jump_prev_match = "[f",       -- Jump to the previous filtered line
    show_help = "?",              -- Show help window
  },

  remote = {
    host = "127.0.0.1",
    port = "30010",
    commands = {
      "livecoding.compile",
      "stat fps",
      "stat unit",
      "stat gpu",
      "stat cpu",
      "stat none",
    },
  },
  -- Border for the help window
  help = {
    border = "rounded",
  },

  -- Syntax highlighting settings
  highlights = {
    enabled = true,
    groups = {
      -- You can override default highlight rules
      -- or add new ones here.
    },
  },
}
```

## ⚡ Usage

Run these commands inside an Unreal Engine project directory.

```vim
:ULG start      " Start tailing the default log for the current Unreal Engine project.
:ULG start!     " Open a file picker to select a log file to tail.
:ULG stop       " Stop tailing the current log (leaves the window open).
```

### Log Window Actions
*   `P` (by default): Opens a prompt to input a remote command to send to the Unreal Editor. Completion for configured commands is available.

To close the log window, focus it and run `:q`.

## 🤝 Integrations

### lualine.nvim

Integrate with [lualine.nvim](https://github.com/nvim-lualine/lualine.nvim) to show on the statusline whether `ULG.nvim` is monitoring a log.

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
  -- 2. A `cond` (condition) function that determines if the component should be displayed
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

Unreal Engine related plugins:
*   [UEP.nvim](https://github.com/taku25/UEP.nvim) - Unreal Engine Project Manager
*   [UBT.nvim](https://github.com/taku25/UBT.nvim) - Unreal Build Tool Integration

## 📜 License
MIT License

Copyright (c) 2025 taku25

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
