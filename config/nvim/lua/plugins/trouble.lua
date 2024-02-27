return {
	"folke/trouble.nvim",
	event = "VeryLazy",
	dependencies = { "nvim-tree/nvim-web-devicons" },
	opts = {
		auto_preview = true
	},
	config = function()
		vim.keymap.set('n', '<leader>lq', ":TroubleToggle document_diagnostics<CR>",
			{ desc = "Toggle Document Diagnostics" })
		vim.keymap.set('n', '<leader>ld', ":TroubleToggle document_diagnostics<CR>",
			{ desc = "Toggle Document Diagnostics" })
		vim.keymap.set('n', '<leader>ll', ':TroubleToggle loclist<CR>', { desc = "Toggle Locallist" })
		vim.keymap.set('n', '<leader>lw', ':TroubleToggle workspace_diagnostics<CR>',
			{ desc = "Toggle Workspace Diagnostics" })
		vim.keymap.set('n', '<leader>lr', ':TroubleToggle lsp_references<CR>', { desc = "Toggle LSP References" })
	end
}
