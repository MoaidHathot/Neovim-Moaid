require('actions-preview').setup {

}

vim.keymap.set({ 'n', 'v' }, '<leader>la', require('actions-preview').code_actions)
