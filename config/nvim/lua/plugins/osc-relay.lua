return {
	{
		"MoaidHathot/osc-relay.nvim",
		event = "VeryLazy",
		opts = {
			-- Progress bar only. OSC 0/2 (titles) compete with nvim's own
			-- 'title' management — nvim re-emits its title on focus changes,
			-- overwriting any title we forward. State is fully encoded in
			-- the progress bar instead (color + fill differentiate states).
			--
			-- If you want to opt in anyway, do BOTH of:
			--   1. allow = { "0", "2", "9;4" }
			--   2. vim.opt.title = false   (in your options.lua, so nvim
			--                               stops fighting our forwarded title)
			allow = { "9;4" },
		},
	},
}
