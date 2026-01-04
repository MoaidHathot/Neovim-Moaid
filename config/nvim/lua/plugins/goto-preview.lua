return {
	'rmagatti/goto-preview',
	-- event = "VeryLazy",	
	keys = {

		{ mode = { 'n', 'v' },'<leader>pd', function() require("goto-preview").goto_preview_definition() end,      { desc = "Preview Definition", silent = true } },
		{ mode = { 'n', 'v' },'<leader>pt', function() require("goto-preview").goto_preview_type_definition() end, { desc = "Preview Type Definition", silent = true } },
		{ mode = { 'n', 'v' },'<leader>pi', function() require("goto-preview").goto_preview_type_implementation() end, { desc = "Preview Implementation", silent = true } },
		{ mode = { 'n', 'v' },'<leader>pr', function() require("goto-preview").goto_preview_references() end,      { desc = "Preview References", silent = true } },
		{ mode = { 'n', 'v' },'<leader>ps', function() require("goto-preview").goto_preview_declaration() end,      { desc = "Preview References", silent = true } },
		{ mode = { 'n', 'v' },'<leader>pc', function() require("goto-preview").close_all_win() end,                { desc = "Close Previews", silent = true } },
	},
	config = function()
		require('goto-preview').setup()
	end
}
