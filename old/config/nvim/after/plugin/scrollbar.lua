local scrollbar = require('scrollbar')

-- local colors = require("tokyonight.colors")
scrollbar.setup {
	-- handle = {
	-- 	-- color = colors.bg_highlight,
	-- 	color = '#db4b4b'
	-- },
}

local search = require('scrollbar.handlers.search')
search.setup {
}

local git = require('scrollbar.handlers.gitsigns')
git.setup {
}
