return {
	'rmagatti/goto-preview',
	-- event = "VeryLazy",	
	keys = {

		{ '<leader>pd', function() require("goto-preview").goto_preview_definition() end, mode = { 'n', 'v' }, desc = "Preview Definition", silent = true },
		{ '<leader>pt', function() require("goto-preview").goto_preview_type_definition() end, mode = { 'n', 'v' }, desc = "Preview Type Definition", silent = true },
		{ '<leader>pi', function() require("goto-preview").goto_preview_type_implementation() end, mode = { 'n', 'v' }, desc = "Preview Implementation", silent = true },
		{ '<leader>pr', function() require("goto-preview").goto_preview_references() end, mode = { 'n', 'v' }, desc = "Preview References", silent = true },
		{ '<leader>ps', function() require("goto-preview").goto_preview_declaration() end, mode = { 'n', 'v' }, desc = "Preview Declaration", silent = true },
		{ '<leader>pc', function() require("goto-preview").close_all_win() end, mode = { 'n', 'v' }, desc = "Close Previews", silent = true },
	},
	opts = {},
}
