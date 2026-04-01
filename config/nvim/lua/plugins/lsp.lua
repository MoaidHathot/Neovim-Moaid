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
		event = "VeryLazy",
		-- version = "1.32.0",
		dependencies = {
			"williamboman/mason.nvim",
			"neovim/nvim-lspconfig",
		},
		opts = {
			auto_install = false,
		},
	},
	{
		"seblyng/roslyn.nvim",
		ft = { "cs", "vb", "csproj", "sln", "slnx", "props", "csx", "targets", "trpoj", "fproj" },
		opts = {
			-- your configuration comes here; leave empty for default settings
		},
	},
	{
		"neovim/nvim-lspconfig",
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

			vim.api.nvim_create_autocmd("LspAttach", {
				group = vim.api.nvim_create_augroup("moaid_lsp_attach", { clear = true }),
				callback = function(ev)
					local buf = ev.buf
					local bopts = function(desc)
						return { buffer = buf, desc = desc, silent = true }
					end

					vim.keymap.set('n', '<leader>lff', function() vim.lsp.buf.format({ async = true }) end, bopts("Format document"))
					vim.keymap.set('n', '<leader>lr', vim.lsp.buf.rename, bopts("Rename Symbol"))
					vim.keymap.set({ 'n', 'i' }, '<f2>', vim.lsp.buf.rename, bopts("Rename Symbol"))
					vim.keymap.set({ 'n', 'i' }, '<f12>', vim.lsp.buf.definition, bopts("Go to Definition"))
					vim.keymap.set('n', '<leader>ld', vim.lsp.buf.definition, bopts("Go to Definition"))
					vim.keymap.set('n', '<leader>li', vim.lsp.buf.implementation, bopts("Go to Implementation"))
					vim.keymap.set('n', '<leader>lh', vim.lsp.buf.signature_help, bopts("Signature Help"))
					vim.keymap.set('n', '<leader>lsR', vim.lsp.buf.references, bopts("Go to References"))
					-- vim.keymap.set({ 'n' }, '<leader>lsD', ":Trouble document_diagnostics<CR>", bopts("Toggle Document Diagnostics"))
					vim.keymap.set('n', '<leader>lsD', ":Trouble diagnostics<CR>", bopts("Toggle Document Diagnostics"))
					vim.keymap.set('n', '<leader>lsI', ':Trouble lsp_implementations<CR>', bopts("Toggle LSP Implementations"))
					vim.keymap.set('n', '<leader>lsd', ":Trouble lsp_definitions<CR>", bopts("Toggle LSP Definitions"))
					vim.keymap.set('n', 'K', vim.lsp.buf.hover, bopts("LSP Hover"))
					vim.keymap.set('n', 'gd', vim.lsp.buf.definition, bopts("Go to Definition"))
				end,
			})
		end
	},
	{
		'nvimtools/none-ls.nvim',
		-- event = { "BufReadPre", "BufNewFile" },
		-- lazy = true,
		enabled = false,
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
		end
	},
	{
		"jay-babu/mason-null-ls.nvim",
		-- event = { "BufReadPre", "BufNewFile" },
		event = { 'VeryLazy' },
		enabled = false,
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
		event = { "BufReadPost", "BufNewFile" },
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
