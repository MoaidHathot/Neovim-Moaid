return {
	"lukas-reineke/indent-blankline.nvim",
	event = "VeryLazy",
	main = 'ibl',
	config = function()
		require('ibl').setup({
			indent = {
				char = "▏"
			},
			exclude = {
				filetypes = {
					"help",
					"startify",
					"dashboard",
					"lazy",
					"neogitstatus",
					"NvimTree",
					"Trouble",
					"text",
				},
				buftypes = {
					"terminal",
					"nofile"
				}
			}
		})
	end
}
