--vim.opt.guicursor = ""

vim.opt.nu = true
vim.opt.relativenumber = true
vim.opt.smartcase = true
vim.opt.tabstop = 4
vim.opt.softtabstop = 4
vim.opt.shiftwidth = 4
vim.opt.expandtab = false

vim.opt.smartindent = true
vim.opt.wrap = false

vim.opt.swapfile = false
vim.opt.backup = false
--vim.opt.undodir = os.getenv("HOME") .. "/.vim/undodir"
vim.opt.undofile = true

vim.opt.hlsearch = true
vim.opt.incsearch = true

vim.opt.termguicolors = true


vim.opt.scrolloff = 8
vim.opt.signcolumn = "yes"
vim.opt.isfname:append("@-@")

vim.opt.updatetime = 50


-- vim.opt.colorcolumn = "140"

vim.g.mapleader = " "

-- vim.api.nvim_exec2('set formatoptions-=cro', {})
-- vim.opt_global.formatoptions:remove { 'c', 'r', 'o' }


-- vim.g.OmniSharp_highlighting = 0

-- vim.opt.ignorecase = true
-- This is test

vim.opt.formatoptions:remove { 'c', 'r', 'o' }
