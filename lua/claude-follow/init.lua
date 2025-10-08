-- Claude Code Follow Mode: Watch Claude edit files via Unix socket
-- Version: 1.0.2
local M = {}
M.name = "ClaudeCodeFollowMode"
M.version = "1.0.2"

-- Default configuration
M.config = {
    socket_prefix = "/tmp/nvim-follow-",
    socket_hash_length = 12,
    buffer_name = "[Claude Follow]",
    highlight_duration = 5000,
    sign_text = "●",
    sign_texthl = "DiagnosticInfo",
    sign_linehl = "DiffAdd",
    setup_keymaps = true,
    keymap_prefix = "<leader>af",
    scroll_to_change = true, -- Automatically scroll to changed lines
    scroll_offset = 5, -- Lines of context above/below when scrolling
    debug = false, -- Enable debug logging
    debug_log_path = "/tmp/claude-follow-mode-debug.log",
}

-- Generate socket path based on current working directory
M.get_socket_path = function()
    local cwd = vim.fn.getcwd()
    -- Hash the CWD for a deterministic socket name
    local hash = vim.fn.sha256(cwd):sub(1, M.config.socket_hash_length)
    return M.config.socket_prefix .. vim.env.USER .. "-" .. hash .. ".sock"
end

M.socket_path = nil
M.server_id = nil
M.enabled = false

-- Find or create follow buffer
M.get_or_create_follow_buffer = function()
    -- Check if follow buffer already exists
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_valid(buf) then
            local bufname = vim.api.nvim_buf_get_name(buf)
            -- Match buffer name (may include full path prefix)
            if bufname:match(vim.pesc(M.config.buffer_name) .. "$") then
                return buf
            end
        end
    end

    -- Create new follow buffer (listed, not scratch)
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(buf, M.config.buffer_name)
    vim.bo[buf].bufhidden = "hide"
    vim.bo[buf].buftype = "" -- Normal buffer (not nofile)
    vim.bo[buf].modifiable = true

    -- Add helpful text
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
        "Claude Follow Mode Active",
        "",
        "Files that Claude edits will appear here in your main editor.",
        "",
        "Commands:",
        "  :FollowModeOff  - Disable follow mode",
        "  :FollowModeToggle - Toggle follow mode",
        "",
        "Waiting for Claude to edit files...",
    })

    -- Mark as not modified (so it doesn't ask to save)
    vim.bo[buf].modified = false

    return buf
end

-- Enable follow mode
M.enable = function()
    if M.enabled then
        -- Already enabled, just refocus the follow buffer
        local buf = M.get_or_create_follow_buffer()
        vim.api.nvim_set_current_buf(buf)
        vim.notify("Follow mode already enabled (refocused buffer)", vim.log.levels.INFO)
        return
    end

    -- Get CWD-based socket path
    M.socket_path = M.get_socket_path()

    -- Start socket server
    M.server_id = vim.fn.serverstart(M.socket_path)

    if M.server_id then
        M.enabled = true
        vim.g.follow_mode_enabled = true
        vim.g.follow_mode_socket = M.socket_path
        vim.g.follow_mode_debug = M.config.debug

        -- Get or create follow buffer
        local buf = M.get_or_create_follow_buffer()

        -- Set the buffer in current window
        vim.api.nvim_set_current_buf(buf)

        -- Set up autocmd to handle remote commands
        vim.api.nvim_create_autocmd("VimLeave", {
            callback = function()
                M.disable()
            end,
        })

        local cwd = vim.fn.getcwd()
        vim.notify(
            "Follow mode enabled\nCWD: " .. vim.fn.fnamemodify(cwd, ":~") .. "\nSocket: " .. M.socket_path,
            vim.log.levels.INFO
        )
    else
        vim.notify("Failed to start follow mode server", vim.log.levels.ERROR)
    end
end

-- Disable follow mode
M.disable = function()
    if not M.enabled then
        vim.notify("Follow mode not enabled", vim.log.levels.INFO)
        return
    end

    -- Stop server
    if M.server_id and M.socket_path then
        vim.fn.serverstop(M.socket_path)
        M.server_id = nil
    end

    M.enabled = false
    vim.g.follow_mode_enabled = false
    vim.g.follow_mode_socket = nil
    vim.g.follow_mode_debug = nil

    -- Clean up socket file if it exists
    if M.socket_path then
        vim.fn.delete(M.socket_path)
        M.socket_path = nil
    end

    -- Note: We keep the buffer alive so it can be re-enabled
    -- User can manually delete it with :bd [Claude Follow]

    vim.notify("Follow mode disabled (buffer kept for re-enable)", vim.log.levels.INFO)
end

-- Toggle follow mode
M.toggle = function()
    if M.enabled then
        M.disable()
    else
        M.enable()
    end
end

-- Get status
M.status = function()
    if M.enabled then
        local cwd = vim.fn.getcwd()
        local msg = string.format(
            "Follow mode: ENABLED\nVersion: %s\nCWD: %s\nSocket: %s\nDebug: %s",
            M.version,
            vim.fn.fnamemodify(cwd, ":~"),
            M.socket_path,
            M.config.debug and "ON" or "OFF"
        )
        vim.notify(msg, vim.log.levels.INFO)
    else
        vim.notify("Follow mode: DISABLED\nVersion: " .. M.version, vim.log.levels.INFO)
    end
end

-- Get the main editor window (not sidekick/terminal/floating)
M.get_main_editor_window = function()
    -- Find first normal window that's not special
    for _, win in ipairs(vim.api.nvim_list_wins()) do
        local buf = vim.api.nvim_win_get_buf(win)
        local buftype = vim.bo[buf].buftype
        local bufname = vim.api.nvim_buf_get_name(buf)

        -- Skip terminal and special buffers
        if buftype ~= "terminal" and buftype ~= "prompt" then
            -- Check it's not a floating window
            local win_config = vim.api.nvim_win_get_config(win)
            if win_config.relative == "" then
                -- Not sidekick CLI window (check buffer name)
                if not bufname:match("term://") and not bufname:match("sidekick") then
                    return win
                end
            end
        end
    end

    -- Fallback to window 1
    return vim.fn.win_getid(1)
end

-- Define highlight for changed lines
M.setup_highlights = function()
    -- Define sign for changed lines
    vim.fn.sign_define("ClaudeFollowChange", {
        text = M.config.sign_text,
        texthl = M.config.sign_texthl,
        linehl = M.config.sign_linehl,
    })
end

-- Clear previous highlights
M.clear_highlights = function(buf)
    -- Clear all ClaudeFollowChange signs from buffer
    vim.fn.sign_unplace("claude_follow", { buffer = buf })
end

-- Highlight changed lines
M.highlight_lines = function(buf, start_line, line_count)
    M.clear_highlights(buf)

    -- Place signs on changed lines
    for i = 0, line_count - 1 do
        local line = start_line + i
        vim.fn.sign_place(0, "claude_follow", "ClaudeFollowChange", buf, {
            lnum = line,
            priority = 10,
        })
    end

    -- Auto-clear after configured duration
    vim.defer_fn(function()
        if vim.api.nvim_buf_is_valid(buf) then
            M.clear_highlights(buf)
        end
    end, M.config.highlight_duration)
end

-- Open file (called via RPC from Claude hook)
M.open_file = function(file_path, line_num, line_count, tool_name)
    if not M.enabled then
        return
    end

    -- Default parameters
    line_num = line_num or 1
    line_count = line_count or 1
    tool_name = tool_name or "unknown"

    -- Setup highlights if not done yet
    M.setup_highlights()

    -- Expand path
    local expanded_path = vim.fn.expand(file_path)

    -- Get the main editor window (skip sidekick/terminal)
    local main_win = M.get_main_editor_window()

    -- First, focus the main window
    vim.api.nvim_set_current_win(main_win)

    -- Disable swap file warnings for follow mode
    local old_shortmess = vim.o.shortmess
    vim.o.shortmess = vim.o.shortmess .. "A" -- Suppress ATTENTION message

    -- Use edit! to skip swap file prompts
    vim.cmd("edit! " .. vim.fn.fnameescape(expanded_path))
    local buf = vim.api.nvim_get_current_buf()

    -- Restore shortmess
    vim.o.shortmess = old_shortmess

    -- Ensure buffer is modifiable (use vim.bo for buffer-local options)
    vim.bo[buf].modifiable = true
    vim.bo[buf].readonly = false

    -- Jump to line if provided
    if line_num and line_num > 0 then
        vim.cmd(":" .. line_num)

        -- Scroll to changed lines with configured offset
        if M.config.scroll_to_change then
            -- Set scrolloff temporarily for smooth positioning
            local old_scrolloff = vim.o.scrolloff
            vim.o.scrolloff = M.config.scroll_offset
            vim.cmd("normal! zz") -- Center screen
            vim.o.scrolloff = old_scrolloff
        end
    end

    -- Explicitly redraw to ensure focus
    vim.cmd("redraw")

    -- Highlight changed lines
    if buf and line_num > 0 and line_count > 0 then
        M.highlight_lines(buf, line_num, line_count)
    end

    -- Visual feedback with operation type
    local operation = tool_name == "Edit" and "edited" or tool_name == "Write" and "created" or "modified"
    vim.notify(
        string.format(
            "Following: %s:%d (%s %d line%s)",
            vim.fn.fnamemodify(expanded_path, ":~:."),
            line_num,
            operation,
            line_count,
            line_count > 1 and "s" or ""
        ),
        vim.log.levels.INFO
    )
end

-- Setup function (called by plugin)
M.setup = function(opts)
    opts = opts or {}

    -- Merge user config with defaults
    M.config = vim.tbl_deep_extend("force", M.config, opts)

    -- Create user commands
    vim.api.nvim_create_user_command("FollowModeOn", M.enable, { desc = "Enable Claude follow mode" })
    vim.api.nvim_create_user_command("FollowModeOff", M.disable, { desc = "Disable Claude follow mode" })
    vim.api.nvim_create_user_command("FollowModeToggle", M.toggle, { desc = "Toggle Claude follow mode" })
    vim.api.nvim_create_user_command("FollowModeStatus", M.status, { desc = "Show Claude follow mode status" })

    -- Default keymaps (can be disabled with setup_keymaps = false)
    if M.config.setup_keymaps then
        vim.keymap.set("n", M.config.keymap_prefix, M.toggle, { desc = "Toggle Claude Follow Mode" })
        vim.keymap.set("n", M.config.keymap_prefix .. "e", M.enable, { desc = "Enable Claude Follow Mode" })
        vim.keymap.set("n", M.config.keymap_prefix .. "d", M.disable, { desc = "Disable Claude Follow Mode" })
        vim.keymap.set("n", M.config.keymap_prefix .. "s", M.status, { desc = "Claude Follow Mode Status" })
    end
end

return M
