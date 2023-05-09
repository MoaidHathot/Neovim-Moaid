local trouble = require('trouble')

trouble.setup {
	auto_preview = false
}

vim.keymap.set('n', '<leader>lq', ":TroubleToggle document_diagnostics<CR>")
vim.keymap.set('n', '<leader>ld', ":TroubleToggle document_diagnostics<CR>")
-- vim.keymap.set('n', '<leader>la', ':TroubleToggle quickfix<CR>')
vim.keymap.set('n', '<leader>ll', ':TroubleToggle loclist<CR>')
vim.keymap.set('n', '<leader>lw', ':TroubleToggle workspace_diagnostics<CR>')
vim.keymap.set('n', '<leader>lr', ':TroubleToggle lsp_references<CR>')


local telescope = require('telescope')
-- local actions = require('telescope.actions')

telescope.setup {
	defaults = {
		mappings = {
			i = { ["<c-t>"] = trouble.open_with_trouble },
			n = { ["<c-t>"] = trouble.open_with_trouble },
		}
	}
}
