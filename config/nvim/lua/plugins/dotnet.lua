return {
	{
		'MoaidHathot/dotnet.nvim',
		-- enabled = false,
		branch = 'dev',
		cmd = "DotnetUI",
		keys = {
			{ '<leader>/', mode = { 'n', 'v' } },
			{ '<leader>na', "<cmd>:DotnetUI new_item<CR>", { desc = '.NET new item', silent = true} },
			{ '<leader>nb', "<cmd>:DotnetUI file bootstrap<CR>", { desc = '.NET bootstrap class', silent = true} },
			{ '<leader>nra', "<cmd>:DotnetUI project reference add<CR>", { desc = '.NET add project reference', silent = true} },
			{ '<leader>nrr', "<cmd>:DotnetUI project reference remove<CR>", { desc = '.NET remove project reference', silent = true} },
			{ '<leader>npa', "<cmd>:DotnetUI project package add<CR>", { desc = '.NET ada project package', silent = true} },
			{ '<leader>npr', "<cmd>:DotnetUI project package remove<CR>", { desc = '.NET remove project package', silent = true} },
		},
		opts = {
			-- project_selection = {
			-- 	path_display = 'filename_first',
			-- }
		},
	}
}
