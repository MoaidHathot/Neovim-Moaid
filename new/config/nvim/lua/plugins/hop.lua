return {
	'phaazon/hop.nvim',
	event = "VeryLazy",
	branch = 'v2', -- optional but strongly recommended
	-- lazy = false,
	config = function()
		-- you can configure Hop the way you like here; see :h hop-config
		require 'hop'.setup { keys = 'etovxqpdygfblzhckisuran' }

		vim.api.nvim_set_keymap("n", "s", ":HopChar2<cr>", { silent = true })
		vim.api.nvim_set_keymap("n", "S", ":HopWord<cr>", { silent = true })
		vim.keymap.set('', 'ls', ":HopLine<CR>", { desc = 'Hop Line', silent = true })
	end
}
