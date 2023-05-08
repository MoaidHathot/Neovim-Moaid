-- This file can be loaded by calling `lua require('plugins')` from your init.vim
-- Only required if you have packer configured as `opt`
vim.cmd [[packadd packer.nvim]]
return require('packer').startup(function(use)
	-- Packer can manage itself
	use 'wbthomason/packer.nvim'

	use {
		'nvim-telescope/telescope.nvim'
		, tag = '0.1.1',
		requires = { { 'nvim-lua/plenary.nvim' } }
	}

	use({
		'rose-pine/neovim',
	})


	use('nvim-treesitter/nvim-treesitter', { run = ':TSUpdate' })
	use('nvim-treesitter/playground')
	use('ThePrimeagen/harpoon')
	use('mbbill/undotree')
	use('tpope/vim-fugitive')

	use {
		'VonHeikemen/lsp-zero.nvim',
		branch = 'v2.x',
		requires = {
			-- LSP Support
			{ 'neovim/nvim-lspconfig' }, -- Required
			{
				-- Optional
				'williamboman/mason.nvim',
				run = function()
					pcall(vim.cmd, 'MasonUpdate')
				end,
			},
			{ 'williamboman/mason-lspconfig.nvim' }, -- Optional

			-- Autocompletion
			{ 'hrsh7th/nvim-cmp' }, -- Required
			{ 'hrsh7th/cmp-nvim-lsp' }, -- Required
			{ 'L3MON4D3/LuaSnip' }, -- Required
		}
	}

	use { 'Issafalcon/lsp-overloads.nvim' }

	use { 'hrsh7th/cmp-path' }
	use { 'hrsh7th/cmp-buffer' }
	use { 'hrsh7th/cmp-cmdline' }
	use { 'hrsh7th/cmp-nvim-lua' }
	use { 'hrsh7th/cmp-nvim-lsp-signature-help' }
	use { 'saadparwaiz1/cmp_luasnip' }

	use { 'neovim/nvim-lspconfig' }

	use { "ray-x/lsp_signature.nvim" }

	use 'github/copilot.vim'

	use('OmniSharp/omnisharp-vim')

	use {
		'nvim-tree/nvim-tree.lua',
		requires = {
			'nvim-tree/nvim-web-devicons', -- optional
		},
	}

	use { 'mfussenegger/nvim-dap' }
	use { "rcarriga/nvim-dap-ui", requires = { "mfussenegger/nvim-dap" } }
	use "folke/neodev.nvim"

	use('tpope/vim-surround')

	use('tpope/vim-repeat')

	use {
		'phaazon/hop.nvim',
		branch = 'v2',
	}

	use {
		'lewis6991/gitsigns.nvim'
	}

	use {
		"folke/which-key.nvim",
	}

	use { 'akinsho/bufferline.nvim', tag = "*", requires = 'nvim-tree/nvim-web-devicons' }

	use {
		'goolord/alpha-nvim',
		requires = { 'nvim-tree/nvim-web-devicons' },
	}

	use {
		'numToStr/Comment.nvim',
	}

	use {
		"windwp/nvim-autopairs",
	}

	use {
		'nvim-lualine/lualine.nvim',
		requires = { 'nvim-tree/nvim-web-devicons', opt = true }
	}

	use { "akinsho/toggleterm.nvim", tag = '*' }

	use {
		"folke/todo-comments.nvim",
		requires = "nvim-lua/plenary.nvim",
	}

	use {
		"folke/trouble.nvim",
		requires = {
			{ 'nvim-telescope/telescope.nvim' },
			{ "nvim-tree/nvim-web-devicons" },
		}
	}

	use { "Tastyep/structlog.nvim" }

	use { 'rcarriga/nvim-notify' }

	use { 'RRethy/vim-illuminate' }
	use "lukas-reineke/indent-blankline.nvim"
	use { 'andymass/vim-matchup',
		setup = function()
			vim.g.matchup_matchparen_offscreen = { method = "popup" }
		end }

	use 'karb94/neoscroll.nvim'
	use { 'norcalli/nvim-colorizer.lua' }
	use 'HiPhish/nvim-ts-rainbow2'
	use 'lvimuser/lsp-inlayhints.nvim'
	use { 'L3MON4D3/LuaSnip' }
	use "rafamadriz/friendly-snippets"

	use "rebelot/kanagawa.nvim"
	use 'folke/tokyonight.nvim'

	use({
		"utilyre/barbecue.nvim",
		tag = "*",
		requires = {
			"SmiteshP/nvim-navic",
			"nvim-tree/nvim-web-devicons", -- optional dependency
		},
		after = "nvim-web-devicons", -- keep this if you're using NvChad
	})

	use 'LunarVim/lunar.nvim'
	use "lunarvim/Onedarker.nvim"
end)
