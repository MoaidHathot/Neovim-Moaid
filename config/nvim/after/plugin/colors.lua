require('rose-pine').setup {
	-- 'auto' | 'main' | 'moon' | 'dawn'
	variant = 'auto',
	dark_variant = 'main',
	bol_vert_split = false
}


function ColorMyPencils(color)
	color = color or "rose-pine"
	-- color = color or 'rose-pine'
	vim.cmd.colorscheme(color)

end

ColorMyPencils()
