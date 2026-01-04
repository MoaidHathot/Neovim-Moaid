return {
	{
		'MoaidHathot/dotnet.nvim',
		-- enabled = false,
		branch = 'dev',
		cmd = "DotnetUI",
		keys = {
			{ '<leader>/', mode = { 'n', 'v' } },
			{ mode = { 'n', 'v' },'<leader>na', "<cmd>:DotnetUI new_item<CR>", { desc = '.NET new item', silent = true} },
			{ mode = { 'n', 'v' },'<leader>nb', "<cmd>:DotnetUI file bootstrap<CR>", { desc = '.NET bootstrap class', silent = true} },
			{ mode = { 'n', 'v' },'<leader>nra', "<cmd>:DotnetUI project reference add<CR>", { desc = '.NET add project reference', silent = true} },
			{ mode = { 'n', 'v' },'<leader>nrr', "<cmd>:DotnetUI project reference remove<CR>", { desc = '.NET remove project reference', silent = true} },
			{ mode = { 'n', 'v' },'<leader>npa', "<cmd>:DotnetUI project package add<CR>", { desc = '.NET ada project package', silent = true} },
			{ mode = { 'n', 'v' },'<leader>npr', "<cmd>:DotnetUI project package remove<CR>", { desc = '.NET remove project package', silent = true} },
		},
		opts = {
			bootstrap = {
				auto_bootstrap = false,
			}
			-- project_selection = {
			-- 	path_display = 'filename_first',
			-- }
		},
	}
}
