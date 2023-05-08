local builtin = require('telescope.builtin')

--vim.keymap.set('n', '<leader>pf', builtin.find_files, {})

-- vim.keymap.set('n', '<leader>f', builtin.find_files, {})
-- vim.keymap.set('n', '<leader>f', builtin.find_files, { desc = 'Find Files' })
-- vim.keymap.set('n', '<leader>ff', builtin.find_files, { desc = 'Find Files' })


vim.keymap.set('n', '<leader>st', builtin.buffers, { desc = 'Find Buffers' })
vim.keymap.set('n', '<leader>sf', builtin.find_files, { desc = 'Find Files' })
vim.keymap.set('n', '<leader>sg', builtin.live_grep, { desc = 'Find Grep' })
vim.keymap.set('n', '<leader>sb', builtin.buffers, { desc = 'Find Buffers' })
vim.keymap.set('n', '<leader>sh', builtin.help_tags, { desc = 'Find Help' })
vim.keymap.set('n', '<leader>sc', builtin.current_buffer_fuzzy_find, { desc = 'Find in current buffer' })
vim.keymap.set('n', '<leader>sd', builtin.diagnostics, { desc = 'Find Diagnostics' })
vim.keymap.set('n', '<leader>sk', builtin.keymaps, { desc = 'Find Keymaps' })
vim.keymap.set('n', '<leader>sp', builtin.git_files, { desc = 'Find Project git files' })

-- local telescope = require('telescope')
-- local actions = require('telescope.actions')
-- local trouble = require('trouble.providers.telescope')
