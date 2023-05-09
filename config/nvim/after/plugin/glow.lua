local glow = require('glow')

glow.setup {
	style = "dark" -- dark/light	
}

vim.keymap.set('n', '<leader>mg', ":Glow<CR>")
