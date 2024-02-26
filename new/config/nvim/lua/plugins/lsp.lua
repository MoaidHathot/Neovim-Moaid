return {
	{
		"williamboman/mason.nvim",
		event = "VeryLazy",
		-- lazy = false,
		config = function()
			require('mason').setup()
		end
	},
	{
		"williamboman/mason-lspconfig.nvim",
		event = "VeryLazy",
		dependencies = {
			"williamboman/mason.nvim"
		},
		opts = {
			auto_install = true,
		},
		config = function()
			require('mason-lspconfig').setup({
				ensure_installed = { "lua_ls", "omnisharp" }
			})
		end
	},
	{
		"neovim/nvim-lspconfig",
		event = "VeryLazy",
		-- lazy = false,
		dependencies = {
			"williamboman/mason.nvim",
			"williamboman/mason-lspconfig.nvim",
		},
		config = function()
			local capabilities = require('cmp_nvim_lsp').default_capabilities()
			local lspconfig = require('lspconfig')

			lspconfig.lua_ls.setup({
				capabilities = capabilities
			})

			lspconfig.omnisharp.setup({
				capabilities = capabilities,
				enable_roslyn_analysers = true,
				enable_import_completion = true,
				organize_imports_on_format = true,
				filetypes = { 'cs', 'vb', 'csproj', 'sln', 'slnx', 'props', 'csx', 'props', 'targets' }
			})

			vim.keymap.set('n', 'K', vim.lsp.buf.hover, {})
			vim.keymap.set('n', 'gd', vim.lsp.buf.definition, {})
			-- vim.keymap.set({ 'n', 'v' }, '<leader>la', vim.lsp.buf.code_action, {})
		end
	},
	{
		'nvimtools/none-ls.nvim',
		event = "VeryLazy",
		config = function()
			local null_ls = require('null-ls')
			null_ls.setup({
				sources = {
					null_ls.builtins.formatting.stylua,
					null_ls.builtins.formatting.csharpier,
					null_ls.builtins.formatting.fixjson,
					null_ls.builtins.formatting.yamlfmt,
					null_ls.builtins.formatting.black,
					null_ls.builtins.formatting.isort,
				}
			})

			vim.keymap.set('n', '<leader>lff', vim.lsp.buf.format, {})
		end
	},
	{
		"jay-babu/mason-null-ls.nvim",
		event = { "BufReadPre", "BufNewFile" },
		dependencies = {
			"williamboman/mason.nvim",
			"nvimtools/none-ls.nvim",
			"neovim/nvim-lspconfig"
		},
		config = function()
			require('mason-null-ls').setup({
				automatic_setup = true
			})
		end,
	}
}
