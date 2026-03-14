return {
	{
		'MoaidHathot/dotnet.nvim',
		-- enabled = false,
		branch = 'dev',
		cmd = "DotnetUI",
		keys = {
			{ '<leader>/', mode = { 'n', 'v' } },
			{ '<leader>na', "<cmd>DotnetUI new_item<CR>", mode = { 'n', 'v' }, desc = '.NET new item', silent = true },
			{ '<leader>nb', "<cmd>DotnetUI file bootstrap<CR>", mode = { 'n', 'v' }, desc = '.NET bootstrap class', silent = true },
			{ '<leader>nra', "<cmd>DotnetUI project reference add<CR>", mode = { 'n', 'v' }, desc = '.NET add project reference', silent = true },
			{ '<leader>nrr', "<cmd>DotnetUI project reference remove<CR>", mode = { 'n', 'v' }, desc = '.NET remove project reference', silent = true },
			{ '<leader>npa', "<cmd>DotnetUI project package add<CR>", mode = { 'n', 'v' }, desc = '.NET add project package', silent = true },
			{ '<leader>npr', "<cmd>DotnetUI project package remove<CR>", mode = { 'n', 'v' }, desc = '.NET remove project package', silent = true },
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
