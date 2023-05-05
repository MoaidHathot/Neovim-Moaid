local lualine = require('lualine')

lualine.setup {
	options = {
		theme = 'auto',
		icon_enabled = true,
		sections = {
			lualine_a = {
				'diagnostics',
				sources = {'nvim_diagnostic', 'nvim_lsp' },
				sections = {'error', 'warn', 'info', 'hint' },
			}
		}
	}
}
