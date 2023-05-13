return {

	{ 'nvim-treesitter/nvim-treesitter', build = { ':TSUpdate' }, lazy = true },
	{
		'VonHeikemen/lsp-zero.nvim',
		branch = 'v2.x',
		dependencies = {
			-- LSP Support
			{ 'neovim/nvim-lspconfig',            lazy = true }, -- Required
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
		dependencies = {
			"williamboman/mason.nvim",
			"jose-elias-alvarez/null-ls.nvim",
		},
	},
	-- { 'ErichDonGubler/lsp_lines.nvim',       lazy = true },
	{ 'https://git.sr.ht/~whynothugo/lsp_lines.nvim', lazy = true },
	--
	{ 'onsails/lspkind.nvim',                         lazy = true },
	{ 'hrsh7th/cmp-path',                             lazy = false },
	{ 'hrsh7th/cmp-buffer',                           lazy = false },
	{ 'hrsh7th/cmp-cmdline',                          lazy = false },
	{ 'hrsh7th/cmp-nvim-lua',                         lazy = true },
	{ 'saadparwaiz1/cmp_luasnip',                     lazy = true },
	{ 'Issafalcon/lsp-overloads.nvim',                lazy = true },
	{ 'neovim/nvim-lspconfig',                        lazy = true },
	{ "ray-x/lsp_signature.nvim",                     lazy = true },
	{ 'mfussenegger/nvim-dap',                        lazy = true },
	{ "rcarriga/nvim-dap-ui",                         dependencies = { "mfussenegger/nvim-dap" }, lazy = true },
	{
		'akinsho/bufferline.nvim',
		dependencies = { 'nvim-tree/nvim-web-devicons' },
		version = "*",
		lazy = true
	},
	{ "folke/neodev.nvim",                   lazy = true },
	'ThePrimeagen/harpoon',
	{ 'mbbill/undotree',                     lazy = true },
	{ 'tpope/vim-fugitive',                  lazy = true },
	{ 'github/copilot.vim',                  lazy = false },
	{ 'tpope/vim-surround',                  lazy = true },
	{ 'tpope/vim-repeat',                    lazy = true },
	{ "Tastyep/structlog.nvim",              lazy = true },
	{ 'rcarriga/nvim-notify',                lazy = true },
	{ 'RRethy/vim-illuminate',               lazy = true },
	{ "lukas-reineke/indent-blankline.nvim", lazy = true },
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
	{ 'nvim-telescope/telescope-ui-select.nvim', lazy = true },
	{ 'nvim-tree/nvim-tree.lua',                 dependencies = { 'nvim-tree/nvim-web-devicons' }, lazy = true },
	{ 'lewis6991/gitsigns.nvim',                 lazy = true },
	{ "folke/which-key.nvim",                    lazy = true },
	{ 'L3MON4D3/LuaSnip',                        lazy = true },
	{ "rafamadriz/friendly-snippets",            lazy = true },
	{ "b0o/schemastore.nvim",                    lazy = true },
	{ 'dstein64/vim-startuptime',                lazy = false },
	{ "ellisonleao/glow.nvim",                   lazy = true },
	{
		"folke/trouble.nvim",
		dependencies = {
			'nvim-telescope/telescope.nvim',
			"nvim-tree/nvim-web-devicons",
		},
		lazy = true
	},
	{ 'goolord/alpha-nvim',        dependencies = { 'nvim-tree/nvim-web-devicons' }, lazy = true },
	{ 'nvim-lualine/lualine.nvim', dependencies = { 'nvim-tree/nvim-web-devicons' }, lazy = true },
	{ "akinsho/toggleterm.nvim",   version = '*',                                    lazy = true },
	{ "folke/todo-comments.nvim",  dependencies = "nvim-lua/plenary.nvim",           lazy = true },
	{ 'phaazon/hop.nvim',          branch = 'v2',                                    lazy = true },
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
	{ "petertriho/nvim-scrollbar", lazy = true },
	{ 'kevinhwang91/nvim-hlslens', lazy = true },
	{ 'chentoast/marks.nvim',      lazy = true },
	--themes
	{ "catppuccin/nvim",           lazy = false },
	{ 'rose-pine/neovim',          lazy = false },
	{ 'LunarVim/lunar.nvim',       lazy = false },
	{ "lunarvim/Onedarker.nvim",   lazy = false },
	{ "rebelot/kanagawa.nvim",     lazy = false },
	{ 'folke/tokyonight.nvim',     lazy = false },
	{ 'Everblush/nvim',            name = 'everblush', lazy = false },
	{ 'sainnhe/edge',              lazy = false },
	{ 'Mofiqul/vscode.nvim',       priority = 1000,    lazy = false },
}
