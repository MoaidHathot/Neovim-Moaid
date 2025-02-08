return {
	{
		enabled = false,
		"utilyre/barbecue.nvim",
		event = "VeryLazy",
		name = "barbecue",
		version = "*",
		dependencies = {
			"SmiteshP/nvim-navic",
			"nvim-tree/nvim-web-devicons", -- optional dependency
		},
		opts = {
			-- configurations go here
		},
	},
	{
    'Bekaboo/dropbar.nvim',
    -- optional, but required for fuzzy finder support
    -- dependencies = {
    --   'nvim-telescope/telescope-fzf-native.nvim',
    --   build = 'make'
    -- },
    -- config = function()
    --   local dropbar_api = require('dropbar.api')
    --   -- vim.keymap.set('n', '<Leader>;', dropbar_api.pick, { desc = 'Pick symbols in winbar' })
    --   -- vim.keymap.set('n', '[;', dropbar_api.goto_context_start, { desc = 'Go to start of current context' })
    --   -- vim.keymap.set('n', '];', dropbar_api.select_next_context, { desc = 'Select next context' })
    -- end
  }
}
