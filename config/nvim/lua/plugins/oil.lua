return {
	'stevearc/oil.nvim',
	keys = {
		{ '<leader>mF', "<CMD>Oil<CR>", mode = { 'n', 'v' }, desc = "Open Oil file manager" }
	},
	opts = {
		default_file_explorer = false,
	},
	dependencies = { "nvim-tree/nvim-web-devicons" },
}
