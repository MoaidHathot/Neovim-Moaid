return {
	'ThePrimeagen/harpoon',
	-- event = "VeryLazy",
	keys = {
		{ mode = { 'n', 'v' },"<leader>a", function() require("harpoon.mark").add_file() end },
		{ mode = { 'n', 'v' },"<leader>h", function() require("harpoon.ui").toggle_quick_menu() end },
		{ mode = { 'n', 'v' },"<leader>1", function() require("harpoon.ui").nav_file(1) end },
		{ mode = { 'n', 'v' },"<leader>2", function() require("harpoon.ui").nav_file(2) end },
		{ mode = { 'n', 'v' },"<leader>3", function() require("harpoon.ui").nav_file(3) end },
		{ mode = { 'n', 'v' },"<leader>4", function() require("harpoon.ui").nav_file(4) end },
		{ mode = { 'n', 'v' },"<leader>5", function() require("harpoon.ui").nav_file(5) end },
		{ mode = { 'n', 'v' },"<leader>6", function() require("harpoon.ui").nav_file(6) end },
		{ mode = { 'n', 'v' },"<leader>7", function() require("harpoon.ui").nav_file(7) end },
		{ mode = { 'n', 'v' },"<leader>8", function() require("harpoon.ui").nav_file(8) end },
		{ mode = { 'n', 'v' },"<leader>9", function() require("harpoon.ui").nav_file(9) end },
		{ mode = { 'n', 'v' },"<leader>0", function() require("harpoon.ui").nav_file(10) end },
	},
	opts = {
		global_settings = {
			enter_on_sendcmd = true
		}
	}
}
