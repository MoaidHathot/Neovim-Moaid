return {
	'stevearc/oil.nvim',
	keys = {
		{ mode = { 'n', 'v' },'<leader>mF', "<CMD>Oil<CR>", { desc = "Open Oil file manager" } }
	},
	opts = {
		default_file_explorer = false,
	},
	dependencies = { "nvim-tree/nvim-web-devicons" },
}
