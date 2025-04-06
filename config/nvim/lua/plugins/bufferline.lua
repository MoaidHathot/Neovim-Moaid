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
		keys = {
			{ '<leader>/', mode = { 'n', 'v' } },
			{ mode = 'n', '<leader>bf', "<cmd>:BufferLinePick<CR>",  desc = 'Pick Buffer' },
			-- { mode = 'n', '<leader>bs', "<cmd>:BufferLinePick<CR>",  desc = 'Pick Buffer' },
			{ mode = 'n', '<leader>bp', "<cmd>:BufferLineTogglePin<CR>",  desc = 'Pin Buffer' },
		},
		opts = {
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
					-- diagnostics = "nvim_lsp",
					-- diagnostics_indicator = function(count, level, diagnostics_dict, context)
					-- 	-- return "("..count..")"
					-- 	local icon = level:match("error") and " " or " "
					-- 	return " " .. icon .. count
					-- end,
					sort_by = 'insert_at_end',
				}
		},
	},
	{
		'romgrk/barbar.nvim',
		enabled = false,
		dependencies = {
			'lewis6991/gitsigns.nvim', -- OPTIONAL: for git status
			'nvim-tree/nvim-web-devicons', -- OPTIONAL: for file icons
		},
		keys = {
			{ '<leader>/', mode = { 'n', 'v' } },
			{ mode = 'n', '<leader>bf', "<cmd>:BufferPick<CR>",  desc = 'Pick Buffer' },
			{ mode = 'n', '<leader>bp', "<cmd>:BufferLineTogglePin<CR>",  desc = 'Pin Buffer' },
		},
		-- init = function()
		-- 	vim.g.barbar_auto_setup = false
		-- end,
		opts = {
		},
	}
}
