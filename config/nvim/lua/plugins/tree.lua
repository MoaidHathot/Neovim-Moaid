return {
	{
		"nvim-neo-tree/neo-tree.nvim",
		enabled = true,
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
	},
	{
		'nvim-tree/nvim-tree.lua',
		version = "*",
		lazy = false,
		enabled = false,
		dependencies = {
			"nvim-tree/nvim-web-devicons"
		},
		keys = {
			{ '<leader>e',  vim.cmd.NvimTreeToggle },
			{ '<leader>tc', vim.cmd.NvimTreeCollapse },
			{ '<leader>tf', vim.cmd.NvimTreeFindFile }
		},
		config = function()
			require('nvim-tree').setup({
				disable_netrw = true,
				hijack_netrw = true,
				view = {
					number = true,
					relativenumber = true,
					width = 45,
				},
				renderer = {
					group_empty = true,
					highlight_git = true,
					-- highlight_opened_files = 'true',
					special_files = { "bin", "debug" }
				},
				update_focused_file = {
					enable = true
				},
				filters = {
					dotfiles = true,
				},
				modified = {
					enable = true,
				},
				git = {
					enable = true,
					timeout = 700,
				},
				actions = {
					open_file = {
						resize_window = false,
					}
				}
			})
		end
	}
}
