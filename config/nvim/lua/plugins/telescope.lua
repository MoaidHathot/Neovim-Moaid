return {
	{
		'nvim-telescope/telescope.nvim',
		event = "VeryLazy",
		-- tag = '0.1.5',
		dependencies = {
			'nvim-lua/plenary.nvim',
		},
		opts = {
			defaults = {
				mappings = {
					i = { ["<C-t>"] = function() require("trouble.sources.telescope").open() end },
					n = { ["<C-t>"] = function() require('trouble.sources.telescope').open() end },
				},
				path_display = { 'filename_first'}
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
					fuzzy = true,    -- false will only do exact matching
					override_generic_sorter = true, -- override the generic sorter
					override_file_sorter = true, -- override the file sorter
					case_mode = "smart_case", -- or "ignore_case" or "respect_case"
				}
			}
		},
		keys = {
			{ '<leader>sF', "<cmd>Telescope find_files hidden=true no_ignore=true<CR>", { desc = 'Find All Files' } },
			{ '<leader>sf', require('telescope.builtin').find_files,                    { desc = 'Find Files' } },
			-- vim.keymap.set('n', '<C-p>', require('telescope.builtin').find_files, { desc = 'Find Files' })
			{ '<leader>sg', require('telescope.builtin').live_grep,                     { desc = 'Find Grep' } },
			{ '<leader>sG',
				function()
					require('telescope.builtin').live_grep { additional_args = function(args)
						return vim.list_extend(args,
							{ '--hidden', '--no-ignore' })
					end }
				end, { desc = 'Find Grep Everything' } },
			{ '<leader>sb', require('telescope.builtin').buffers,                                               { desc = 'Find Buffers' } },
			{ '<leader>sh', require('telescope.builtin').help_tags,                                             { desc = 'Find Help' } },
			{ '<leader>sc', require('telescope.builtin').current_buffer_fuzzy_find,                             { desc = 'Find in current buffer' } },
			{ '<leader>sd', require('telescope.builtin').diagnostics,                                           { desc = 'Find Diagnostics' } },
			{ '<leader>sk', require('telescope.builtin').keymaps,                                               { desc = 'Find Keymaps' } },
			{ '<leader>sp', require('telescope.builtin').git_files,                                             { desc = 'Find Project git files' } },
			-- vim.keymap.set('n', '<leader>sB', ":Telescope file_browser path=%:p:h select_buffer=true<CR>",
			-- { desc = "File Browser" })
			-- vim.keymap.set('n', '<leader>sP', ":Telescope project<CR>", { desc = "Find Projects" })
			{ '<leader>sr', require('telescope.builtin').registers,                                             { desc = 'Find Registers' } },
			{ '<leader>sR', require('telescope.builtin').resume,                                                { desc = 'Open last picker' } },
			{ '<leader>sm', require('telescope.builtin').marks,                                                 { desc = 'Find Marks' } },
			-- vim.keymap.set('n', '<leader>sC', require('telescope.builtin').colorscheme, { desc = 'Find Color Scheme' })
			{ '<leader>sC', function() require('telescope.builtin').colorscheme({ enable_preview = true }) end, { desc = 'Find Color Scheme' } },
			{ '<leader>sj', require('telescope.builtin').jumplist,                                              { desc = 'Find Jump List' } },
			{ '<leader>so', require('telescope.builtin').oldfiles,                                              { desc = 'Find Recent Files' } },

			{ '<leader>lQ', require('telescope.builtin').quickfix,                                              { desc = 'Find Quick Fixes' } },
			{ '<leader>gi', require('telescope.builtin').lsp_implementations,                                   { desc = 'Find Implementations' } },
			{ '<leader>gd', require('telescope.builtin').lsp_definitions,                                       { desc = 'Find Definitions' } },
			{ '<leader>gD', require('telescope.builtin').lsp_type_definitions,                                  { desc = 'Find Definitions' } },

			{ '<leader>gb', require('telescope.builtin').git_branches,                                          { desc = 'Git Branches' } },
			{ '<leader>gs', require('telescope.builtin').git_status,                                            { desc = 'Git Status' } },
			{ '<leader>gS', require('telescope.builtin').git_stash,                                             { desc = 'Git Stash' } },


			{ '<leader>st', require('telescope.builtin').builtin,                                               { desc = 'Find Telescope Pickers' } },
			{ '<leader>sT', require('telescope.builtin').builtin,                                               { desc = 'Find Telescope cached Pickers' } },
		},
	},
	{
		'nvim-telescope/telescope-ui-select.nvim',
		'nvim-telescope/telescope-fzf-native.nvim',
		-- enables = false,
		-- event = "VeryLazy"
		cmd = "Telescope",
		config = function()
			local telescope = require('telescope')

			telescope.load_extension('ui-select')
			telescope.load_extension('fzf')
		end
	},
	{
		'nvim-telescope/telescope-fzf-native.nvim',
		build = 'make'
	}
}
