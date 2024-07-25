return
{
	{
		'akinsho/bufferline.nvim',
		-- enabled = false,
		-- event = "VeryLazy",
		event = { "BufReadPre", "BufNewFile" },
		version = "*",
		dependencies = {
			'nvim-tree/nvim-web-devicons'
		},
		-- lazy = false,
		config = function()
			local bufferline = require('bufferline')

			vim.keymap.set('n', '<leader>bf', "<cmd>:BufferLinePick<CR>", { desc = 'Pick Buffer' })
			vim.keymap.set('n', '<leader>bs', "<cmd>:BufferLinePick<CR>", { desc = 'Pick Buffer' })
			vim.keymap.set('n', '<leader>bp', "<cmd>:BufferLineTogglePin<CR>", { desc = 'Pin Buffer' })


			bufferline.setup {
				options = {
					numbers = "none",
					indicator = {
						icon = '▎',
						style = 'icon'
					},
					offsets = {
						{
							filetype = "NvimTree",
							text = "File Explorer",
							separator = true
						}
					},
					separator_style = "think",
					hover = {
						enabled = true,
						delay = 200,
						reveal = { 'close' }
					},
					diagnostics = "nvim_lsp",
					diagnostics_indicator = function(count, level, diagnostics_dict, context)
						-- return "("..count..")"
						local icon = level:match("error") and " " or " "
						return " " .. icon .. count
					end,
				}
			}
		end
	},
	{
		'romgrk/barbar.nvim',
		enabled = false,
		dependencies = {
			'lewis6991/gitsigns.nvim', -- OPTIONAL: for git status
			'nvim-tree/nvim-web-devicons', -- OPTIONAL: for file icons
		},
		init = function()
			vim.g.barbar_auto_setup = false
			vim.keymap.set('n', '<leader>bs', "<cmd>:BufferPick<CR>", { desc = 'Pick Buffer' })
			vim.keymap.set('n', '<leader>bp', "<cmd>:BufferPin<CR>", { desc = 'Pin Buffer' })
		end,
		opts = {
			-- lazy.nvim will automatically call setup for you. put your options here, anything missing will use the default:
			-- animation = true,
			-- insert_at_start = true,
			-- …etc.
		},
	}
}
