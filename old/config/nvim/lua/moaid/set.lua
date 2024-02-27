--vim.opt.guicursor = ""

vim.opt.nu = true
vim.opt.relativenumber = true
vim.opt.ignorecase = true
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
-- vim.opt.undodir = os.getenv("appdata") .. "../Local/nvim-data/undodir"
vim.opt.undofile = true
vim.opt.undolevels = 30000

vim.opt.hlsearch = true
vim.opt.incsearch = true

vim.opt.termguicolors = true


vim.opt.scrolloff = 8
vim.opt.signcolumn = "yes"
vim.opt.isfname:append("@-@")

vim.opt.updatetime = 50

-- vim.opt.colorcolumn = "140"

vim.g.mapleader = " "
vim.g.maplocalleader = "\\"

vim.opt.autowrite = true          -- Enable auto write
vim.opt.completeopt = "menu,menuone,noselect"
vim.opt.clipboard = "unnamedplus" -- Sync with system clipboard

vim.opt.confirm = true            -- Confirm to save changes before exiting modified buffer
vim.opt.cursorline = true         -- Enable highlighting of the current line


vim.opt.wildmode = "longest:full,full" -- Command-line completion mode
vim.opt.spelllang = { "en" }
vim.opt.showmode = false
vim.opt.shortmess:append({ W = true, I = true, c = true })
vim.opt.sessionoptions = { "buffers", "curdir", "tabpages", "winsize" }
vim.opt.pumblend = 10              -- Popup blend
vim.opt.pumheight = 10             -- Maximum number of entries in a popup
vim.opt.inccommand = "nosplit"     -- preview incremental substitute
vim.opt.laststatus = 0
vim.opt.list = true                -- Show some invisible characters (tabs...
vim.opt.mouse = "a"                -- Enable mouse mode
vim.opt.number = true              -- Print line number
vim.opt.formatoptions = "jcroqlnt" -- tcqj
vim.opt.grepformat = "%f:%l:%c:%m"
vim.opt.grepprg = "rg --vimgrep"

vim.g.markdown_recommended_style = 0

-- vim.api.nvim_exec2('set formatoptions-=cro', {})
-- vim.opt_global.formatoptions:remove { 'c', 'r', 'o' }


-- vim.g.OmniSharp_highlighting = 0

-- vim.opt.ignorecase = true
-- This is test

vim.opt.formatoptions:remove { 'c', 'r', 'o' }

-- vim.opt.foldmethod = "expr"
-- vim.opt.foldexpr = "nvim_treesitter#foldexpr()"

-- vim.api.nvim_create_autocmd({ "BufReadPost,FileReadPost" }, { pattern = { "*" }, command = "normal zR", })

-- function to create a list of commands and convert them to autocommands
-------- This function is taken from https://github.com/norcalli/nvim_utils
-- local function nvim_create_augroups(definitions)
-- 	for group_name, definition in pairs(definitions) do
-- 		vim.api.nvim_command('augroup ' .. group_name)
-- 		vim.api.nvim_command('autocmd!')
-- 		for _, def in ipairs(definition) do
-- 			local command = table.concat(vim.tbl_flatten { 'autocmd', def }, ' ')
-- 			vim.api.nvim_command(command)
-- 		end
-- 		vim.api.nvim_command('augroup END')
-- 	end
-- end
--
-- local autoCommands = {
-- 	-- other autocommands
-- 	open_folds = {
-- 		{ "BufReadPost,FileReadPost", "*", "normal zR" }
-- 	}
-- }

-- nvim_create_augroups(autoCommands)

-- vim.opt.shell = powershell.exe
