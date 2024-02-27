local indent = require('ibl')

indent.setup({
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

-- indent.setup({
-- 	show_trailing_blankline_indent = false,
-- 	show_current_context = true,
-- 	show_first_indent_level = true,
-- 	buftype_exclude = { "terminal", "nofile" },
-- 	filetype_exclude = {
-- 		"help",
-- 		"startify",
-- 		"dashboard",
-- 		"lazy",
-- 		"neogitstatus",
-- 		"NvimTree",
-- 		"Trouble",
-- 		"text",
-- 	},
-- 	char = "▏",
-- 	context_char = "▏",
--
-- })
