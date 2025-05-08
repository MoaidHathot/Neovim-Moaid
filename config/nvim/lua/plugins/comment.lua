return {
	'numtostr/comment.nvim',
	enabled = false,
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
