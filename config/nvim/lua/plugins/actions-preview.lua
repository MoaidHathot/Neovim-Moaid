return {
	"aznhe21/actions-preview.nvim",
	-- event = "VeryLazy",
	-- lazy = false,
	keys = {
		{ "<leader>la", "<cmd>lua require('actions-preview').code_actions()<CR>", desc = "Code Actions" },
	}
}
