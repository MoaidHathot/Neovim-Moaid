return {
	'tzachar/highlight-undo.nvim',
	event = "VeryLazy",
	config = function()
		require('highlight-undo').setup()
	end
}
