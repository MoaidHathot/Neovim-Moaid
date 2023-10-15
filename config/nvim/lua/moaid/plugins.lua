return {
	{
		'nvim-treesitter/nvim-treesitter',
		build = { ':TSUpdate' },
		lazy = true
	},
	{ 'nvim-treesitter/playground',      lazy = false },
	{
		'VonHeikemen/lsp-zero.nvim',
		branch = 'v2.x',
		dependencies = {
			-- LSP Support
			{ 'neovim/nvim-lspconfig',            event = { "BufReadPre", "BufNewFile" }, lazy = true }, -- Required
			{
				-- Optional
				'williamboman/mason.nvim',
				build = function()
					pcall(vim.cmd, 'MasonUpdate')
				end,
			},
			{ 'williamboman/mason-lspconfig.nvim' }, -- Optional

			-- Autocompletion
			{ 'hrsh7th/nvim-cmp',                 lazy = true }, -- Required
			{ 'hrsh7th/cmp-nvim-lsp',             lazy = true }, -- Required
			{ 'L3MON4D3/LuaSnip',                 lazy = true } -- Required
		},
		lazy = false
	},
	{ 'jose-elias-alvarez/null-ls.nvim', lazy = true },
	{
		"jay-babu/mason-null-ls.nvim",
		event = { "BufReadPre", "BufNewFile" },
		dependencies = { "williamboman/mason.nvim", "jose-elias-alvarez/null-ls.nvim",
		},
	},
	-- { 'ErichDonGubler/lsp_lines.nvim',       lazy = true },
	{ 'https://git.sr.ht/~whynothugo/lsp_lines.nvim', lazy = true },
	{ 'kosayoda/nvim-lightbulb',                      lazy = true },
	--
	{ 'onsails/lspkind.nvim',                         lazy = true },
	{ 'hrsh7th/cmp-path',                             lazy = false },
	{ 'hrsh7th/cmp-buffer',                           lazy = false },
	{ 'hrsh7th/cmp-cmdline',                          lazy = false },
	{ 'hrsh7th/cmp-nvim-lua',                         lazy = false },
	{ 'saadparwaiz1/cmp_luasnip',                     lazy = false },
	{ 'Issafalcon/lsp-overloads.nvim',                lazy = true },
	{ 'neovim/nvim-lspconfig',                        lazy = true },
	{ "ray-x/lsp_signature.nvim",                     lazy = true },
	{ 'mfussenegger/nvim-dap',                        lazy = true },
	{ "rcarriga/nvim-dap-ui",                         dependencies = { "mfussenegger/nvim-dap" }, lazy = true },
	{ 'theHamsta/nvim-dap-virtual-text',              lazy = true },
	{ 'nvim-telescope/telescope-dap.nvim',            lazy = true },
	{
		'nvim-treesitter/nvim-treesitter-textobjects',
		dependencies = { 'nvim-treesitter/nvim-treesitter' },
		lazy = false,
	},
	{
		'akinsho/bufferline.nvim',
		dependencies = { 'nvim-tree/nvim-web-devicons' },
		version = "*",
		lazy = true
	},
	{
		"nvim-neotest/neotest",
		dependencies = {
			"nvim-lua/plenary.nvim",
			"nvim-treesitter/nvim-treesitter",
			"antoinemadec/FixCursorHold.nvim",
			"Issafalcon/neotest-dotnet",
			"nvim-neotest/neotest-python"
		},
		lazy = true
	},
	{ 'rmagatti/goto-preview',               lazy = false },
	{ 'aznhe21/actions-preview.nvim',        lazy = true },
	{ "folke/neodev.nvim",                   lazy = true },
	{ 'ThePrimeagen/harpoon',                lazy = true },
	{ 'mbbill/undotree',                     lazy = false },
	{ 'github/copilot.vim',                  lazy = false },
	{ 'tpope/vim-fugitive',                  lazy = false },
	{ 'tpope/vim-surround',                  lazy = false },
	{ 'tpope/vim-repeat',                    lazy = false },
	{ "Tastyep/structlog.nvim",              lazy = true },
	{ 'rcarriga/nvim-notify',                lazy = true },
	-- {
	-- 	'folke/noice.nvim',
	-- 	event = 'VeryLazy',
	-- 	dependencies = {
	-- 		'MunifTanjim/nui.nvim',
	-- 		"rcarriga/nvim-notify"
	-- 	}
	-- },
	{ 'RRethy/vim-illuminate',               lazy = false },
	{ "lukas-reineke/indent-blankline.nvim", main = 'ibl',                               Lazy = true },
	{ 'numToStr/Comment.nvim',               lazy = true },
	{ "windwp/nvim-autopairs",               lazy = true },
	{ 'karb94/neoscroll.nvim',               lazy = true },
	{ 'norcalli/nvim-colorizer.lua',         lazy = true },
	{ 'HiPhish/nvim-ts-rainbow2',            lazy = true },
	{ 'nvim-telescope/telescope.nvim',       dependencies = { 'nvim-lua/plenary.nvim' }, lazy = true },
	{ "Shatur/neovim-session-manager",       dependencies = { "nvim-lua/plenary.nvim" }, lazy = true },
	{
		"nvim-telescope/telescope-file-browser.nvim",
		dependencies = {
			"nvim-telescope/telescope.nvim",
			"nvim-lua/plenary.nvim"
		},
		lazy = true
	},
	{
		'nvim-telescope/telescope-project.nvim',
		dependencies = {
			'nvim-telescope/telescope.nvim',
			'nvim-telescope/telescope-file-browser.nvim'
		},
		lazy = true
	},
	-- { 'moll/vim-bbye',                           lazy = false },
	-- { 'nvim-telescope/telescope-fzf-native.nvim', build = 'make',                                   lazy = true },
	{ 'nvim-telescope/telescope-ui-select.nvim', lazy = true },
	{ 'stevearc/dressing.nvim',                  lazy = true },
	{ 'nvim-tree/nvim-tree.lua',                 dependencies = { 'nvim-tree/nvim-web-devicons' }, lazy = true },
	{ 'lewis6991/gitsigns.nvim',                 lazy = false },
	{ "folke/which-key.nvim",                    lazy = true },
	{
		'L3MON4D3/LuaSnip',
		dependencies = { 'rafamadriz/friendly-snippets' },
		lazy = false,
		build = 'make install_jsregexp',
	},
	{ "rafamadriz/friendly-snippets", lazy = true },
	{ "b0o/schemastore.nvim",         lazy = true },
	-- { 'dstein64/vim-startuptime',     lazy = false },
	{ "ellisonleao/glow.nvim",        lazy = true },
	{
		"folke/trouble.nvim",
		dependencies = {
			'nvim-telescope/telescope.nvim',
			"nvim-tree/nvim-web-devicons",
		},
		lazy = false
	},
	{ 'goolord/alpha-nvim',        dependencies = { 'nvim-tree/nvim-web-devicons' }, lazy = true },
	{ 'nvim-lualine/lualine.nvim', dependencies = { 'nvim-tree/nvim-web-devicons' }, lazy = true },
	{ "akinsho/toggleterm.nvim",   version = '*',                                    lazy = true },
	{ "folke/todo-comments.nvim",  dependencies = "nvim-lua/plenary.nvim",           lazy = true },
	{ 'phaazon/hop.nvim',          branch = 'v2',                                    lazy = true },
	-- { "ggandor/leap.nvim",         lazy = true },
	-- { 'folke/flash.nvim',            lazy = false },
	{
		"utilyre/barbecue.nvim",
		name = "barbecue",
		version = "*",
		dependencies = {
			"SmiteshP/nvim-navic",
			"nvim-tree/nvim-web-devicons", -- optional dependency
		},
		lazy = true
	},
	{
		'andymass/vim-matchup',
		init = function()
			vim.g.matchup_matchparen_offscreen = { method = "popup" }
		end,
		lazy = true
	},
	{ "petertriho/nvim-scrollbar",       lazy = true },
	{ 'kevinhwang91/nvim-hlslens',       lazy = true },
	{ 'chentoast/marks.nvim',            lazy = true },
	{ 'nathom/filetype.nvim',            lazy = false },
	{ 'stevearc/oil.nvim',               lazy = true },
	{ 'eandrju/cellular-automaton.nvim', lazy = false },
	{ 'ThePrimeagen/vim-be-good',        lazy = false },
	{ "sindrets/diffview.nvim",          lazy = false },
	{
		"iamcco/markdown-preview.nvim",
		lazy = false,
		build = function()
			vim.fn["mkdp#util#install"]()
		end
	},
	-- {
	-- 	"jackMort/ChatGPT.nvim",
	-- 	event = "VeryLazy",
	-- 	-- config = function()
	-- 	-- 	require("chatgpt").setup()
	-- 	-- end,
	-- 	dependencies = {
	-- 		"MunifTanjim/nui.nvim",
	-- 		"nvim-lua/plenary.nvim",
	-- 		"nvim-telescope/telescope.nvim"
	-- 	},
	-- 	lazy = true,
	-- },
	{ 'tzachar/highlight-undo.nvim',      lazy = false },
	-- { 'zaldih/themery.nvim',              lazy = true },
	--themes
	{ "catppuccin/nvim",                  lazy = false },
	{ 'rose-pine/neovim',                 lazy = false },
	{ 'LunarVim/lunar.nvim',              lazy = false },
	{ "lunarvim/Onedarker.nvim",          lazy = false },
	{ "navarasu/onedark.nvim",            lazy = false },
	{ "rebelot/kanagawa.nvim",            lazy = false },
	{ 'folke/tokyonight.nvim',            lazy = false },
	{ 'Everblush/nvim',                   name = 'everblush', lazy = false },
	{ 'sainnhe/edge',                     lazy = false },
	{ 'Mofiqul/vscode.nvim',              lazy = false },
	{ 'JoosepAlviste/palenightfall.nvim', lazy = false },
	{ 'stevedylandev/flexoki-nvim',       name = 'flexoki',   lazy = false },
	{ "EdenEast/nightfox.nvim",           priority = 1000,    lazy = false }
}
