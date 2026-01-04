return {
	"aznhe21/actions-preview.nvim",
	-- event = "VeryLazy",
	-- lazy = false,
	keys = {
		{ mode = { 'n', 'v' }, "<leader>la", "<cmd>lua require('actions-preview').code_actions()<CR>", desc = "Code Actions" },
	}
}
