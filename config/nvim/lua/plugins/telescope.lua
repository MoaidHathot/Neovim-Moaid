return {
	{
		'nvim-telescope/telescope.nvim',
		event = "VeryLazy",
		tag = '0.1.5',
		dependencies = {
			'nvim-lua/plenary.nvim',
			-- 'nvim-treesitter/nvim-treesitter'
		},
		config = function()
			local builtin = require('telescope.builtin')
			vim.keymap.set('n', '<leader>sF', "<cmd>Telescope find_files hidden=true no_ignore=true<CR>",
				{ desc = 'Find All Files' })
			vim.keymap.set('n', '<leader>sf', builtin.find_files, { desc = 'Find Files' })
			vim.keymap.set('n', '<C-p>', builtin.find_files, { desc = 'Find Files' })
			vim.keymap.set('n', '<leader>sg', builtin.live_grep, { desc = 'Find Grep' })
			vim.keymap.set('n', '<leader>sG',
				function()
					builtin.live_grep { additional_args = function(args)
						return vim.list_extend(args,
							{ '--hidden', '--no-ignore' })
					end }
				end, { desc = 'Find Grep Everything' })
			vim.keymap.set('n', '<leader>sb', builtin.buffers, { desc = 'Find Buffers' })
			vim.keymap.set('n', '<leader>sh', builtin.help_tags, { desc = 'Find Help' })
			vim.keymap.set('n', '<leader>sc', builtin.current_buffer_fuzzy_find, { desc = 'Find in current buffer' })
			vim.keymap.set('n', '<leader>sd', builtin.diagnostics, { desc = 'Find Diagnostics' })
			vim.keymap.set('n', '<leader>sk', builtin.keymaps, { desc = 'Find Keymaps' })
			vim.keymap.set('n', '<leader>sp', builtin.git_files, { desc = 'Find Project git files' })
			-- vim.keymap.set('n', '<leader>sB', ":Telescope file_browser path=%:p:h select_buffer=true<CR>",
			-- { desc = "File Browser" })
			-- vim.keymap.set('n', '<leader>sP', ":Telescope project<CR>", { desc = "Find Projects" })
			vim.keymap.set('n', '<leader>sr', builtin.registers, { desc = 'Find Registers' })
			vim.keymap.set('n', '<leader>sR', builtin.resume, { desc = 'Open last picker' })
			vim.keymap.set('n', '<leader>sm', builtin.marks, { desc = 'Find Marks' })
			-- vim.keymap.set('n', '<leader>sC', builtin.colorscheme, { desc = 'Find Color Scheme' })
			vim.keymap.set('n', '<leader>sC', function()
				builtin.colorscheme({ enable_preview = true })
			end, { desc = 'Find Color Scheme' })
			vim.keymap.set('n', '<leader>sj', builtin.jumplist, { desc = 'Find Jump List' })
			vim.keymap.set('n', '<leader>so', builtin.oldfiles, { desc = 'Find Recent Files' })

			vim.keymap.set('n', '<leader>lQ', builtin.quickfix, { desc = 'Find Quick Fixes' })
			vim.keymap.set('n', '<leader>gi', builtin.lsp_implementations, { desc = 'Find Implementations' })
			vim.keymap.set('n', '<leader>gd', builtin.lsp_definitions, { desc = 'Find Definitions' })
			vim.keymap.set('n', '<leader>gD', builtin.lsp_type_definitions, { desc = 'Find Definitions' })

			vim.keymap.set('n', '<leader>gb', builtin.git_branches, { desc = 'Git Branches' })
			vim.keymap.set('n', '<leader>gs', builtin.git_status, { desc = 'Git Status' })
			vim.keymap.set('n', '<leader>gS', builtin.git_stash, { desc = 'Git Stash' })


			vim.keymap.set('n', '<leader>st', builtin.builtin, { desc = 'Find Telescope Pickers' })
			vim.keymap.set('n', '<leader>sT', builtin.builtin, { desc = 'Find Telescope cached Pickers' })
		end
	},
	{
		'nvim-telescope/telescope-ui-select.nvim',
		'nvim-telescope/telescope-fzf-native.nvim',
		-- event = "VeryLazy"
		cmd = "Telescope",
		config = function()
			local telescope = require('telescope')
			telescope.setup({
				defaults = {
					mappings = {
						i = { ["<C-t>"] = require('trouble.providers.telescope').open_with_trouble },
						n = { ["<C-t>"] = require('trouble.providers.telescope').open_with_trouble },
					}
				},
				extensions = {
					["ui-select"] = {
						require("telescope.themes").get_dropdown {
						},
						file_browser = {
							theme = 'ivy',
							--hijack_newtrw = true
						}
					},
					fzf = {
						fuzzy = true, -- false will only do exact matching
						override_generic_sorter = true, -- override the generic sorter
						override_file_sorter = true, -- override the file sorter
						case_mode = "smart_case", -- or "ignore_case" or "respect_case"
					}
				}
			})

			telescope.load_extension('ui-select')
			telescope.load_extension('fzf')
		end
	},
	{
		'nvim-telescope/telescope-fzf-native.nvim',
		build = 'make'
	}
}
