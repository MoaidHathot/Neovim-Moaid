return {
	'akinsho/toggleterm.nvim',
	-- event = "VeryLazy",
	cmd = "ToggleTerm",
	keys = {

		{ '<C-\\>',     '<cmd>:1ToggleTerm direction=float<CR>',              mode = { 'n', 'i', 't' } },
		{ '<M-F1>',      '<cmd>:2ToggleTerm direction=horizontal size=20<CR>', mode = { 'n', 't' } },
		{ '<M-F2>',      '<cmd>:3ToggleTerm direction=vertical size=100<CR>',  mode = { 'n', 't' } },
		{ '<M-F3>',      '<cmd>:4ToggleTerm direction=float<CR>',              mode = { 'n', 't' } },
		{ '<leader>gl', "",                                                   mode = { 'n', 't' } },
		{ '<leader>gl', function() end,                                       mode = { 'n', 't' } },
	},
	version = "*",
	config = function()
		require('toggleterm').setup({

			start_in_insert = true,
			terminal_mappings = true,
			-- direction = 'float',
			-- shell = "pwsh.exe -NoLogo -NoProfile",
			shell = "pwsh.exe -NoLogo",
			auto_scroll = true,
			-- persist_mode = true,
			persist_size = true,
			close_on_exit = true,
		})

		local Terminal = require('toggleterm.terminal').Terminal
		local lazygit = Terminal:new({ cmd = 'lazygit', hidden = true, direction = 'float' })

		function _lazygit_toggle()
			lazygit:toggle()
		end

		vim.keymap.set({ 'n', 't' }, '<leader>gl', function() _lazygit_toggle() end)
	end
}
