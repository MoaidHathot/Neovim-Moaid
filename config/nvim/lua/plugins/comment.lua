return {
	'numtostr/comment.nvim',
	enabled = true,
	-- event = "verylazy",
	keys = {
		{ '<leader>/', mode = { 'n', 'v' } }
	},
	opts = {
		toggler = {
			line = '<leader>/',
		},
		opleader = {
			line = '<leader>/'
		}
	}
}
