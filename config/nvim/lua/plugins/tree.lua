return {
	{
		"nvim-neo-tree/neo-tree.nvim",
		enabled = true,
		-- event = "VeryLazy",
		branch = "v3.x",
		keys = {
			{ '<leader>e', ':Neotree reveal toggle<CR>', desc = "Toggle Neotree" },
			{
				'<leader>tf',
				function()
					local currBuffer = vim.api.nvim_buf_get_name(0)
					vim.cmd("Neotree reveal_file=" .. currBuffer)
				end,
				desc = "Find file in Neotree"
			}
		},
		dependencies = {
			"nvim-lua/plenary.nvim",
			"nvim-tree/nvim-web-devicons", -- not strictly required, but recommended
			"MunifTanjim/nui.nvim",
			-- "3rd/image.nvim", -- Optional image support in preview window: See `# Preview Mode` for more information
		},
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
