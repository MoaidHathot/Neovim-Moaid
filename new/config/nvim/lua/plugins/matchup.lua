return {
	'andymass/vim-matchup',
	event = "VeryLazy",
	config = function()
		local config = require('nvim-treesitter.configs')
		config.setup {
			matchup = {
				enabled = true,
			}
		}
	end
}
