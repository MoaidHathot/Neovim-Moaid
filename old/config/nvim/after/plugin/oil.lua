local oil = require('oil')

oil.setup {

}


vim.keymap.set('n', '<leader>mF', require('oil').open, { desc = "Edit File System", silent = true })
