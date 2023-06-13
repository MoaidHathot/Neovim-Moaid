local tree = require('nvim-tree')

tree.setup {
	disable_netrw = true,
	hijack_netrw = true,
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
		dotfiles = false,
	},
	view = {
		number = true,
		relativenumber = true,
		width = 45,
		-- preservce_window_proportions = true,
	},
	diagnostics = {
		enable = true,
		show_on_dirs = true,
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
}

vim.keymap.set("n", "<leader>e", vim.cmd.NvimTreeToggle)
vim.keymap.set('n', "<leader>tc", vim.cmd.NvimTreeCollapse)
vim.keymap.set('n', "<leader>tf", vim.cmd.NvimTreeFindFile)
