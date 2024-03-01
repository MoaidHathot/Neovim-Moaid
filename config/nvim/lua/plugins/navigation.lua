return {
	{
		'phaazon/hop.nvim',
		-- event = "VeryLazy",
		branch = 'v2', -- optional but strongly recommended
		enabled = false,
		-- lazy = false,
		keys = {
			{ "s",  ":HopChar2<cr>", "Hop Char2" },
			{ "S",  ":HopWord<cr>",  "Hop Char2" },
			{ "ls", ":HopLine<cr>",  "Hop Line" },
		},
		opts = {
			keys = 'etovxqpdygfblzhckisuran'
		}
		-- config = function()
		-- you can configure Hop the way you like here; see :h hop-config
		-- require 'hop'.setup { keys = 'etovxqpdygfblzhckisuran' }

		-- vim.api.nvim_set_keymap("n", "s", ":HopChar2<cr>", { silent = true })
		-- vim.api.nvim_set_keymap("n", "S", ":HopWord<cr>", { silent = true })
		-- vim.keymap.set('', 'ls', ":HopLine<CR>", { desc = 'Hop Line', silent = true })
		-- end
	},
	{
		"folke/flash.nvim",
		-- event = "VeryLazy",
		---@type Flash.Config
		opts = {
			modes = {
				char = {
					enabled = false,
				}
			}
		},
		-- stylua: ignore
		keys = {
			{ "s", mode = { "n", "x", "o" }, function() require("flash").jump() end, desc = "Flash" },
			-- { "S", mode = { "n", "x", "o" }, function() require("flash").Treesitter() end, desc = "Flash Treesitter" },
		},
	}
}
