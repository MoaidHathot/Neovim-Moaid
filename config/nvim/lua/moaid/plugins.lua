return {

	{ 'nvim-treesitter/nvim-treesitter', build = { ':TSUpdate' } },
	{
		'VonHeikemen/lsp-zero.nvim',
		branch = 'v2.x',
		dependencies = {
			-- LSP Support
			{ 'neovim/nvim-lspconfig' }, -- Required
			{
				-- Optional
				'williamboman/mason.nvim',
				build = function()
					pcall(vim.cmd, 'MasonUpdate')
				end,
			},
			{ 'williamboman/mason-lspconfig.nvim' }, -- Optional

			-- Autocompletion
			{ 'hrsh7th/nvim-cmp' }, -- Required
			{ 'hrsh7th/cmp-nvim-lsp' }, -- Required
			{ 'L3MON4D3/LuaSnip' }, -- Required
		},
	},
	'hrsh7th/cmp-path',
	'hrsh7th/cmp-buffer',
	'hrsh7th/cmp-cmdline',
	'hrsh7th/cmp-nvim-lua',
	'hrsh7th/cmp-nvim-lsp-signature-help',
	'saadparwaiz1/cmp_luasnip',
	'Issafalcon/lsp-overloads.nvim',
	'neovim/nvim-lspconfig',
	"ray-x/lsp_signature.nvim",
	'OmniSharp/omnisharp-vim',

	'mfussenegger/nvim-dap',
	{ "rcarriga/nvim-dap-ui",            dependencies = { "mfussenegger/nvim-dap" } },
	{ 'akinsho/bufferline.nvim',         dependencies = { 'nvim-tree/nvim-web-devicons' }, version = "*" },
	"folke/neodev.nvim",
	'ThePrimeagen/harpoon',
	'mbbill/undotree',
	'tpope/vim-fugitive',
	'github/copilot.vim',
	'tpope/vim-surround',
	'tpope/vim-repeat',
	"Tastyep/structlog.nvim",
	'rcarriga/nvim-notify',
	'RRethy/vim-illuminate',
	"lukas-reineke/indent-blankline.nvim",
	'numToStr/Comment.nvim',
	"windwp/nvim-autopairs",
	'karb94/neoscroll.nvim',
	'norcalli/nvim-colorizer.lua',
	'HiPhish/nvim-ts-rainbow2',
	{ 'nvim-telescope/telescope.nvim', dependencies = { 'nvim-lua/plenary.nvim' }, version = '0.1.1' },
	{ "Shatur/neovim-session-manager", dependencies = { "nvim-lua/plenary.nvim" } },
	{
		"nvim-telescope/telescope-file-browser.nvim",
		dependencies = {
			"nvim-telescope/telescope.nvim",
			"nvim-lua/plenary.nvim"
		}
	},
	{
		'nvim-telescope/telescope-project.nvim',
		dependencies = {
			'nvim-telescope/telescope.nvim',
			'nvim-telescope/telescope-file-browser.nvim'
		}
	},
	'nvim-telescope/telescope-ui-select.nvim',
	{ 'nvim-tree/nvim-tree.lua',   dependencies = { 'nvim-tree/nvim-web-devicons' } },
	'lewis6991/gitsigns.nvim',
	"folke/which-key.nvim",
	'lvimuser/lsp-inlayhints.nvim',
	'L3MON4D3/LuaSnip',
	"rafamadriz/friendly-snippets",
	"b0o/schemastore.nvim",
	'dstein64/vim-startuptime',
	"ellisonleao/glow.nvim",
	{
		"folke/trouble.nvim",
		dependencies = {
			'nvim-telescope/telescope.nvim',
			"nvim-tree/nvim-web-devicons",
		}
	},
	{ 'goolord/alpha-nvim',        dependencies = { 'nvim-tree/nvim-web-devicons' } },
	{ 'nvim-lualine/lualine.nvim', dependencies = { 'nvim-tree/nvim-web-devicons' } },
	{ "akinsho/toggleterm.nvim",   version = '*' },
	{ "folke/todo-comments.nvim",  dependencies = "nvim-lua/plenary.nvim", },
	{ 'phaazon/hop.nvim',          branch = 'v2', },
	{
		"utilyre/barbecue.nvim",
		name = "barbecue",
		version = "*",
		dependencies = {
			"SmiteshP/nvim-navic",
			"nvim-tree/nvim-web-devicons", -- optional dependency
		}
	},
	{
		'andymass/vim-matchup',
		init = function()
			vim.g.matchup_matchparen_offscreen = { method = "popup" }
		end
	},

	--themes
	{ "catppuccin/nvim",         lazy = true },
	{ 'rose-pine/neovim',        lazy = true },
	{ 'LunarVim/lunar.nvim',     lazy = true },
	{ "lunarvim/Onedarker.nvim", lazy = true },
	{ "rebelot/kanagawa.nvim",   lazy = true },
	{ 'folke/tokyonight.nvim',   lazy = true },
	{ 'Everblush/nvim',          name = 'everblush', lazy = true },
	{ 'sainnhe/edge',            priority = 1000,    lazy = true }
}
