return {
	'rmagatti/goto-preview',
	-- event = "VeryLazy",	
	keys = {

		{ '<leader>pd', function() require("goto-preview").goto_preview_definition() end,      { desc = "Preview Definition", silent = true } },
		{ '<leader>pt', function() require("goto-preview").goto_preview_type_definition() end, { desc = "Preview Type Definition", silent = true } },
		{ '<leader>pi', function() require("goto-preview").goto_preview_type_definition() end, { desc = "Preview Implementation", silent = true } },
		{ '<leader>pr', function() require("goto-preview").goto_preview_references() end,      { desc = "Preview References", silent = true } },
		{ '<leader>pc', function() require("goto-preview").close_all_win() end,                { desc = "Close Previews", silent = true } },
	},
	config = function()
		require('goto-preview').setup()
	end
}
