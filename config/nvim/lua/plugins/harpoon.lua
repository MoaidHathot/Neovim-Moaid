return {
	'ThePrimeagen/harpoon',
	-- event = "VeryLazy",
	keys = {
		{ "<leader>a", function() require("harpoon.mark").add_file() end },
		{ "<leader>h", function() require("harpoon.ui").toggle_quick_menu() end },
		{ "<leader>1", function() require("harpoon.ui").nav_file(1) end },
		{ "<leader>2", function() require("harpoon.ui").nav_file(2) end },
		{ "<leader>3", function() require("harpoon.ui").nav_file(3) end },
		{ "<leader>4", function() require("harpoon.ui").nav_file(4) end },
		{ "<leader>5", function() require("harpoon.ui").nav_file(5) end },
		{ "<leader>6", function() require("harpoon.ui").nav_file(6) end },
		{ "<leader>7", function() require("harpoon.ui").nav_file(7) end },
	},
	opts = {
		global_settings = {
			enter_on_sendcmd = true
		}
	}
}
