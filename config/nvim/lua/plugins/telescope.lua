return {
	{
		'nvim-telescope/telescope.nvim',
		event = "VeryLazy",
		-- tag = '0.1.5',
		dependencies = {
			'nvim-lua/plenary.nvim',
			{
				'nvim-telescope/telescope-fzf-native.nvim',
				build = 'make'
			}
		},
		opts = {
			defaults = {
				mappings = {
					i = { ["<C-t>"] = function() require("trouble.sources.telescope").open() end },
					n = { ["<C-t>"] = function() require('trouble.sources.telescope').open() end },
				},
				path_display = { 'filename_first' }
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
			{ '<leader>sf', function() require('telescope.builtin').find_files() end,   { desc = 'Find Files' } },
			-- vim.keymap.set('n', '<C-p>', require('telescope.builtin').find_files, { desc = 'Find Files' })
			{ '<leader>sg', function() require('telescope.builtin').live_grep() end,    { desc = 'Find Grep' } },
			{ '<leader>sG',
				function()
					require('telescope.builtin').live_grep { additional_args = function(args)
						return vim.list_extend(args,
							{ '--hidden', '--no-ignore' })
					end }
				end, { desc = 'Find Grep Everything' } },
			{ '<leader>sb', function() require('telescope.builtin').buffers() end,                              { desc = 'Find Buffers' } },
			{ '<leader>sh', function() require('telescope.builtin').help_tags() end,                            { desc = 'Find Help' } },
			{ '<leader>sc', function() require('telescope.builtin').current_buffer_fuzzy_find() end,            { desc = 'Find in current buffer' } },
			{ '<leader>sd', function() require('telescope.builtin').diagnostics() end,                          { desc = 'Find Diagnostics' } },
			{ '<leader>sk', function() require('telescope.builtin').keymaps() end,                              { desc = 'Find Keymaps' } },
			{ '<leader>sp', function() require('telescope.builtin').git_files() end,                            { desc = 'Find Project git files' } },
			-- vim.keymap.set('n', '<leader>sB', ":Telescope file_browser path=%:p:h select_buffer=true<CR>",
			-- { desc = "File Browser" })
			-- vim.keymap.set('n', '<leader>sP', ":Telescope project<CR>", { desc = "Find Projects" })
			{ '<leader>sr', function() require('telescope.builtin').registers() end,                            { desc = 'Find Registers' } },
			{ '<leader>sR', function() require('telescope.builtin').resume() end,                               { desc = 'Open last picker' } },
			{ '<leader>sm', function() require('telescope.builtin').marks() end,                                { desc = 'Find Marks' } },
			-- vim.keymap.set('n', '<leader>sC', require('telescope.builtin').colorscheme, { desc = 'Find Color Scheme' })
			{ '<leader>sC', function() require('telescope.builtin').colorscheme({ enable_preview = true }) end, { desc = 'Find Color Scheme' } },
			{ '<leader>sj', function() require('telescope.builtin').jumplist() end,                             { desc = 'Find Jump List' } },
			{ '<leader>so', function() require('telescope.builtin').oldfiles() end,                             { desc = 'Find Recent Files' } },

			{ '<leader>lQ', function() require('telescope.builtin').quickfix() end,                             { desc = 'Find Quick Fixes' } },
			{ '<leader>gi', function() require('telescope.builtin').lsp_implementations() end,                  { desc = 'Find Implementations' } },
			{ '<leader>gd', function() require('telescope.builtin').lsp_definitions() end,                      { desc = 'Find Definitions' } },
			{ '<leader>gD', function() require('telescope.builtin').lsp_type_definitions() end,                 { desc = 'Find Definitions' } },

			{ '<leader>gb', function() require('telescope.builtin').git_branches() end,                         { desc = 'Git Branches' } },
			{ '<leader>gs', function() require('telescope.builtin').git_status() end,                           { desc = 'Git Status' } },
			{ '<leader>gS', function() require('telescope.builtin').git_stash() end,                            { desc = 'Git Stash' } },


			{ '<leader>st', function() require('telescope.builtin').builtin() end,                              { desc = 'Find Telescope Pickers' } },
			{ '<leader>sT', function() require('telescope.builtin').builtin() end,                              { desc = 'Find Telescope cached Pickers' } },
			{ '<leader>st', function()
				local opts = {}
				opts.cwd = opts.cwd or vim.uv.cwd()
				opts.delimeter = opts.delimeter or "  "
				opts.hidden = opts.hidden or true
				opts.ignored = opts.ignored or false

				local pickers = require('telescope.pickers')
				local finders = require('telescope.finders')
				local make_entry = require('telescope.make_entry')
				local config = require('telescope.config').values

				local finder = finders.new_async_job({
					command_generator = function(prompt)
						if not prompt or prompt == "" then
							return nil
						end

						local pieces = vim.split(prompt, opts.delimeter)
						local args = { "rg" }

						if pieces[1] then
							table.insert(args, "-e")
							table.insert(args, pieces[1])
						end

						local type = nil
						local more_args_pieces = nil
						local more_more_pieces = nil

						local command_args = {}

						-- print("Pieces", vim.inspect(pieces))

						if pieces[2] then
							if pieces[2]:find("%*") then
								type = pieces[2]
							elseif pieces[2]:find("%-") then
								more_args_pieces = pieces[2]
							end

							if pieces[3] then
								if pieces[3]:find("%*") then
									type = pieces[3]
								elseif pieces[3]:find("%-") then
									more_more_pieces = pieces[3]
								end
							end
						end

						if type then
							table.insert(args, "-g")
							table.insert(args, type)
						end

						if more_args_pieces then
							for match in more_args_pieces:gmatch("%-%-%S+") do
								table.insert(command_args, match)
							end
						end

						if more_more_pieces then
							for match in more_more_pieces:gmatch("%-%-%S+") do
								table.insert(command_args, match)
							end
						end

						table.insert(command_args, { "--color=never", "--no-heading", "--with-filename", "--line-number", "--column", "--smart-case", "--follow" })

						local final_args = vim.tbl_flatten {
							args,
							-- { "--color=never", "--no-heading", "--with-filename", "--line-number", "--column", "--smart-case", "--follow" },
							command_args
						}

						-- print(vim.inspect(final_args))

						return final_args
					end,

					entry_maker = make_entry.gen_from_vimgrep(opts),
					cwd = opts.cwd,
				})

				pickers.new(opts, {
					debounce = 100,
					prompt_title = "Grep with Filter",
					finder = finder,
					previewer = config.grep_previewer(opts),
					sorter = require('telescope.sorters').empty(),
				}):find()
			end, { desc = 'Find Grep with Filters' } }
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
	-- {
	-- 	'nvim-telescope/telescope-fzf-native.nvim',
	-- 	build = 'make'
	-- }
}
