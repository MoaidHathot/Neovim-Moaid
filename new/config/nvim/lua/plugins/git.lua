return {
	{
		'tpope/vim-fugitive',
		event = "VeryLazy"
	},
	{
		'lewis6991/gitsigns.nvim',
		event = "VeryLazy",
		config = function()
			require('gitsigns').setup()
		end
	}
}
