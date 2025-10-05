# claude-follow-hook.nvim

Watch Claude Code edit files in real-time from your NeoVim editor.

## Features

- 🔌 **Socket-based communication** between Claude Code CLI and NeoVim
- 📂 **Workspace-aware** - Each directory gets its own socket
- 🎨 **Visual highlights** - See exactly what Claude changed with green backgrounds and gutter markers
- ⚡ **Auto-focus** - Files open automatically as Claude edits them
- 🔄 **Re-enable friendly** - Toggle on/off without errors

## Demo

When Claude Code edits files, this plugin automatically:
1. Opens the file in your main editor window
2. Jumps to the edited line
3. Highlights changed lines with green background
4. Shows `●` markers in the gutter
5. Displays notification with operation details

Perfect for pair programming with Claude or watching Claude work in another terminal/tab!

## Installation

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "zach-source/claude-follow-hook.nvim",
  config = function()
    require("claude-follow").setup({
      setup_keymaps = true,  -- Enable default keymaps
      keymap_prefix = "<leader>af",  -- Prefix for keymaps
    })
  end,
}
```

### Using [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  "zach-source/claude-follow-hook.nvim",
  config = function()
    require("claude-follow").setup()
  end
}
```

## Configuration

### Default Setup

```lua
require("claude-follow").setup({
  -- Keymaps
  setup_keymaps = true,        -- Enable default keymaps (default: true)
  keymap_prefix = "<leader>af", -- Keymap prefix (default: "<leader>af")

  -- Socket settings
  socket_prefix = "/tmp/nvim-follow-", -- Socket path prefix
  socket_hash_length = 12,     -- Length of CWD hash in socket name

  -- UI customization
  buffer_name = "[Claude Follow]", -- Name of the follow buffer
  sign_text = "●",             -- Sign text in gutter
  sign_texthl = "DiagnosticInfo", -- Highlight group for sign text
  sign_linehl = "DiffAdd",     -- Highlight group for line background
  highlight_duration = 5000,   -- Duration to show highlights (ms)

  -- Scroll behavior
  scroll_to_change = true,     -- Auto-scroll to changed lines (default: true)
  scroll_offset = 5,           -- Lines of context above/below (default: 5)

  -- Debug
  debug = false,               -- Enable debug logging (default: false)
  debug_log_path = "/tmp/claude-follow-mode-debug.log", -- Path for debug logs
})
```

### Configuration Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `setup_keymaps` | boolean | `true` | Enable default keymaps |
| `keymap_prefix` | string | `"<leader>af"` | Prefix for all keymaps |
| `socket_prefix` | string | `"/tmp/nvim-follow-"` | Socket file path prefix |
| `socket_hash_length` | number | `12` | Length of CWD hash in socket name |
| `buffer_name` | string | `"[Claude Follow]"` | Name of follow buffer |
| `sign_text` | string | `"●"` | Character shown in gutter for changes |
| `sign_texthl` | string | `"DiagnosticInfo"` | Highlight group for sign |
| `sign_linehl` | string | `"DiffAdd"` | Highlight group for changed lines |
| `highlight_duration` | number | `5000` | How long to show highlights (milliseconds) |
| `scroll_to_change` | boolean | `true` | Auto-scroll viewport to changed lines |
| `scroll_offset` | number | `5` | Lines of context above/below when scrolling |
| `debug` | boolean | `false` | Enable debug logging in bash hook |
| `debug_log_path` | string | `"/tmp/claude-follow-mode-debug.log"` | Debug log file path |

### Disable Default Keymaps

```lua
require("claude-follow").setup({
  setup_keymaps = false,  -- Disable keymaps, set up your own
})

-- Custom keymaps
vim.keymap.set("n", "<leader>wF", require("claude-follow").toggle)
```

## Usage

### Commands

- `:FollowModeOn` - Enable follow mode
- `:FollowModeOff` - Disable follow mode
- `:FollowModeToggle` - Toggle follow mode
- `:FollowModeStatus` - Show status

### Default Keymaps

- `<leader>af` - Toggle follow mode
- `<leader>afe` - Enable follow mode
- `<leader>afd` - Disable follow mode
- `<leader>afs` - Status

## Claude Code Hook Setup

### 1. Install the Hook Script

Copy `follow-mode-notify.sh` to your Claude Code hooks directory:

```bash
cp follow-mode-notify.sh ~/.claude/hooks/
chmod +x ~/.claude/hooks/follow-mode-notify.sh
```

### 2. Configure Claude Code Settings

Add to `~/.claude/settings.json`:

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Write|Edit|MultiEdit",
        "hooks": [
          {
            "type": "command",
            "timeout": 2,
            "command": "/Users/YOUR_USERNAME/.claude/hooks/follow-mode-notify.sh"
          }
        ]
      }
    ]
  }
}
```

Replace `YOUR_USERNAME` with your actual username, or use `$HOME/.claude/hooks/follow-mode-notify.sh`.

## How It Works

### Socket Communication

1. NeoVim creates a Unix socket when follow mode is enabled: `/tmp/nvim-follow-<USER>-<CWD_HASH>.sock`
2. The socket is unique per working directory (workspace-aware)
3. Claude Code's PostToolUse hook sends file edits to this socket
4. NeoVim receives the message and opens/highlights the file

### Workspace Isolation

Each directory gets its own socket based on SHA256 hash of the CWD:
- `~/repos/project1` → `nvim-follow-user-abc123.sock`
- `~/repos/project2` → `nvim-follow-user-def456.sock`

This means:
- Multiple NeoVim instances can have follow mode enabled simultaneously
- Claude edits in project1 only affect NeoVim in project1
- No cross-contamination between workspaces

## Requirements

- NeoVim 0.9+ (for RPC support)
- Claude Code CLI installed
- `jq` for JSON parsing in the hook script
- Unix-like system (macOS, Linux)

## Testing

Run the test suite with:

```bash
make test
```

Or manually with:

```bash
nvim --headless --noplugin -u tests/minimal_init.lua -c "PlenaryBustedDirectory tests/ { minimal_init = 'tests/minimal_init.lua' }"
```

**Note**: Tests require [plenary.nvim](https://github.com/nvim-lua/plenary.nvim) to be installed.

## Tips

### Use with Zellij/Tmux

Perfect for multi-pane setups:
- One pane: NeoVim with follow mode enabled
- Another pane: Claude Code CLI editing files
- Watch Claude work in real-time!

### Disable for Sensitive Operations

Follow mode opens files automatically. Disable it when:
- Working with sensitive files
- Running untrusted Claude commands
- Want to avoid interruptions

Just run `:FollowModeOff` or toggle with your keymap.

## Troubleshooting

### Hook Not Working

Enable debug logging in your NeoVim config:
```lua
require("claude-follow").setup({
  debug = true,
})
```

Check the log:
```bash
tail -f /tmp/claude-follow-mode-debug.log
```

Debug logs will only be written when `debug = true` is set in your config.

### Socket Not Found

Ensure:
1. Follow mode is enabled in NeoVim (`:FollowModeStatus`)
2. Claude and NeoVim are in the same working directory
3. Socket path matches: Run `:lua print(vim.g.follow_mode_socket)` in NeoVim

### Files Not Highlighting

Check:
1. Signs are enabled: `:set signcolumn?` (should be `yes` or `auto`)
2. Highlights work: Try `:sign place 1 line=1 name=ClaudeFollowChange buffer=1`

## License

MIT

## Author

Zach Taylor (@zach-source)

## Contributing

Issues and PRs welcome at: https://github.com/zach-source/claude-follow-hook.nvim
