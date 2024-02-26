return {
	{
		"iamcco/markdown-preview.nvim",
		event = "VeryLazy",
		build = function()
			vim.fn["mkdp#util#install"]()
		end
	},
	{
		"ellisonleao/glow.nvim",
		event = "VeryLazy",
		config = function()
			require("glow").setup({
				style = "dark",
			})

			vim.keymap.set('n', '<leader>mg', ":Glow<CR>")
		end
	}
}
