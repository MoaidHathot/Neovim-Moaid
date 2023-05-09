local which = require('which-key')

vim.o.timeout = true
vim.o.timeoutlen = 200

which.setup {

}

which.register({
	s = {
		name = "Search"
	},
	l = {
		name = "LSP",
	},
	d = {
		name = "Debugging",
		s = "Start/Continue",
		t = 'Toggle Breakpoint',
		u = 'Toggle UI',
		i = 'Step Into',
		o = 'Step Over',
		['<F10>'] = 'Step Over',
		['<F5>'] = "Star/Continue",
		['<F11>'] = 'Step Into',
	},
	h = "Harpoon Togle",
	a = "Harpoon Add",
	['1'] = "Harpoon #1",
	['2'] = "Harpoon #2",
	['3'] = "Harpoon #3",
	e = "File Explorer",
	t = {
		name = "File Explore",
		f = "Track File",
		c = "Collapse"
	},
	c = "Close Buffers",
	q = "Quit",
	b = {
		name = "Buffers",
		b = "Previous Buffer",
		n = "Next Buffer",
		d = "Delete Buffer"
	},
	p = {
		name = "Packer",
		s = "Sync"
	},
	m = {
		name = "Markdown",
		g = "Glow Show",
		s = "Shout Out"
	},
	['<F5>'] = "Toggle History"
}, { prefix = "<leader>" })
