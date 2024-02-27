local trouble = require('trouble')

trouble.setup {
	auto_preview = false
}

vim.keymap.set('n', '<leader>lq', ":TroubleToggle document_diagnostics<CR>", { desc = "Toggle Document Diagnostics" })
vim.keymap.set('n', '<leader>ld', ":TroubleToggle document_diagnostics<CR>", { desc = "Toggle Document Diagnostics" })
vim.keymap.set('n', '<leader>lD', ":TroubleToggle lsp_definitions<CR>", { desc = "Toggle LSP Definitions" })
-- vim.keymap.set('n', '<leader>la', ':TroubleToggle quickfix<CR>')
vim.keymap.set('n', '<leader>ll', ':TroubleToggle loclist<CR>', { desc = "Toggle Locallist" })
vim.keymap.set('n', '<leader>lw', ':TroubleToggle workspace_diagnostics<CR>', { desc = "Toggle Workspace Diagnostics" })
vim.keymap.set('n', '<leader>lR', ':TroubleToggle lsp_references<CR>', { desc = "Toggle LSP References" })
vim.keymap.set('n', '<leader>lr', vim.lsp.buf.rename, { desc = "toggle lsp references" })
vim.keymap.set('n', '<f2>', vim.lsp.buf.rename, { desc = "toggle lsp references" })
vim.keymap.set('n', '<leader>lI', ':TroubleToggle lsp_implementations<CR>', { desc = "Toggle LSP References" })
