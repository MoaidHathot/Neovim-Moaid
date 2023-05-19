local tree = require('nvim-tree')

tree.setup {
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
	view = {
		number = true,
		relativenumber = true,
		-- preservce_window_proportions = true,
	},
	diagnostics = {
		enable = true,
		show_on_dirs = true,
	},
	modified = {
		enable = true,
	},
	actions = {
		open_file = {
			resize_window = false,
		},
	}
}

vim.keymap.set("n", "<leader>e", vim.cmd.NvimTreeToggle)
vim.keymap.set('n', "<leader>tc", vim.cmd.NvimTreeCollapse)
vim.keymap.set('n', "<leader>tf", vim.cmd.NvimTreeFindFile)
