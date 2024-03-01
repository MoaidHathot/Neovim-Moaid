return {
	"lukas-reineke/indent-blankline.nvim",
	event = "VeryLazy",
	main = 'ibl',
	opts = {
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
	}
}
