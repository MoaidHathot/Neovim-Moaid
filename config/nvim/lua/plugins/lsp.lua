return {
	{
		"williamboman/mason.nvim",
		-- event = "VeryLazy",
		-- lazy = true,
		-- event = { "BufReadPre", "BufNewFile" },
		cmd = { "Mason", "MasonUpdate" },
		-- version = "1.11.0",
		config = function()
			require('mason').setup({
				    registries = {
					"github:mason-org/mason-registry",
					"github:Crashdummyy/mason-registry",
				},
			})
		end
	},
	{
		"williamboman/mason-lspconfig.nvim",
		-- event = { "BufReadPre", "BufNewFile" },
		-- version = "1.32.0",
		dependencies = {
			"williamboman/mason.nvim",
			"neovim/nvim-lspconfig",
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
		"seblyng/roslyn.nvim",
		opts = {
			-- your configuration comes here; leave empty for default settings
		},
	},
	{
		"neovim/nvim-lspconfig",
		-- event = { "BufReadPre", "BufNewFile" },
		event = { "BufReadPost", "BufNewFile" },
		-- event = "VeryLazy",
		-- lazy = true,
		dependencies = {
			"williamboman/mason.nvim",
			-- "williamboman/mason-lspconfig.nvim",
		},
		config = function()
			vim.lsp.config.roslyn = {
				filetypes = { 'cs', 'vb', 'csproj', 'sln', 'slnx', 'props', 'csx', 'targets', 'tproj', 'slngen', 'fproj' },
				-- root_dir = vim.lsp.config.util.root_pattern(".git", "*.sln", "*.csproj"),
				-- root_dir = { '.git', '*.sln', '*.csproj' },
				settings = {
					roslyn = {
						enable_roslyn_analysers = true,
						enable_import_completion = true,
						organize_imports_on_format = true,
						enable_decompilation_support = true,
					},
					["csharp|projects"] = {
						dotnet_enable_file_based_programs = true,
					},
					["csharp|code_lens"] = {
						dotnet_enable_references_code_lens = false
					},
				}
			}
		end
	},
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
			vim.keymap.set('n', '<leader>lff', function() vim.lsp.buf.format({ async = true }) end, { desc = "Format document" })
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
			vim.keymap.set('n', 'K', vim.lsp.buf.hover, { desc = "LSP Hover" })
			vim.keymap.set('n', 'gd', vim.lsp.buf.definition, { desc = "Go to Definition" })
		end
	},
	{
		"jay-babu/mason-null-ls.nvim",
		-- event = { "BufReadPre", "BufNewFile" },
		event = { 'VeryLazy' },
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
