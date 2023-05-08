local neodev = require('neodev')

neodev.setup({
	library = {
		plugins = {
			'nvim-dap-ui'
		},
		types = true
	}
})
