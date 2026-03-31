return {
	'rmagatti/goto-preview',
	-- event = "VeryLazy",	
	keys = {

		{ '<leader>Pd', function() require("goto-preview").goto_preview_definition() end, mode = { 'n', 'v' }, desc = "Preview Definition", silent = true },
		{ '<leader>Pt', function() require("goto-preview").goto_preview_type_definition() end, mode = { 'n', 'v' }, desc = "Preview Type Definition", silent = true },
		{ '<leader>Pi', function() require("goto-preview").goto_preview_type_implementation() end, mode = { 'n', 'v' }, desc = "Preview Implementation", silent = true },
		{ '<leader>Pr', function() require("goto-preview").goto_preview_references() end, mode = { 'n', 'v' }, desc = "Preview References", silent = true },
		{ '<leader>Ps', function() require("goto-preview").goto_preview_declaration() end, mode = { 'n', 'v' }, desc = "Preview Declaration", silent = true },
		{ '<leader>Pc', function() require("goto-preview").close_all_win() end, mode = { 'n', 'v' }, desc = "Close Previews", silent = true },
	},
	opts = {},
}
