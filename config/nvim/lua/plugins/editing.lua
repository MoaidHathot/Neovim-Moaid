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
			{ '<Leader>n', '<Cmd>noh<CR>', mode = 'n', desc = "No HLS", silent = true },
			{ 'n', [[<Cmd>execute('normal! ' . v:count1 . 'n')<CR><Cmd>lua require('hlslens').start()<CR>]], mode = 'n', desc = "Next search result", silent = true },
			{ 'N', [[<Cmd>execute('normal! ' . v:count1 . 'N')<CR><Cmd>lua require('hlslens').start()<CR>]], mode = 'n', desc = "Previous Search Result", silent = true },
			{ '*', [[*<Cmd>lua require('hlslens').start()<CR>]], mode = 'n', desc = 'Next Search Result Highlighted', silent = true },
			{ '#', [[#<Cmd>lua require('hlslens').start()<CR>]], mode = 'n', desc = "Previous Search Result Highlighted", silent = true },
			{ 'g*', [[g*<Cmd>lua require('hlslens').start()<CR>]], mode = 'n', desc = "Mark Current Word And Search Forward", silent = true },
			{ 'g#', [[g#<Cmd>lua require('hlslens').start()<CR>]], mode = 'n', desc = "Mark Current Word and Search Backwards" },
		},
		main = "hlslens",
		opts = {},
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
		event = { "BufReadPost", "BufNewFile" },
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
		main = "scrollbar",
		opts = {},
	},
	{
		"azabiong/vim-highlighter",
		event = { "BufReadPost", "BufNewFile" },
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
