local glow = require('glow')

glow.setup {
	style = "dark" -- dark/light	
}

vim.keymap.set('n', '<leader>ms', ":Glow<CR>")
