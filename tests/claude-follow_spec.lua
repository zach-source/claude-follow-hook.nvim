-- Tests for claude-follow plugin
local follow = require("claude-follow")

describe("claude-follow", function()
    before_each(function()
        -- Reset state before each test
        if follow.enabled then
            follow.disable()
        end

        -- Delete all buffers to avoid conflicts
        for _, buf in ipairs(vim.api.nvim_list_bufs()) do
            if vim.api.nvim_buf_is_valid(buf) then
                pcall(vim.api.nvim_buf_delete, buf, { force = true })
            end
        end

        -- Reset config to defaults
        follow.config = {
            socket_prefix = "/tmp/nvim-follow-",
            socket_hash_length = 12,
            buffer_name = "[Claude Follow]",
            highlight_duration = 5000,
            sign_text = "●",
            sign_texthl = "DiagnosticInfo",
            sign_linehl = "DiffAdd",
            setup_keymaps = true,
            keymap_prefix = "<leader>af",
            scroll_to_change = true,
            scroll_offset = 5,
            debug = false,
            debug_log_path = "/tmp/claude-follow-mode-debug.log",
        }
    end)

    after_each(function()
        -- Clean up after tests
        if follow.enabled then
            follow.disable()
        end

        -- Clean up any socket files
        if follow.socket_path then
            vim.fn.delete(follow.socket_path)
        end
    end)

    describe("get_socket_path", function()
        it("should generate consistent socket paths for same CWD", function()
            local path1 = follow.get_socket_path()
            local path2 = follow.get_socket_path()
            assert.are.equal(path1, path2)
        end)

        it("should use configured socket prefix", function()
            follow.config.socket_prefix = "/custom/path/nvim-"
            local path = follow.get_socket_path()
            assert.truthy(path:match("^/custom/path/nvim%-"))
        end)

        it("should use configured hash length", function()
            follow.config.socket_hash_length = 8
            local path = follow.get_socket_path()
            -- Extract hash part (between last - and .sock)
            local hash = path:match("%-([^%-]+)%.sock$")
            assert.are.equal(8, #hash)
        end)

        it("should include username in socket path", function()
            local path = follow.get_socket_path()
            local user = vim.env.USER
            assert.truthy(path:find(user, 1, true))
        end)
    end)

    describe("get_or_create_follow_buffer", function()
        it("should create a new buffer on first call", function()
            local buf = follow.get_or_create_follow_buffer()
            assert.truthy(vim.api.nvim_buf_is_valid(buf))
            local name = vim.api.nvim_buf_get_name(buf)
            -- Buffer name includes full path
            assert.truthy(name:match(vim.pesc(follow.config.buffer_name) .. "$"))
        end)

        it("should reuse existing buffer on subsequent calls", function()
            local buf1 = follow.get_or_create_follow_buffer()
            local buf2 = follow.get_or_create_follow_buffer()
            assert.are.equal(buf1, buf2)
        end)

        it("should use configured buffer name", function()
            -- Delete any existing buffers first
            for _, buf in ipairs(vim.api.nvim_list_bufs()) do
                if vim.api.nvim_buf_is_valid(buf) then
                    pcall(vim.api.nvim_buf_delete, buf, { force = true })
                end
            end

            follow.config.buffer_name = "[Test Buffer]"
            local buf = follow.get_or_create_follow_buffer()
            local name = vim.api.nvim_buf_get_name(buf)
            -- Buffer name includes full path
            assert.truthy(name:match(vim.pesc("[Test Buffer]") .. "$"))
        end)
    end)

    describe("enable/disable/toggle", function()
        it("should enable follow mode", function()
            follow.enable()
            assert.is_true(follow.enabled)
            assert.truthy(follow.socket_path)
            assert.truthy(follow.server_id)
        end)

        it("should disable follow mode", function()
            follow.enable()
            follow.disable()
            assert.is_false(follow.enabled)
            assert.is_nil(follow.server_id)
        end)

        it("should toggle follow mode on", function()
            assert.is_false(follow.enabled)
            follow.toggle()
            assert.is_true(follow.enabled)
        end)

        it("should toggle follow mode off", function()
            follow.enable()
            follow.toggle()
            assert.is_false(follow.enabled)
        end)

        it("should handle double enable gracefully", function()
            follow.enable()
            local socket1 = follow.socket_path
            follow.enable()
            local socket2 = follow.socket_path
            assert.are.equal(socket1, socket2)
            assert.is_true(follow.enabled)
        end)

        it("should handle disable when not enabled", function()
            assert.has_no.errors(function()
                follow.disable()
            end)
        end)
    end)

    describe("setup_highlights", function()
        it("should define sign with configured properties", function()
            follow.config.sign_text = "■"
            follow.config.sign_texthl = "WarningMsg"
            follow.config.sign_linehl = "DiffChange"

            follow.setup_highlights()

            local sign = vim.fn.sign_getdefined("ClaudeFollowChange")[1]
            -- Sign text gets padded with a space
            assert.are.equal("■ ", sign.text)
            assert.are.equal("WarningMsg", sign.texthl)
            assert.are.equal("DiffChange", sign.linehl)
        end)
    end)

    describe("configuration", function()
        it("should merge user config with defaults", function()
            follow.setup({
                socket_prefix = "/custom/",
                highlight_duration = 3000,
            })

            assert.are.equal("/custom/", follow.config.socket_prefix)
            assert.are.equal(3000, follow.config.highlight_duration)
            -- Should preserve other defaults
            assert.are.equal("[Claude Follow]", follow.config.buffer_name)
        end)

        it("should respect setup_keymaps = false", function()
            follow.setup({
                setup_keymaps = false,
            })

            assert.is_false(follow.config.setup_keymaps)
        end)

        it("should use custom keymap_prefix", function()
            follow.setup({
                keymap_prefix = "<leader>w",
            })

            assert.are.equal("<leader>w", follow.config.keymap_prefix)
        end)

        it("should configure scroll behavior", function()
            follow.setup({
                scroll_to_change = false,
                scroll_offset = 10,
            })

            assert.is_false(follow.config.scroll_to_change)
            assert.are.equal(10, follow.config.scroll_offset)
        end)

        it("should configure debug mode", function()
            follow.setup({
                debug = true,
            })

            assert.is_true(follow.config.debug)
        end)
    end)

    describe("get_main_editor_window", function()
        it("should find a valid window", function()
            local win = follow.get_main_editor_window()
            assert.truthy(vim.api.nvim_win_is_valid(win))
        end)

        it("should skip terminal buffers", function()
            -- Get current normal window
            local normal_win = vim.api.nvim_get_current_win()

            -- Create a terminal buffer with unlisted flag
            local term_buf = vim.api.nvim_create_buf(false, true)
            pcall(vim.api.nvim_buf_set_option, term_buf, "buftype", "terminal")

            -- Main window should still be the normal one
            local main_win = follow.get_main_editor_window()
            assert.are.equal(normal_win, main_win)

            -- Cleanup
            pcall(vim.api.nvim_buf_delete, term_buf, { force = true })
        end)
    end)

    describe("highlight_lines", function()
        it("should place signs on changed lines", function()
            local buf = vim.api.nvim_create_buf(false, false)
            vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "line1", "line2", "line3" })

            follow.setup_highlights()
            follow.highlight_lines(buf, 2, 1)

            -- Check that sign was placed
            local signs = vim.fn.sign_getplaced(buf, { group = "claude_follow" })[1].signs
            assert.are.equal(1, #signs)
            assert.are.equal(2, signs[1].lnum)
        end)

        it("should clear highlights after configured duration", function()
            follow.config.highlight_duration = 100 -- Fast for testing

            local buf = vim.api.nvim_create_buf(false, false)
            vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "line1", "line2" })

            follow.setup_highlights()
            follow.highlight_lines(buf, 1, 1)

            -- Wait for auto-clear
            vim.wait(200, function()
                return false
            end)

            local signs = vim.fn.sign_getplaced(buf, { group = "claude_follow" })[1].signs
            assert.are.equal(0, #signs)
        end)
    end)
end)
