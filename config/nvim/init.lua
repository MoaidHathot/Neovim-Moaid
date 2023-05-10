if vim.g.vscode then
	-- vim.cmd [[
	-- " source $HOME/.config/nvim/vscode.vim
	-- ]]
	return
end

vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1

require("moaid")
