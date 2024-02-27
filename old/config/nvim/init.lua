vim.loader.enable()
-- if vim.g.vscode then
-- 	vim.cmd [[
-- 	" source $HOME/.config/nvim/vscode.vim
-- 	source vscode.vim
-- ]]
-- else
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1
require("moaid")

-- if vim.cmd([[!git rev-parse --is-inside-work-tree > nul]]) then
-- 	-- print('inside git repo')
-- 	local a = true
-- else
-- 	-- print('not git repo')
-- 	local b = false
-- end

-- end
