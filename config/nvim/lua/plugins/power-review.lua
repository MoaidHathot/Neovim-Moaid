return {
	-- PowerReview.nvim - PR review inside Neovim
	-- All business logic (auth, provider, git) is handled by the `powerreview` CLI tool.
	-- CLI config lives at $XDG_CONFIG_HOME/PowerReview/config.json
	{
		dir = "P:\\Github\\PowerReview",
		name = "power-review.nvim",
		dependencies = {
			"MunifTanjim/nui.nvim",
			"nvim-neo-tree/neo-tree.nvim",
			"nvim-telescope/telescope.nvim",
		},
		cmd = "PowerReview",
		keys = {
			{ "<leader>pr", desc = "[PowerReview] Open/resume review" },
			{ "<leader>pl", desc = "[PowerReview] List sessions" },
			{ "<leader>pf", desc = "[PowerReview] Toggle files panel" },
			{ "<leader>pc", desc = "[PowerReview] Toggle comments panel" },
			{ "<leader>pa", desc = "[PowerReview] Add comment", mode = { "n", "v" } },
			{ "<leader>pe", desc = "[PowerReview] Edit draft" },
			{ "<leader>pA", desc = "[PowerReview] Approve draft" },
			{ "<leader>pS", desc = "[PowerReview] Submit pending" },
			{ "<leader>pv", desc = "[PowerReview] Set vote" },
			{ "<leader>pR", desc = "[PowerReview] Reply to thread" },
			{ "<leader>ps", desc = "[PowerReview] Sync remote threads" },
			{ "<leader>pQ", desc = "[PowerReview] Close review" },
			{ "<leader>pD", desc = "[PowerReview] Delete session" },
			{ "]r", desc = "[PowerReview] Next comment" },
			{ "[r", desc = "[PowerReview] Previous comment" },
		},
		config = function(_, opts)
			require("power-review").setup(opts)

			-- Inject statusline component into lualine (lualine_b section)
			local ok, lualine = pcall(require, "lualine")
			if ok then
				local sl = require("power-review.statusline")
				local lualine_cfg = lualine.get_config()
				-- Insert into lualine_b so it sits next to branch/diff
				table.insert(lualine_cfg.sections.lualine_b, sl.lualine())
				lualine.setup(lualine_cfg)
			end
		end,
		opts = {
			-- Run CLI from local nupkg source via dotnet dnx (no global install needed)
			cli = {
				executable = { "dnx", "--yes", "--add-source", "https://api.nuget.org/v3/index.json", "PowerReview", "--" },
			},

			ui = {
				files = {
					provider = "neo-tree",
				},
				diff = {
					provider = "native",
				},
			},
		},
	},
}
