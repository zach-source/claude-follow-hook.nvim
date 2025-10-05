-- Minimal init for testing
-- Sets up plenary and the plugin for testing

-- Disable swap files for testing
vim.opt.swapfile = false
vim.opt.updatecount = 0

-- Add plugin to runtimepath
vim.opt.rtp:append(".")

-- Add plenary to runtimepath (assumes it's installed)
vim.opt.rtp:append(vim.fn.stdpath("data") .. "/lazy/plenary.nvim")

-- Ensure plenary is available
local ok, _ = pcall(require, "plenary")
if not ok then
    print(
        "Plenary not found. Install with: git clone https://github.com/nvim-lua/plenary.nvim ~/.local/share/nvim/lazy/plenary.nvim"
    )
    vim.cmd("cquit")
end
