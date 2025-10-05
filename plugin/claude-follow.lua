-- Claude Follow Hook Plugin Entry Point
-- Auto-loads the plugin and sets up commands

if vim.g.loaded_claude_follow then
  return
end
vim.g.loaded_claude_follow = true

-- Load the module
require("claude-follow").setup()
