return {
	{
		'karb94/neoscroll.nvim',
		event = "VeryLazy",
		config = function()
			require('neoscroll').setup({})
		end
	},
	{
		'kevinhwang91/nvim-hlslens',
		event = "VeryLazy",
		config = function()
			require('hlslens').setup()

			vim.api.nvim_set_keymap('n', 'n',
				[[<Cmd>execute('normal! ' . v:count1 . 'n')<CR><Cmd>lua require('hlslens').start()<CR>]],
				{ desc = "Next search result", silent = true })

			vim.api.nvim_set_keymap('n', 'N',
				[[<Cmd>execute('normal! ' . v:count1 . 'N')<CR><Cmd>lua require('hlslens').start()<CR>]],
				{ desc = "Previous Search Result", silent = true })

			vim.api.nvim_set_keymap('n', '*', [[*<Cmd>lua require('hlslens').start()<CR>]],
				{ desc = 'Next Search Result Highlighted', silent = true })

			vim.api.nvim_set_keymap('n', '#', [[#<Cmd>lua require('hlslens').start()<CR>]],
				{ desc = "Previous Search Result Highlighted", silent = true })

			vim.api.nvim_set_keymap('n', 'g*', [[g*<Cmd>lua require('hlslens').start()<CR>]],
				{ desc = "Mark Current Word And Search Forward", silent = true })

			vim.api.nvim_set_keymap('n', 'g#', [[g#<Cmd>lua require('hlslens').start()<CR>]],
				{ desc = "Mark Current Workd and Search Backwards" })

			vim.api.nvim_set_keymap('n', '<Leader>n', '<Cmd>noh<CR>', { desc = "No HLS", silent = true })
		end

	},
	{
		'tpope/vim-surround',
		event = "VeryLazy"
	},
	{
		'kosayoda/nvim-lightbulb',
		event = "VeryLazy",
		config = function()
			require('nvim-lightbulb').setup({
				autocmd = { enabled = true }
			})
		end
	},
	{
		'chentoast/marks.nvim',
		event = "VeryLazy",
		config = function()
			require('marks').setup({})
		end
	},
	{
		'HiPhish/nvim-ts-rainbow2',
		event = "VeryLazy",
		config = function()
			require('nvim-treesitter.configs').setup({
				rainbow = {
					enable = true,
					extended_mode = true,
				}
			})
		end
	},
	{
		'RRethy/vim-illuminate',
		event = "VeryLazy",
		enable = false,
	},
	{
		"petertriho/nvim-scrollbar",
		event = "VeryLazy",
		config = function()
			require('scrollbar').setup({})
		end
	}
}
