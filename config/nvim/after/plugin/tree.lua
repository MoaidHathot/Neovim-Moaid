local tree = require('nvim-tree')

tree.setup {
	renderer = {
		group_empty = true,
	},
	filters = {
		dotfiles = true,
	}
}

vim.opt.termguicolors = true


vim.keymap.set("n", "<leader>e", vim.cmd.NvimTreeToggle)
vim.keymap.set('n', "<leader>tc", vim.cmd.NvimTreeCollapse)
vim.keymap.set('n', "<leader>tf", vim.cmd.NvimTreeFindFile)
