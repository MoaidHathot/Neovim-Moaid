local session = require('session_manager')
local config = require('session_manager.config')

session.setup {
	autoload_mode = config.AutoloadMode.CurrentDir
}

local config_group = vim.api.nvim_create_augroup('session_group', {}) -- A global group for all your config autocommands

vim.api.nvim_create_autocmd({ 'BufWritePost' }, {
	group = config_group,
	callback = function()
		if vim.bo.filetype ~= 'git'
			and not vim.bo.filetype ~= 'gitcommit'
			and not vim.bo.filetype ~= 'gitrebase'
		then
			session.autosave_session()
		end
	end
})
