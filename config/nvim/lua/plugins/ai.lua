return {
	{
		"yetone/avante.nvim",
		-- event = "VeryLazy",
		enabled = false,
		version = false, -- Never set this value to "*"! Never!
		keys = {
			{ "<leader>aa", "<cmd>AvanteToggle<cr>", mode = { 'n', 'v' }, desc = "Avante" },
			{ "<leader>at", "<cmd>AvanteToggle<cr>", mode = { 'n', 'v' }, desc = "Avante" },
			{ "<leader>af", "<cmd>AvanteFocus<cr>",  mode = { 'n', 'v' }, desc = "Avante" },
		},
		opts = {
			provider = "openai",
			openai = {
				endpoint = "https://api.openai.com/v1",
				model = "gpt-4o", -- your desired model (or use gpt-4o, etc.)
				timeout = 30000, -- Timeout in milliseconds, increase this for reasoning models
				temperature = 0,
				max_completion_tokens = 8192, -- Increase this to include reasoning tokens (for reasoning models)
				--reasoning_effort = "medium", -- low|medium|high, only used for reasoning models
			},
		},
		-- if you want to build from source then do `make BUILD_FROM_SOURCE=true`
		-- build = "make",
		build = "powershell -ExecutionPolicy Bypass -File Build.ps1 -BuildFromSource false", -- for windows
		dependencies = {
			"nvim-treesitter/nvim-treesitter",
			"stevearc/dressing.nvim",
			"nvim-lua/plenary.nvim",
			"MunifTanjim/nui.nvim",
			--- The below dependencies are optional,
			-- "echasnovski/mini.pick", -- for file_selector provider mini.pick
			"nvim-telescope/telescope.nvim", -- for file_selector provider telescope
			"hrsh7th/nvim-cmp",    -- autocompletion for avante commands and mentions
			-- "ibhagwan/fzf-lua", -- for file_selector provider fzf
			"nvim-tree/nvim-web-devicons", -- or echasnovski/mini.icons
			-- "zbirenbaum/copilot.lua", -- for providers='copilot'
			{
				-- support for image pasting
				"HakonHarnes/img-clip.nvim",
				event = "VeryLazy",
				opts = {
					-- recommended settings
					default = {
						embed_image_as_base64 = false,
						prompt_for_file_name = false,
						drag_and_drop = {
							insert_mode = true,
						},
						-- required for Windows users
						use_absolute_path = true,
					},
				},
			},
			{
				-- Make sure to set this up properly if you have lazy=true
				'MeanderingProgrammer/render-markdown.nvim',
				enabled = false,
				opts = {
					file_types = { "markdown", "Avante" },
				},
				ft = { "markdown", "Avante" },
				-- cmd= { "RenderMarkdown", "RenderAvante" },
			},
		},
	},
	{
		"folke/sidekick.nvim",
		opts = {
			-- add any options here
			cli = {
				mux = {
					backend = "zellij",
					enabled = false,
				},
			},
		},
		-- stylua: ignore
		keys = {
			{
				"<tab>",
				function()
					-- if there is a next edit, jump to it, otherwise apply it if any
					if not require("sidekick").nes_jump_or_apply() then
						return "<Tab>" -- fallback to normal tab
					end
				end,
				expr = true,
				desc = "Goto/Apply Next Edit Suggestion",
			},
			{
				"<leader>aa",
				function() require("sidekick.cli").toggle({ name = "copilot" }) end,
				-- function() require("sidekick.cli").show({ name = "copilot" }) end,
				mode = { "n", "v" },
				desc = "Sidekick Toggle CLI (Copilot)",
			},
			{
				"<leader>as",
				function() require("sidekick.cli").select() end,
				-- Or to select only installed tools:
				-- require("sidekick.cli").select({ filter = { installed = true } })
				desc = "Sidekick Select CLI",
			},
			{
				"<leader>at",
				function() require("sidekick.cli").send({ msg = "{this}" }) end,
				mode = { "x", "n" },
				desc = "Send This",
			},
			{
				"<leader>av",
				function() require("sidekick.cli").send({ msg = "{selection}" }) end,
				mode = { "x" },
				desc = "Send Visual Selection",
			},
			{
				"<leader>as",
				function() require("sidekick.cli").send({ selection = true }) end,
				mode = { "v" },
				desc = "Sidekick Send Visual Selection",
			},
			{
				"<leader>ap",
				function() require("sidekick.cli").prompt() end,
				mode = { "n", "v" },
				desc = "Sidekick Select Prompt",
			},
		},
	}
}
