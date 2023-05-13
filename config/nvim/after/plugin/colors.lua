require('rose-pine').setup {
	-- 'auto' | 'main' | 'moon' | 'dawn'
	variant = 'auto',
	dark_variant = 'main',
	bol_vert_split = false
}

-- require('kanagawa').setup {
--
-- }
--

function ColorMyPencils(color)
	color = color or "rose-pine"
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
--
ColorMyPencils('vscode')
