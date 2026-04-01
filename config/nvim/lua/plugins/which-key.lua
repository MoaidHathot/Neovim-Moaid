return {
	"folke/which-key.nvim",
	event = "VeryLazy",
	cmd = "WhichKey",
	init = function()
		vim.o.timeout = true
		vim.o.timeoutlen = 300
	end,
	opts = {
		spec = {
			{ "<leader>b", group = "Buffers" },
			{ "<leader>f", group = "Files" },
			{ "<leader>s", group = "Search" },
			{ "<leader>l", group = "LSP" },
			{ "<leader>lf", group = "Format" },
			{ "<leader>ls", group = "Symbols" },
			{ "<leader>g", group = "Git" },
			{ "<leader>m", group = "Misc" },
			{ "<leader>n", group = ".NET" },
			{ "<leader>nr", group = ".NET References" },
			{ "<leader>np", group = ".NET Packages" },
			{ "<leader>P", group = "Preview" },
			{ "<leader>p", group = "PowerReview" },
			{ "<leader>a", group = "AI" },
			{ "<leader>d", group = "Debug/Run" },
			{ "<leader>h", group = "Highlight" },
			{ "<leader>t", group = "Tree" },
		},
	},
}
