return {
	{
		"iamcco/markdown-preview.nvim",
		-- event = "VeryLazy",
		enable = true,
		cmd = { "MarkdownPreviewToggle", "MarkdownPreview", "MarkdownPreviewStop" },
		ft = { "markdown", "md" },
		-- build = function()
			-- vim.fn["mkdp#util#install"]()
		-- end
		build = "cd app && npm install",
	    init = function()
			vim.g.mkdp_filetypes = { "markdown" }
		end,
	},
	{
		"ellisonleao/glow.nvim",
		-- event = "VeryLazy",
		cmd = "Glow",
		ft = { "markdown", "md" },
		opts = {
			style = "dark",
		},
	},
	{
		"OXY2DEV/markview.nvim",
		enable = false,
		lazy = true,
		-- ft = { "markdown", "md" },
		cmd = "Markview",
	},
	{
		"terrastruct/d2-vim",
		enabled = true,
		lazy = true,
		ft = { "d2" },
	}
}
