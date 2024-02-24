return {
	'andymass/vim-matchup',
	config = function()
		local config = require('nvim-treesitter.configs')
		config.setup {
			matchup = {
				enabled = true,
			}
		}
	end
}
