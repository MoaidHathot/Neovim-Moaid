return {
	{
		"williamboman/mason.nvim",
		-- event = "VeryLazy",
		lazy = true,
		config = function()
			require('mason').setup()
		end
	},
	{
		"williamboman/mason-lspconfig.nvim",
		-- event = "VeryLazy",
		lazy = true,
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
		event = { "BufReadPre", "BufNewFile" },
		-- event = "VeryLazy",
		-- lazy = true,
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
				enable_decompilation_support = true,
				filetypes = { 'cs', 'vb', 'csproj', 'sln', 'slnx', 'props', 'csx', 'props', 'targets' }
			})

			lspconfig.powershell_es.setup({
				capabilities = capabilities,
				bundle_path = vim.fn.stdpath("data") .. "/mason/packages/powershell-editor-services",
				init_options = {
					enableProfileLoading = false,
				}

			})

			lspconfig.pylsp.setup({
				capabilities = capabilities,
			})

			lspconfig.yamlls.setup({
				capabilities = capabilities
			})

			lspconfig.bufls.setup({
				capabilities = capabilities
			})

			lspconfig.bicep.setup({
				capabilities = capabilities
			})

			vim.keymap.set('n', 'K', vim.lsp.buf.hover, {})
			vim.keymap.set('n', 'gd', vim.lsp.buf.definition, {})
			-- vim.keymap.set({ 'n', 'v' }, '<leader>la', vim.lsp.buf.code_action, {})
		end
	},
	{
		'nvimtools/none-ls.nvim',
		-- event = { "BufReadPre", "BufNewFile" },
		lazy = true,
		-- event = "VeryLazy",
		config = function()
			local null_ls = require('null-ls')
			null_ls.setup({
				sources = {
					-- null_ls.builtins.formatting.stylua,
					null_ls.builtins.formatting.csharpier,
					null_ls.builtins.formatting.yamlfmt,
					null_ls.builtins.formatting.black,
					null_ls.builtins.formatting.isort,
				}
			})
			vim.keymap.set('n', '<leader>lff', function() vim.lsp.buf.format({ async = true }) end,
				{ desc = "Format document" })
			vim.keymap.set('n', '<leader>lr', vim.lsp.buf.rename, { desc = "Rename Symbol" })
			vim.keymap.set({ 'n', 'i' }, '<f2>', vim.lsp.buf.rename, { desc = "Rename Symbol" })
			vim.keymap.set({ 'n', 'i' }, '<f12>', vim.lsp.buf.definition, { desc = "Go to Definition" })
			vim.keymap.set({ 'n' }, '<leader>ld', vim.lsp.buf.definition, { desc = "Go to Definition" })
			vim.keymap.set('n', '<leader>li', vim.lsp.buf.implementation, { desc = "Go to Implementation" })
			vim.keymap.set('n', '<leader>lh', vim.lsp.buf.signature_help, { desc = "Signature Help" })
			vim.keymap.set('n', '<leader>lsR', vim.lsp.buf.references, { desc = "To to References" })
			vim.keymap.set({ 'n' }, '<leader>lsD', ":TroubleToggle document_diagnostics<CR>",
				{ desc = "Toggle Document Diagnostics" })
			vim.keymap.set('n', '<leader>lsI', ':TroubleToggle lsp_implementations<CR>',
				{ desc = "Toggle LSP References" })
			vim.keymap.set('n', '<leader>lsd', ":TroubleToggle lsp_definitions<CR>", { desc = "Toggle LSP Definitions" })
		end
	},
	{
		"jay-babu/mason-null-ls.nvim",
		event = { "BufReadPre", "BufNewFile" },
		-- event = { 'VeryLazy' },
		-- enabled = false,
		dependencies = {
			"williamboman/mason.nvim",
			"nvimtools/none-ls.nvim",
			-- "neovim/nvim-lspconfig"
		},
		config = function()
			require('mason-null-ls').setup({
				automatic_setup = true
			})
		end,
	},
	{
		'https://git.sr.ht/~whynothugo/lsp_lines.nvim',
		event = "VeryLazy",
		config = function()
			require('lsp_lines').setup()

			vim.diagnostic.config({
				virtual_lines = false,
				virtual_text = true,
			})

			local function toggleLines()
				local new_value = not vim.diagnostic.config().virtual_lines
				vim.diagnostic.config({ virtual_lines = new_value, virtual_text = not new_value })
				return new_value
			end

			vim.keymap.set('n', '<leader>lu', toggleLines, { desc = "Toggle Underline Diagnostics", silent = true })
		end
	}
}
