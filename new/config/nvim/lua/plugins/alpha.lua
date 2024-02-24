local name = {

	[[]],
	[[]],
	[[]],
	[[]],
	[[ /$$      /$$                     /$$       /$$       /$$   /$$             /$$     /$$                   /$$    ]],
	[[| $$$    /$$$                    |__/      | $$      | $$  | $$            | $$    | $$                  | $$    ]],
	[[| $$$$  /$$$$  /$$$$$$   /$$$$$$  /$$  /$$$$$$$      | $$  | $$  /$$$$$$  /$$$$$$  | $$$$$$$   /$$$$$$  /$$$$$$  ]],
	[[| $$ $$/$$ $$ /$$__  $$ |____  $$| $$ /$$__  $$      | $$$$$$$$ |____  $$|_  $$_/  | $$__  $$ /$$__  $$|_  $$_/  ]],
	[[| $$  $$$| $$| $$  \ $$  /$$$$$$$| $$| $$  | $$      | $$__  $$  /$$$$$$$  | $$    | $$  \ $$| $$  \ $$  | $$    ]],
	[[| $$\  $ | $$| $$  | $$ /$$__  $$| $$| $$  | $$      | $$  | $$ /$$__  $$  | $$ /$$| $$  | $$| $$  | $$  | $$ /$$]],
	[[| $$ \/  | $$|  $$$$$$/|  $$$$$$$| $$|  $$$$$$$      | $$  | $$|  $$$$$$$  |  $$$$/| $$  | $$|  $$$$$$/  |  $$$$/]],
	[[|__/     |__/ \______/  \_______/|__/ \_______/      |__/  |__/ \_______/   \___/  |__/  |__/ \______/    \___/  ]],
	[[]],
	[[]],
	[[]],
	[[]],
	[[]],
	[[]],
	[[]],


}

return {
	'goolord/alpha-nvim',
	lazy = false,
	dependencies = { 'nvim-tree/nvim-web-devicons' },
	config = function()
		local alpha = require('alpha')
		local dashboard = require('alpha.themes.startify')

		--dashboard.section.header.val = name

		--dashboard.section.buttons.val = {
		--	dashboard.button('n', "  New file", ":ene <BAR> startinsert <CR>"),
		--	dashboard.button('f', " Find file", "<leader>sf"),
		--	dashboard.button('r', " Recently opened files", "<leader>so"),
		--	dashboard.button('p', " Recently opened projects", "<leader>sP"),
		--	dashboard.button('t', " Find text", "<leader>sg"),
		--	-- dashboard.button('p', "ﴬ"),
		--	-- dashboard.button('p', ""),
		--	-- dashboard.button('p', ""),
		--	dashboard.button('q', " Quit", ":qa<CR>")
		--}

		dashboard.section.header.val = name
		--dashboard.section.footer.val = " Moaid Hathot"

		alpha.setup(dashboard.opts)

		vim.keymap.set('n', '<leader>;', ":Alpha<CR>", { desc = "Toggle Alpha", silent = true })
	end
}
