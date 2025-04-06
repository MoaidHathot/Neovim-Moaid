return {
	{
		'karb94/neoscroll.nvim',
		event = "VeryLazy",
		opts = {}
	},
	{
		'kevinhwang91/nvim-hlslens',
		event = "VeryLazy",
		keys = {
			{ mode = 'n', '<Leader>n', '<Cmd>noh><CR>', { desc = "No HLS", silent = true} },
			{ mode ='n', 'n', [[<Cmd>execute('normal! ' . v:count1 . 'n')<CR><Cmd>lua require('hlslens').start()<CR>]], { desc = "Next search result", silent = true }},
			{ mode ='n', 'N', [[<Cmd>execute('normal! ' . v:count1 . 'N')<CR><Cmd>lua require('hlslens').start()<CR>]], { desc = "Previous Search Result", silent = true }},
			{ mode ='n', '*', [[*<Cmd>lua require('hlslens').start()<CR>]], { desc = 'Next Search Result Highlighted', silent = true }},
			{ mode ='n', '#', [[#<Cmd>lua require('hlslens').start()<CR>]], { desc = "Previous Search Result Highlighted", silent = true }},
			{ mode ='n', 'g*', [[g*<Cmd>lua require('hlslens').start()<CR>]], { desc = "Mark Current Word And Search Forward", silent = true }},
			{ mode ='n', 'g#', [[g#<Cmd>lua require('hlslens').start()<CR>]], { desc = "Mark Current Workd and Search Backwards" }},
			{ mode ='n', '<Leader>n', '<Cmd>noh<CR>', { desc = "No HLS", silent = true }},

		},
		config = function()
			require('hlslens').setup()
		end
	},
	{
		'tpope/vim-surround',
		event = "VeryLazy"
	},
	-- {
	-- 	'kosayoda/nvim-lightbulb',
	-- 	event = "VeryLazy",
	-- 	config = function()
	-- 		require('nvim-lightbulb').setup({
	-- 			autocmd = { enabled = true }
	-- 		})
	-- 	end
	-- },
	{
		'chentoast/marks.nvim',
		event = "VeryLazy",
		opts = {},
	},
	{
		'HiPhish/nvim-ts-rainbow2',
		event = { "BufReadPre", "BufNewFile" },
		enabled = false,
		-- event = "VeryLazy",
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
		'HiPhish/rainbow-delimiters.nvim',
		enabled = true,
		event = { "BufReadPre", "BufNewFile" },
		-- config = function()
		-- 	require('rainbow-delimiters.setup').setup {
		-- 	}
		-- end
	},
	{
		"tzachar/local-highlight.nvim",
		enabled = false,
		event = "VeryLazy",
		config = function()
			require('local-highlight').setup({
				insert_mode = true,
			})
		end
	},
	{
		"petertriho/nvim-scrollbar",
		event = "VeryLazy",
		config = function()
			require('scrollbar').setup({})
		end
	},
	{
		"azabiong/vim-highlighter",
		event = { "BufReadPre", "BufNewFile" },
		enabled = true,
		init = function()
			 vim.cmd([[
			   let HiSet   = 'f<CR>'
			   let HiErase = 'f<BS>'
			   let HiClear = 'f<C-L>'
			   let HiFind  = 'f<Tab>'
			   let HiSetSL = 't<CR>'
			 ]])
		end
	},
}
