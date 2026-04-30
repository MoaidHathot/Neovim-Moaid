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

vim.opt.undofile = true
vim.opt.undolevels = 30000

vim.opt.hlsearch = true
vim.opt.incsearch = true

vim.opt.termguicolors = true

vim.opt.scrolloff = 8
vim.opt.signcolumn = "yes"
vim.opt.isfname:append("@-@")

vim.opt.updatetime = 50

vim.g.mapleader = " "
vim.g.maplocalleader = "\\"

vim.opt.autowrite = true          -- Enable auto write
vim.opt.completeopt = "menu,menuone,noselect"
-- Sync with system clipboard
-- Since this operation is synchronous and can be relatively slow (specially on Windows), schedule it to make it asynchrounous
vim.schedule(function()
  vim.opt.clipboard = "unnamedplus"
end)
-- vim.opt.clipboard = "unnamedplus" -- Sync with system clipboard

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
-- vim.opt.laststatus = 0
vim.opt.laststatus = 3
vim.opt.list = true                -- Show some invisible characters (tabs...
vim.opt.mouse = "a"                -- Enable mouse mode
vim.opt.number = true              -- Print line number
vim.opt.formatoptions = "jqlnt"    -- tcqj
vim.opt.grepformat = "%f:%l:%c:%m"
vim.opt.grepprg = "rg --vimgrep"

--vim.g.markdown_recommended_style = 0

-- Folding (managed by nvim-ufo)
vim.opt.foldcolumn = "1"
vim.opt.foldlevel = 99
vim.opt.foldlevelstart = 99
vim.opt.foldenable = true

vim.opt.splitbelow = true            -- New horizontal splits open below
vim.opt.splitright = true            -- New vertical splits open to the right

vim.opt.winborder = 'rounded'

-- Is not supported in Windows Terminal. This is a new feature in 0.10.0 for preventing screen flippering
-- https://gist.github.com/christianparpart/d8a62cc1ab659194337d73e399004036
vim.opt.termsync = false

-- Use PowerShell for :terminal on Windows
if vim.fn.has("win32") == 1 then
	local pwsh = vim.fn.executable("pwsh") == 1 and "pwsh" or "powershell"
	vim.opt.shell = pwsh
	vim.opt.shellcmdflag = "-NoLogo -ExecutionPolicy RemoteSigned -Command"
	vim.opt.shellquote = ""
	vim.opt.shellxquote = ""
	vim.opt.shellredir = "2>&1 | %%{ \"$_\" } | Out-File %s; exit $LastExitCode"
	vim.opt.shellpipe = "2>&1 | %%{ \"$_\" } | Tee-Object %s; exit $LastExitCode"
end
