vim.g.mapleader = " "

local function get_bufs_loaded()
	local bufs_loaded = {}

	for i, buf_hndl in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_loaded(buf_hndl) then
			bufs_loaded[i] = buf_hndl
		end
	end

	return bufs_loaded
end

local function save_all_bufs(bufs)
	for i, buf in ipairs(bufs) do
		vim.api.nvim_buf_call(buf, function()
			vim.api.nvim_command(':w')
		end)
	end
end

-- save document
vim.keymap.set("n", "<C-s>", vim.cmd.w, { silent = true })
vim.keymap.set("i", "<C-s>", vim.cmd.w, { silent = true })
vim.keymap.set("v", "<C-s>", vim.cmd.w, { silent = true })

-- save all documents
vim.keymap.set("n", "<C-S-s>", vim.cmd.wall, { silent = false })
vim.keymap.set("i", "<C-S>s", vim.cmd.wall, { silent = true })
vim.keymap.set("v", "<C-S>s", vim.cmd.wall, { silent = true })

-- Delete text
vim.keymap.set('i', '<C-Del>', "<Esc>ce")
vim.keymap.set('i', '<C-backspiace>', "<Esc>cb")
vim.keymap.set('n', '<C-Del>', "ce")
vim.keymap.set('n', '<C-backspace>', "cb")

-- vim.keymap.set('n', '<leader>q', ':q!<CR>:q!<CR>:q!<CR>')
vim.keymap.set('n', '<leader>q', ':q<CR>:q<CR>:q<CR>')

-- Split navigation and management
vim.keymap.set('n', '<leader>bb', ':bprev<CR>', { silent = true })
vim.keymap.set('n', '<leader>bn', ':bnext<CR>', { silent = true })
-- vim.keymap.set('n', '<leader>c', ':bprev<CR>:bdelete #<CR>')
vim.keymap.set('n', '<leader>bd', ':bprev<CR>:bdelete #<CR>')

-- Move between splits
vim.keymap.set('n', '<C-h>', ':wincmd h<CR>', { silent = true })
vim.keymap.set('n', '<C-l>', ':wincmd l<CR>', { silent = true })
vim.keymap.set('n', '<C-j>', ':wincmd j<CR>', { silent = true })
vim.keymap.set('n', '<C-k>', ':wincmd k<CR>', { silent = true })

-- Reise splits
vim.keymap.set('n', '<C-Right>', ':vertical-resize +1<CR>', { silent = true })
vim.keymap.set('n', '<C-Left>', ':vertical-resize -1<CR>', { silent = true })
vim.keymap.set('n', '<C-Up>', ':resize -1<CR>', { silent = true })
vim.keymap.set('n', '<C-Down>', ':resize +1<CR>', { silent = true })

-- Move current line / block with Alt-j/k a la vscode.
vim.keymap.set('n', "<M-j>", ":m .+1<CR>==", { silent = true })
vim.keymap.set('n', "<M-k>", ":m .-2<CR>==, { silent = true }")

-- Better line / block movement
vim.keymap.set('n', "<A-j>", ":m '>+1<CR>gv-gv", { silent = true })
vim.keymap.set('n', "<A-k>", ":m '<-2<CR>gv-gv", { silent = true })

-- Better indenting in Visual mode
vim.keymap.set('v', '>', ">gv")
vim.keymap.set('v', '<', "<gv")

vim.keymap.set('i', "<C-k>", 'k')

vim.keymap.set('n', '<leader>;', ":Alpha<CR>")

vim.keymap.set('n', '<leader>ps', "<cmd>:so<CR>:PackerSync<CR>")
vim.keymap.set('n', '<leader>ms', "<cmd>:w<CR>:so<CR>")
vim.keymap.set('i', '<C-c>', '<Esc>')

-- vim.keymap.set('n', '<leader>c', '"+y<CR>')
-- vim.keymap.set('i', '<leader>c', '"+y<CR>')
-- vim.keymap.set('v', '<leader>c', '"+y<CR>')
-- vim.keymap.set('n', '<leader>v', '"+p<CR>')
-- vim.keymap.set('i', '<leader>v', '"+p<CR>')
-- vim.keymap.set('v', '<leader>v', '"+p<CR>')
