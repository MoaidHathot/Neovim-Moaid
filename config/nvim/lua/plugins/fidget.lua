return {
	"j-hui/fidget.nvim",
	enabled = false,
	event = "VeryLazy",
	config = function()
		require('fidget').setup({})
	end
}
