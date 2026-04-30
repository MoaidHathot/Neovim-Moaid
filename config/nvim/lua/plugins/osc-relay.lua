return {
	{
		"MoaidHathot/osc-relay.nvim",
		event = "VeryLazy",
		opts = {
			-- To also forward tab titles (e.g. opencode's emoji prefix shows
			-- in the WT tab text instead of just the progress bar color),
			-- change to: allow = { "0", "2", "9;4" }
			-- Default-off because it competes with nvim's own 'title' setting.
			allow = { "0", "2", "9;4" },
		},
	},
}
