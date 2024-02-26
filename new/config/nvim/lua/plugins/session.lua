return {
	{
		-- 'Shatur/neovim-session-manager',
		-- lazy = false,
		-- dependencies = {
		-- 	'nvim-lua/plenary.nvim'
		-- },
		-- config = function()
		--
		-- 	local session = require('session_manager')
		-- 	local config = require('session_manager.config')
		--
		-- 	session.setup {
		-- 		autoload_mode = config.AutoloadMode.CurrentDir
		-- 	}
		--
		-- 	local config_group = vim.api.nvim_create_augroup('session_group', {}) -- A global group for all your config autocommands
		--
		-- 	vim.api.nvim_create_autocmd({ 'BufWritePost' }, {
		-- 		group = config_group,
		-- 		callback = function()
		-- 			if vim.bo.filetype ~= 'git'
		-- 				and not vim.bo.filetype ~= 'gitcommit'
		-- 				and not vim.bo.filetype ~= 'gitrebase'
		-- 			then
		-- 				session.autosave_session()
		-- 			end
		-- 		end
		-- 	})
		-- end
	},
	{
		'rmagatti/auto-session',
		-- event = "LazyDone",
		config = function()
			require('auto-session').setup({
				log_level = 'error',
				auto_restore_enabled = true
			})
			vim.keymap.set('n', '<leader>ss', require("auto-session.session-lens").search_session, { desc = "Search Session" })
		end
	}
}
