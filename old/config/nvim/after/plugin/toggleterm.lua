local toggleterm = require("toggleterm")

toggleterm.setup {
	-- open_mapping = [[<c-\>]],
	start_in_insert = true,
	terminal_mappings = true,
	-- direction = 'float',
	shell = "pwsh.exe -NoLogo -NoProfile",
	auto_scroll = true,
	-- persist_mode = true,
	persist_size = true,
	close_on_exit = true,
}

-- function _G.set_terminal_keymaps()
-- 	local opts = { buffer = 0 }
-- 	vim.keymap.set('t', '<esc>', [[<C-\><C-n>]], opts)
-- end

-- vim.cmd('autocmd! TermOpen term://* lua set_terminal_keymaps()')
-- vim.cmd('autocmd! TermOpen term://* ')
-- vim.cmd('autocmd! term://* <Esc>')



local terminal1 = require('toggleterm.terminal').Terminal

terminal1:new {
	open_mapping = [[<M-1>]],
	-- start_in_insert = true,
	-- terminal_mappings = true,
	direction = 'float',
	shell = "pwsh.exe -NoLogo",
	auto_scroll = true,
}

local function _toggleTerminal1()
	terminal1:toggle()
end

local terminal2 = require('toggleterm.terminal').Terminal

terminal2:new {
	cmd = "lazygit",
	direction = "top",
	float_opts = {
		border = "double"
	},
	hiddern = true
}

local function _lazygitToggle()
	terminal2:toggle()
end

local Terminal = require('toggleterm.terminal').Terminal
local lazygit = Terminal:new({ cmd = 'lazygit', hidden = true, direction = 'float' })

local function _lazygit_toggle()
	lazygit:toggle()
end

vim.keymap.set({ 'n', 'i', 't' }, '<C-\\>', '<cmd>:1ToggleTerm direction=float<CR>')
vim.keymap.set({ 'n', 't' }, '<M-1>', '<cmd>:2ToggleTerm direction=horizontal size=20<CR>')
vim.keymap.set({ 'n', 't' }, '<M-2>', '<cmd>:3ToggleTerm direction=vertical size=100<CR>')
vim.keymap.set({ 'n', 't' }, '<M-3>', '<cmd>:4ToggleTerm direction=float<CR>')
-- vim.keymap.set({ 'n', 't' }, '<leader>gl', "<cmd>:5TermExec cmd='lazygit' direction=float<CR>")
vim.keymap.set({ 'n', 't' }, '<leader>gl', "<cmd>lua _lazygit_toggle()<CR>")

-- vim.keymap.set('n', "<M-1>", '<cmd>lua _toggleTerminal1()<CR><Esc>')
-- vim.keymap.set('n', "<M-2>", '<cmd>lua _lazygitToggle()<CR>')

-- vim.api.nvim_set_keymap("n", "<M-1>", "<cmd>lua _toggleTerminal1()<CR>:<C-\\><C-n>", {})
