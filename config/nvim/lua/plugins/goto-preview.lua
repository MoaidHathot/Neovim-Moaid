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
		--
		-- 	vim.keymap.set('n', '<leader>pd', '<cmd>lua require("goto-preview").goto_preview_definition()<CR>',
		-- 		{ desc = "Preview Definition", silent = true })
		-- 	vim.keymap.set('n', '<leader>pt', '<cmd>lua require("goto-preview").goto_preview_type_definition()<CR>',
		-- 		{ desc = "Preview Type Definition", silent = true })
		-- 	vim.keymap.set('n', '<leader>pi', '<cmd>lua require("goto-preview").goto_preview_type_definition()<CR>',
		-- 		{ desc = "Preview Implementation", silent = true })
		-- 	vim.keymap.set('n', '<leader>pr', '<cmd>lua require("goto-preview").goto_preview_references()<CR>',
		-- 		{ desc = "Preview References", silent = true })
		-- 	vim.keymap.set('n', '<leader>pc', '<cmd>lua require("goto-preview").close_all_win()<CR>',
		-- 		{ desc = "Close Previews", silent = true })
	end
}
