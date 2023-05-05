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
		as = 'rose-pine',
		config = function()
			vim.cmd('colorscheme rose-pine')
		end
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

	use { 'hrsh7th/cmp-path' }
	use { 'hrsh7th/cmp-buffer' }

	use { 'neovim/nvim-lspconfig' }

	use { "ray-x/lsp_signature.nvim" }

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
		'lewis6991/gitsigns.nvim',
		config = function()
			require('gitsigns').setup()
		end
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

	use {
		"SmiteshP/nvim-navic",
		requires = "neovim/nvim-lspconfig"
	}

	use { 'RRethy/vim-illuminate' }
	use "lukas-reineke/indent-blankline.nvim"
	use 'tamago324/nlsp-settings.nvim'
	use { 'andymass/vim-matchup',
		setup = function()
			vim.g.matchup_matchparen_offscreen = { method = "popup" }
		end }

	use 'karb94/neoscroll.nvim'
	use { 'norcalli/nvim-colorizer.lua' }
	use 'HiPhish/nvim-ts-rainbow2'
end)
