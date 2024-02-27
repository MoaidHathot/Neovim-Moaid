return {
	{
		'rmagatti/auto-session',
		event = "VeryLazy",
		config = function()
			require('auto-session').setup({
				log_level = 'error',
				auto_restore_enabled = true
			})
			vim.keymap.set('n', '<leader>ss', require("auto-session.session-lens").search_session,
				{ desc = "Search Session" })
		end
	}
}
