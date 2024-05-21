return {
	{
		'tpope/vim-fugitive',
		event = "VeryLazy",
		enabled = false,
	},
	{
		'lewis6991/gitsigns.nvim',
		-- event = "VeryLazy",
		cmd = "Gitsigns",
		opts = {},
		-- config = function()
		-- 	require('gitsigns').setup()
		-- end
	}
}
