local alpha = require('alpha')
local dashboard = require('alpha.themes.dashboard')


local name = {
	[[ /$$      /$$                     /$$       /$$       /$$   /$$             /$$     /$$                   /$$    ]],
	[[| $$$    /$$$                    |__/      | $$      | $$  | $$            | $$    | $$                  | $$    ]],
	[[| $$$$  /$$$$  /$$$$$$   /$$$$$$  /$$  /$$$$$$$      | $$  | $$  /$$$$$$  /$$$$$$  | $$$$$$$   /$$$$$$  /$$$$$$  ]],
	[[| $$ $$/$$ $$ /$$__  $$ |____  $$| $$ /$$__  $$      | $$$$$$$$ |____  $$|_  $$_/  | $$__  $$ /$$__  $$|_  $$_/  ]],
	[[| $$  $$$| $$| $$  \ $$  /$$$$$$$| $$| $$  | $$      | $$__  $$  /$$$$$$$  | $$    | $$  \ $$| $$  \ $$  | $$    ]],
	[[| $$\  $ | $$| $$  | $$ /$$__  $$| $$| $$  | $$      | $$  | $$ /$$__  $$  | $$ /$$| $$  | $$| $$  | $$  | $$ /$$]],
	[[| $$ \/  | $$|  $$$$$$/|  $$$$$$$| $$|  $$$$$$$      | $$  | $$|  $$$$$$$  |  $$$$/| $$  | $$|  $$$$$$/  |  $$$$/]],
	[[|__/     |__/ \______/  \_______/|__/ \_______/      |__/  |__/ \_______/   \___/  |__/  |__/ \______/    \___/  ]],
}

dashboard.section.header.val = name

dashboard.section.buttons.val = {
	dashboard.button('n', "  New file", ":ene <BAR> startinsert <CR>"),
	dashboard.button('f', " Find file"),
	dashboard.button('r', " Recently opened files"),
	dashboard.button('p', " Recently opened projects"),
	dashboard.button('p', " Find text"),
	-- dashboard.button('p', "ﴬ"),
	-- dashboard.button('p', ""),
	-- dashboard.button('p', ""),
	dashboard.button('q', " Quit", ":qa<CR>")
}

dashboard.section.footer.val = " Moaid Hathot"

alpha.setup(dashboard.config)
