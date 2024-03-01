return {
	"nvim-neo-tree/neo-tree.nvim",
	-- event = "VeryLazy",
	branch = "v3.x",
	keys = {
		{ '<leader>e', ':Neotree reveal toggle<CR>' },
		{ '<leader>tf', function()
			local currBuffer = vim.api.nvim_buf_get_name(0)
			vim.cmd("Neotree reveal_file=" .. currBuffer)
		end }
	},
	dependencies = {
		"nvim-lua/plenary.nvim",
		"nvim-tree/nvim-web-devicons", -- not strictly required, but recommended
		"MunifTanjim/nui.nvim",
		-- "3rd/image.nvim", -- Optional image support in preview window: See `# Preview Mode` for more information
	},
	-- config = function()
	-- 	vim.keymap.set('n', '<leader>e', ":Neotree reveal toggle<CR>", {})
	-- 	vim.keymap.set('n', '<leader>tf', function()
	-- 		local currBuffer = vim.api.nvim_buf_get_name(0)
	-- 		vim.cmd("Neotree reveal_file=" .. currBuffer)
	-- 	end)
	-- end
}
