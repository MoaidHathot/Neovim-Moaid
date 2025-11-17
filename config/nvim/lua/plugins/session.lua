return {
	{
		'rmagatti/auto-session',
		-- event = "VeryLazy",
		-- event = "VimEnter",
		-- keys = {
		-- 	{ '<leader>ss', function() require("auto-session.session-lens").search_session() end, { desc = "Search Session" } },
		-- },
		-- cmd = "SessionRestore",
		config = function()
			require('auto-session').setup({
				log_level = 'error',
				auto_restore_enabled = true,
			})
			-- vim.keymap.set('n', '<leader>ss', function() require("auto-session.session-lens").search_session() end, { desc = "Search Session" })
			vim.keymap.set('n', '<leader>ss', "<cmd>AutoSession search<CR>", { desc = "Search Session" })
		end
	}
}
