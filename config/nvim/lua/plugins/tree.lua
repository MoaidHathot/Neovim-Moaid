local power_review_dir = require("config.power-review").dir

return {
	{
		"nvim-neo-tree/neo-tree.nvim",
		enabled = true,
		cmd = "Neotree",
		-- event = "VeryLazy",
		branch = "v3.x",
		keys = {
			{ mode = { 'n', 'v' },'<leader>e', ':Neotree reveal toggle<CR>', desc = "Toggle Neotree" },
			{
				'<leader>tf',
				mode = { 'n', 'v' },
				function()
					require("neo-tree.command").execute({
						action = "focus",
						source = "filesystem",
						reveal_file = vim.api.nvim_buf_get_name(0),
					})
				end,
				desc = "Find file in Neotree"
			}
		},
		dependencies = {
			"nvim-lua/plenary.nvim",
			"nvim-tree/nvim-web-devicons", -- not strictly required, but recommended
			"MunifTanjim/nui.nvim",
			power_review_dir and "power-review.nvim" or nil,
			-- "3rd/image.nvim", -- Optional image support in preview window: See `# Preview Mode` for more information
		},
		opts = function()
			local opts = {
				sources = {
					"filesystem",
					"buffers",
					"git_status",
				},
				filesystem = {
					use_libuv_file_watcher = true,
				},
				source_selector = {
					winbar = false,
					sources = {
						{ source = "filesystem", display_name = " Files" },
						{ source = "buffers", display_name = " Buffers" },
						{ source = "git_status", display_name = " Git" },
					},
				},
				window = {
					mappings = {
						["Y"] = function(state)
							-- Copy absolute path to clipboard
							local node = state.tree:get_node()
							local filepath = node:get_id()
							vim.fn.setreg("+", filepath)
							vim.notify("Copied path: " .. filepath)
						end,
						["y"] = function(state)
							-- Copy file name to clipboard
							local node = state.tree:get_node()
							local filename = node.name
							vim.fn.setreg("+", filename)
							vim.notify("Copied name: " .. filename)
						end,
					},
				},
			}
			if power_review_dir then
				table.insert(opts.sources, "power_review")
				table.insert(opts.source_selector.sources, { source = "power_review", display_name = " PR Review" })
				opts.power_review = require("power-review.config").get().ui.neotree
			end
			return opts
		end,
		-- opts = function(_, opts)
		-- 	local function on_move(data)
		-- 		Snacks.rename.on_rename_file(data.source, data.destination)
		-- 	end
		-- 	local events = require("neo-tree.events")
		-- 	opts.event_handlers = opts.event_handlers or {}
		-- 	vim.list_extend(opts.event_handlers, {
		-- 		{ event = events.FILE_MOVED,   handler = on_move },
		-- 		{ event = events.FILE_RENAMED, handler = on_move },
		-- 	})
		-- end
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
			{ mode = { 'n', 'v' },'<leader>e',  vim.cmd.NvimTreeToggle },
			{ mode = { 'n', 'v' },'<leader>tc', vim.cmd.NvimTreeCollapse },
			{ mode = { 'n', 'v' },'<leader>tf', vim.cmd.NvimTreeFindFile }
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
