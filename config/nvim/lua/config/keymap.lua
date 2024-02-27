vim.g.mapleader = " "

-- save document
vim.keymap.set("n", "<C-s>", vim.cmd.w, { desc = "Save Buffer", silent = true })
vim.keymap.set("i", "<C-s>", vim.cmd.w, { desc = "Save Buffer", silent = true })
vim.keymap.set("v", "<C-s>", vim.cmd.w, { desc = "Save Buffer", silent = true })

-- save all documents
-- vim.keymap.set("n", "<C-S-s>", vim.cmd.wall, { silent = true })
-- vim.keymap.set("i", "<cs-s>", vim.cmd.wall, { silent = true })
-- vim.keymap.set("v", "<cs-R>", vim.cmd.wall, { silent = true })

-- vim.keymap.set('n', '<leader>mq', ':wa<CR>', { desc = "Save All Buffers", })

-- Delete text
vim.keymap.set('i', '<C-Del>', "<Esc>lce")
vim.keymap.set('n', '<C-Del>', "ce")
-- vim.keymap.set('i', '<C-BS>', "<Esc>cb")
-- vim.keymap.set('i', '<C-Backspace>', "<Esc><C-w>")
-- vim.keymap.set('n', '<C><BS>', "cb<Esc>")
-- vim.keymap.set('n', '<C-backspace>', "<Esc>cb")

-- vim.keymap.set('n', '<leader>q', ':q!<CR>:q!<CR>:q!<CR>')
vim.keymap.set({ 'n', 't', 'v' }, '<leader>q', ':qa<CR>:qa<CR>:qa<CR>')
vim.keymap.set({ 'n', 't', 'v' }, '<leader>Q', ':q!<CR>:q!<CR>:q!<CR>')

-- Split navigation and management
vim.keymap.set('n', '<leader>bb', ':bprev<CR>', { desc = 'Goto Previous Buffer', silent = true })
vim.keymap.set('n', '<leader>bn', ':bnext<CR>', { desc = 'Goto Next Buffer', silent = true })
vim.keymap.set('n', '<C-left>', ':bprev<CR>', { desc = 'Goto Previous Buffer', silent = true })
vim.keymap.set('n', '<C-right>', ':bnext<CR>', { desc = 'Goto Next Buffer', silent = true })
-- vim.keymap.set('n', '<leader>c', ':bprev<CR>:bdelete #<CR>')
vim.keymap.set('n', '<leader>bd', ':bprev<CR>:bdelete #<CR>', { desc = 'Close Current Buffer' })
vim.keymap.set('n', '<leader>bD', "<cmd>:%bd<CR>", { desc = 'Close All Buffers' })
vim.keymap.set('n', '<leader>bC', "<cmd>%bd|e#|bd#<CR>", { desc = 'Close All Buffers But This' })
vim.keymap.set('n', '<leader>bf', "<cmd>:BufferLinePick<CR>", { desc = 'Pick Buffer' })
vim.keymap.set('n', '<leader>bs', "<cmd>:BufferLinePick<CR>", { desc = 'Pick Buffer' })
vim.keymap.set('n', '<leader>bp', "<cmd>:BufferLineTogglePin<CR>", { desc = 'Pin Buffer' })
vim.keymap.set('n', '<leader>br', "<cmd>:e!<CR>", { desc = 'Reload Buffer' })

-- Move between splits
vim.keymap.set({ 'n', }, '<C-h>', ':wincmd h<CR>', { desc = 'Goto Left Buffer', silent = true })
vim.keymap.set({ 'n', }, '<C-l>', ':wincmd l<CR>', { desc = 'Goto Right Buffer', silent = true })
vim.keymap.set({ 'n', }, '<C-j>', ':wincmd j<CR>', { desc = 'Goto Below Buffer', silent = true })
vim.keymap.set({ 'n', }, '<C-k>', ':wincmd k<CR>', { desc = 'Goto Above Buffer', silent = true })

vim.keymap.set('t', '<C-h>', '[[<Cmd>wincmd h<CR>]]', { desc = 'Goto Left Buffer', silent = true, buffer = 0 })
vim.keymap.set('t', '<C-l>', '[[<Cmd>wincmd l<CR>]]', { desc = 'Goto Right Buffer', silent = true, buffer = 0 })
vim.keymap.set('t', '<C-j>', '[[<Cmd>wincmd j<CR>]]', { desc = 'Goto Below Buffer', silent = true, buffer = 0 })
vim.keymap.set('t', '<C-k>', '[[<Cmd>wincmd k<CR>]]', { desc = 'Goto Above Buffer', silent = true, buffer = 0 })


vim.keymap.set('n', "<S-q>", '<cmd>:q<CR>', { desc = "Close Without Saving" })

-- Reise splits
-- vim.keymap.set({ 'n', 't' }, '<S-Left>', ':vertical-resize +1<CR>', { silent = true })
-- vim.keymap.set({ 'n', 't' }, '<S-Right>', ':vertical-resize -1<CR>', { silent = true })
vim.keymap.set({ 'n', 't' }, '<S-Left>', ':vertical res +1^M<CR>', { silent = true })
vim.keymap.set({ 'n', 't' }, '<S-Right>', ':vertical res -1^M<CR>', { silent = true })
vim.keymap.set({ 'n', 't' }, '<C-Up>', ':resize -1<CR>', { silent = true })
vim.keymap.set({ 'n', 't' }, '<C-Down>', ':resize +1<CR>', { silent = true })
vim.keymap.set({ 'n' }, '<S-l>', '10zl', { desc = "Scroll To The Right", silent = true })
vim.keymap.set({ 'n' }, '<S-h>', '10zh', { desc = "Scroll To The Left", silent = true })
-- Move current line / block with Alt-j/k a la vscode.
vim.keymap.set('n', "<M-Down>", ":m .+1<CR>==", { silent = true })
vim.keymap.set('n', "<M-Up>", ":m .-2<CR>==", { silent = true })

-- Better line / block movement
-- vim.keymap.set('n', "<A-j>", ":m '>+1<CR>gv-gv", { silent = true })
-- vim.keymap.set('n', "<A-k>", ":m '<-2<CR>gv-gv", { silent = true })

-- Better indenting in Visual mode
vim.keymap.set('v', '>', ">gv")
vim.keymap.set('v', '<', "<gv")

vim.keymap.set('i', "<C-k>", 'k')

vim.keymap.set('n', '<leader>ps', "<cmd>:w<CR>:so<CR>:Lazy sync<CR>")
-- vim.keymap.set('n', '<leader>ms', "<cmd>:w<CR>:so<CR>")
vim.keymap.set('i', '<C-c>', '<Esc>')

vim.keymap.set("n", "<leader>fs", vim.cmd.wall, { desc = "Save All Buffers", silent = true })
vim.keymap.set("v", "<leader>fs", vim.cmd.wall, { desc = "Save All Buffers", silent = true })
vim.keymap.set('n', '<leader>fa', "gg<S-v>G<CR>", { desc = "Select All File" })
vim.keymap.set('n', '<leader>fC', '<cmd>:%y+<CR>', { desc = 'Copy All File To OS' })
-- vim.keymap.set('n', '<C-a>', 'ggVG', { desc = "Select All Lines" })
-- vim.keymap.set('n', '<leader>fV', 'gg<S-v>G<CR><leader>fv')
vim.keymap.set('n', '<leader>fv', '"+p', { desc = "Paste from OS" })
vim.keymap.set('v', '<leader>fv', '"+p', { desc = "Paste from OS" })
vim.keymap.set('v', '<leader>fc', '"+y', { desc = "Copy to OS" })
vim.keymap.set('n', '<leader>fh', '<cmd>:nohls<CR>', { desc = "No HLS" })
vim.keymap.set('v', '<leader>p', "\"_dP")
vim.keymap.set('i', '<C-p>', '<Esc>pa')

vim.keymap.set('n', '<leader>ms', "<cmd>:w<CR>:so<CR>", { desc = "Shout Out" })

-- create new lines in Normal mode
vim.keymap.set('n', '<leader>o', "o<Esc>^Da<Esc>k", { desc = 'Newline Below', silent = true })
vim.keymap.set('n', '<leader>O', "O<Esc>^Da<Esc>j", { desc = 'Newline Above', silent = true })

vim.keymap.set('i', '<S-tab>', '<esc><<i')

vim.keymap.set('n', '<S-Home>', 'gg')
vim.keymap.set('n', '<S-End>', 'G')
vim.keymap.set('n', '<Home>', '^')

vim.keymap.set('n', '<S-Down>', 'j')
vim.keymap.set('v', '<S-Down>', 'j')
vim.keymap.set('n', '<S-Up>', 'k')
vim.keymap.set('v', '<S-Up>', 'k')
