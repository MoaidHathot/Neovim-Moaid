-- require('rose-pine').setup {
-- 	-- 'auto' | 'main' | 'moon' | 'dawn'
-- 	variant = 'auto',
-- 	dark_variant = 'main',
-- 	bol_vert_split = false
-- }

-- require('kanagawa').setup {
--
-- }
--

function ColorMyPencils(color)
	color = color or "vscode"
	vim.cmd.colorscheme(color)
end

-- ColorMyPencils('rose-pine')
--
-- ColorMyPencils('kanagawa-wave')
-- ColorMyPencils('kanagawa-dragon')
-- ColorMyPencils('kanagawa-lotus')
--
-- ColorMyPencils('tokyonight-night')
-- ColorMyPencils('tokyonight-storm')
-- ColorMyPencils('tokyonight-moon')
-- ColorMyPencils('tokyonight-day')
--
--
-- ColorMyPencils('lunar')
--
-- ColorMyPencils('OneDarker')
--
-- ColorMyPencils('catppuccin')
-- ColorMyPencils('catppuccin-latte')
-- ColorMyPencils('catppuccin-frappe')
-- ColorMyPencils('catppuccin-macchiato')
-- ColorMyPencils('catppuccin-mocha')

-- ColorMyPencils('Everblush')

-- 'default' | 'neon' | 'auro'
vim.g.edge_style = 'neon'
-- vim.g.edge_style = 'default'
-- vim.g.edge_style = 'aura'
-- ColorMyPencils('edge')
--

require('onedark').setup {
	style = 'deep'
}

-- ColorMyPencils('vscode')
-- ColorMyPencils('edge')
ColorMyPencils('nightfox')

-- require('themery').setup({
-- 	themes = { 'vscode', 'rose-pine', 'rose-pine-dawn', 'rose-pine-main', 'rose-pine-moon', 'kanagawa-wave',
-- 		'kanagawa-dragon', 'kanagawa-lotus', 'tokyonight-night',
-- 		'tokyonight-storm', 'tokyonight-day', 'lunar', 'OneDarker', 'catppuccin', 'catppuccin-latte',
-- 		'catppuccin-frappe', 'catppuccin-macchiato', 'catppuccin-mocha', 'everblush', 'edge', 'ron', 'blue', 'delek',
-- 		'pablo', 'quiet', 'shine', 'slate', 'torte', 'murphy', 'desert', 'elflord', 'default', 'evening', 'habamax',
-- 		'morning', 'koehler', 'lunaperche', 'peachpuff', 'industry', 'zellner', 'darkblue',
-- 		'evening' }
-- })
