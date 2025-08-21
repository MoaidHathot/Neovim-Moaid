return {
	{
		"williamboman/mason.nvim",
		-- event = "VeryLazy",
		-- lazy = true,
		-- event = { "BufReadPre", "BufNewFile" },
		cmd = { "Mason", "MasonUpdate" },
		version = "1.11.0",
		config = function()
			require('mason').setup()
		end
	},
	{
		"williamboman/mason-lspconfig.nvim",
		-- event = "VeryLazy",
		-- lazy = true,
		-- event = { "BufReadPre", "BufNewFile" },
		event = { "BufReadPost", "BufNewFile" },
		version = "1.32.0",
		dependencies = {
			"williamboman/mason.nvim"
		},
		opts = {
			auto_install = false,
		},
		config = function()
			require('mason-lspconfig').setup({
				-- ensure_installed = { "lua_ls", "omnisharp", "bicep" }
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
				filetypes = { 'cs', 'vb', 'csproj', 'sln', 'slnx', 'props', 'csx', 'targets', 'tproj', 'slngen', 'fproj' },
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

			lspconfig.buf_ls.setup({
				capabilities = capabilities
			})

			lspconfig.bicep.setup({
				capabilities = capabilities
			})

			lspconfig.lemminx.setup({
				capabilities = capabilities
			})

			lspconfig.eslint.setup({
				capabilities = capabilities
			})

			lspconfig.ts_ls.setup({
				capabilities = capabilities
			})

			lspconfig.tsp_server.setup({
				capabilities = capabilities
			})


			vim.keymap.set('n', 'K', vim.lsp.buf.hover, {})
			vim.keymap.set('n', 'gd', vim.lsp.buf.definition, {})
			-- vim.keymap.set({ 'n', 'v' }, '<leader>la', vim.lsp.buf.code_action, {})
		end
	},
	-- {
	-- 	"neovim/nvim-lspconfig",
	-- 	event = { "BufReadPre", "BufNewFile" },
	-- 	dependencies = {
	-- 		"williamboman/mason.nvim",
	-- 		"williamboman/mason-lspconfig.nvim",
	-- 	},
	-- 	config = function()
	-- 		local capabilities = require('cmp_nvim_lsp').default_capabilities()
	-- 		local function get_capabilities()
	-- 			return capabilities
	-- 			-- return require('cmp_nvim_lsp').default_capabilities()
	-- 		end
	-- 		-- local capabilities = nil
	-- 		-- local get_capabilities = function()
	-- 		-- 	if capabilities == nil then
	-- 		-- 		capabilities = get_default_capabilities()
	-- 		-- 	end
	--
	-- 		-- 	return capabilities
	-- 		-- end
	-- 		local lspconfig = require('lspconfig')
	--
	-- 		-- Lazy load only when opening relevant filetypes
	-- 		local function setup(server, config)
	-- 			local ft = config.filetypes or {}
	-- 			vim.api.nvim_create_autocmd("FileType", {
	-- 				pattern = ft,
	-- 				callback = function()
	-- 					lspconfig[server].setup(config)
	-- 				end,
	-- 				once = true,
	-- 			})
	-- 		end
	--
	-- 		setup("omnisharp", {
	-- 			capabilities = get_capabilities(),
	-- 			filetypes = { 'cs', 'vb', 'csproj', 'sln', 'slnx', 'props', 'csx', 'targets', 'tproj', 'slngen', 'fproj' },
	-- 			-- enable_roslyn_analysers = true,
	-- 			-- enable_import_completion = true,
	-- 			-- organize_imports_on_format = true,
	-- 			-- enable_decompilation_support = true,
	-- 			-- cmd = { "omnisharp", "--languageserver", "--hostPID", tostring(vim.fn.getpid()), "DotNet:enablePackageRestore=false", "--encoding", "utf-8", "--languageserver", "FormattingOptions:EnableEditorConfigSupport=true", "Sdk:IncludePrereleases=true" },
	-- 			-- root_dir = lspconfig.util.root_pattern("*.csproj", "*.sln"),
	-- 			settings = {
	-- 				RoslynExtensionsOptions = {
	-- 					enableDecompilationSupport = true,
	-- 					enableImportCompletion = true,
	-- 					enableAnalyzersSupport = true,
	-- 					organizeImportsOnFormat = true,
	-- 				}
	-- 			},
	--
	-- 		})
	-- 		setup("powershell_es", {
	-- 			capabilities = get_capabilities(),
	-- 			filetypes = { "ps1" },
	-- 			bundle_path = vim.fn.stdpath("data") .. "/mason/packages/powershell-editor-services",
	-- 			init_options = {
	-- 				enableProfileLoading = false,
	-- 			}
	-- 		})
	-- 		setup("lua_ls", { capabilities = get_capabilities(), filetypes = { "lua" } })
	-- 		setup("pylsp", { capabilities = get_capabilities(), filetypes = { "py" } })
	-- 		setup("bicep", { capabilities = get_capabilities(), filetypes = { "bicep" } })
	-- 		setup("buf_ls", { capabilities = get_capabilities(), filetypes = { "proto" } })
	-- 		setup("yamlls", { capabilities = get_capabilities(), filetypes = { "yaml", "yml" } })
	-- 	end
	-- },
	{
		'nvimtools/none-ls.nvim',
		-- event = { "BufReadPre", "BufNewFile" },
		-- lazy = true,
		event = { "BufReadPre", "BufNewFile" },
		-- event = "VeryLazy",
		config = function()
			local null_ls = require('null-ls')
			null_ls.setup({
				sources = {
					-- null_ls.builtins.formatting.stylua,
					-- null_ls.builtins.formatting.csharpier,
					-- null_ls.builtins.formatting.yamlfmt,
					-- null_ls.builtins.formatting.black,
					-- null_ls.builtins.formatting.isort,
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
			-- vim.keymap.set({ 'n' }, '<leader>lsD', ":Trouble document_diagnostics<CR>", { desc = "Toggle Document Diagnostics" })
			vim.keymap.set({ 'n' }, '<leader>lsD', ":Trouble diagnostics<CR>", { desc = "Toggle Document Diagnostics" })
			vim.keymap.set('n', '<leader>lsI', ':Trouble lsp_implementations<CR>', { desc = "Toggle LSP References" })
			vim.keymap.set('n', '<leader>lsd', ":Trouble lsp_definitions<CR>", { desc = "Toggle LSP Definitions" })
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
		-- event = "VeryLazy",
		event = { "BufReadPre", "BufNewFile" },
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
	},
}
