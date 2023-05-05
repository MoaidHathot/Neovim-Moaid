local toggleterm = require("toggleterm")

toggleterm.setup {
	open_mapping = [[<c-\>]],
	start_in_insert = true,
	terminal_mappings = true,
	direction = 'float',
	shell = "pwsh.exe -NoLogo",
	auto_scroll = true,
	persist_mode = true,
	persist_size = true,
	close_on_exit = true,
}

function _G.set_terminal_keymaps()
	local opts = {buffer =0}
	vim.keymap.set('t', '<esc>', [[<C-\><C-n>]], opts)
end

vim.cmd('autocmd! TermOpen term://* lua set_terminal_keymaps()')
-- vim.cmd('autocmd! term://* <Esc>')



local terminal1 = require('toggleterm.terminal').Terminal

terminal1:new {
	open_mapping = [[<M-1>]],
	start_in_insert = true,
	terminal_mappings = true,
	direction = 'vertical',
	shell = "pwsh.exe -NoLogo",
	auto_scroll = true,
}

function _toggleTerminal1()
	terminal1:toggle()
end

vim.keymap.set('n', "<M-1>", '<cmd>lua _toggleTerminal1()<CR><Esc>')

-- vim.api.nvim_set_keymap("n", "<M-1>", "<cmd>lua _toggleTerminal1()<CR>:<C-\\><C-n>", {noremap = true, silent = true})
