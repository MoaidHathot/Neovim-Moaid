return {
	{
		'rmagatti/auto-session',
		-- event = "VeryLazy",
		keys = {
			{ '<leader>ss', function() require("auto-session.session-lens").search_session() end, { desc = "Search Session" } },
		},
		cmd = "SessionRestore",
		config = function()
			require('auto-session').setup({
				log_level = 'error',
				auto_restore_enabled = true
			})
			-- vim.keymap.set('n', '<leader>ss', require("auto-session.session-lens").search_session,
			-- 	{ desc = "Search Session" })
		end
	}
}
