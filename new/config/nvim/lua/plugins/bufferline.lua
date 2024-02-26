return
{
	'akinsho/bufferline.nvim',
	event = "VeryLazy",
	version = "*",
	dependencies = {
		'nvim-tree/nvim-web-devicons'
	},
	-- lazy = false,
	config = function()
		local bufferline = require('bufferline')

		bufferline.setup {
			options = {
				numbers = "none",
				indicator = {
					icon = '▎',
					style = 'icon'
				},
				offsets = {
					{
						filetype = "NvimTree",
						text = "File Explorer",
						separator = true
					}
				},
				separator_style = "think",
				hover = {
					enabled = true,
					delay = 200,
					reveal = { 'close' }
				},
				diagnostics = "nvim_lsp",
				diagnostics_indicator = function(count, level, diagnostics_dict, context)
					-- return "("..count..")"
					local icon = level:match("error") and " " or " "
					return " " .. icon .. count
				end,
			}
		}
	end

}
