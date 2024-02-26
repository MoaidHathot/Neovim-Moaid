return {
	{
		"catppuccin/nvim",
		event = "VeryLazy",
		name = "catppuccin",
		-- priority = 1000,
		-- config = function()
		-- 	vim.cmd.colorscheme "catppuccin"
		-- end
	},
	{
		"EdenEast/nightfox.nvim",
		-- priority = 1000,
		-- event = "VeryLazy",
		config = function()
			vim.cmd.colorscheme "nightfox"
		end
	}
}
