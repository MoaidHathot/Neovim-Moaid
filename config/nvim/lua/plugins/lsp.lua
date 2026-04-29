local roslyn_filetypes = { 'cs', 'vb', 'csproj', 'sln', 'slnx', 'props', 'csx', 'targets', 'tproj', 'slngen', 'fproj', 'razor' }

local function normalize_path(path)
	if not path or path == "" then
		return nil
	end

	return vim.fs.normalize(path)
end

local function common_prefix_len(left, right)
	left = (left or ""):lower()
	right = (right or ""):lower()

	local limit = math.min(#left, #right)
	local index = 1
	while index <= limit and left:sub(index, index) == right:sub(index, index) do
		index = index + 1
	end

	return index - 1
end

local function is_in_dir(path, dir)
	path = normalize_path(path)
	dir = normalize_path(dir)

	if not path or not dir then
		return false
	end

	path = path:lower()
	dir = dir:lower()

	return path == dir or path:sub(1, #dir + 1) == dir .. "/" or path:sub(1, #dir + 1) == dir .. "\\"
end

local function roslyn_target_score(target, current_dir, selected_solution)
	local target_dir = normalize_path(vim.fs.dirname(target)) or ""
	local score = common_prefix_len(current_dir, target_dir)

	if selected_solution and normalize_path(selected_solution) == normalize_path(target) then
		score = score + 1000000
	end

	if is_in_dir(current_dir, target_dir) then
		score = score + 10000 + #target_dir
	end

	if target:match("%.slnx$") then
		score = score + 1000
	elseif target:match("%.sln$") then
		score = score + 500
	elseif target:match("%.slnf$") then
		score = score + 250
	end

	return score
end

local function choose_roslyn_target(targets)
	local candidates = vim.deepcopy(targets)
	local current_file = vim.api.nvim_buf_get_name(0)
	local current_dir = normalize_path(vim.fs.dirname(current_file)) or vim.fn.getcwd()
	local selected_solution = vim.g.roslyn_nvim_selected_solution

	table.sort(candidates, function(left, right)
		local left_score = roslyn_target_score(left, current_dir, selected_solution)
		local right_score = roslyn_target_score(right, current_dir, selected_solution)

		if left_score ~= right_score then
			return left_score > right_score
		end

		return left < right
	end)

	return candidates[1]
end

local function roslyn_root_dir(bufnr, on_dir)
	local config = require("roslyn.config").get()
	if config.lock_target and vim.g.roslyn_nvim_selected_solution then
		on_dir(vim.fs.dirname(vim.g.roslyn_nvim_selected_solution))
		return
	end

	local buf_name = vim.api.nvim_buf_get_name(bufnr)
	if buf_name:match("^roslyn%-source%-generated://") then
		local existing_client = vim.lsp.get_clients({ name = "roslyn" })[1]
		if existing_client and existing_client.config.root_dir then
			on_dir(existing_client.config.root_dir)
			return
		end
	end

	local root_dir = require("roslyn.sln.utils").root_dir(bufnr)
	if root_dir then
		on_dir(root_dir)
		return
	end

	local fallback = vim.fs.root(bufnr, {
		"global.json",
		"Directory.Build.props",
		"Directory.Build.targets",
		"Directory.Packages.props",
		".git",
	}) or normalize_path(vim.fs.dirname(buf_name)) or vim.fn.getcwd()

	on_dir(fallback)
end

local function select_roslyn_target_broad()
	local config = require("roslyn.config").get()
	local broad_search = config.broad_search
	config.broad_search = true
	local ok, err = pcall(vim.cmd, "Roslyn target")
	config.broad_search = broad_search

	if not ok then
		error(err)
	end
end

local function toggle_roslyn_semantic_tokens(buf, client)
	buf = buf or vim.api.nvim_get_current_buf()
	client = client or vim.lsp.get_clients({ name = "roslyn", bufnr = buf })[1]

	if not client then
		vim.notify("Roslyn is not attached to this buffer", vim.log.levels.WARN, { title = "Roslyn" })
		return
	end

	local semantic_tokens_provider = vim.b[buf].roslyn_semantic_tokens_provider
	if not semantic_tokens_provider then
		vim.notify("Roslyn semantic tokens are not available", vim.log.levels.WARN, { title = "Roslyn" })
		return
	end

	if vim.b[buf].roslyn_semantic_tokens_enabled then
		vim.lsp.semantic_tokens.stop(buf, client.id)
		client.server_capabilities.semanticTokensProvider = nil
		vim.b[buf].roslyn_semantic_tokens_enabled = false
		vim.notify("Roslyn semantic tokens disabled", vim.log.levels.INFO, { title = "Roslyn" })
		return
	end

	client.server_capabilities.semanticTokensProvider = semantic_tokens_provider
	vim.b[buf].roslyn_semantic_tokens_enabled = true
	vim.lsp.semantic_tokens.start(buf, client.id)
	vim.notify("Roslyn semantic tokens enabled", vim.log.levels.INFO, { title = "Roslyn" })
end

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
		ft = roslyn_filetypes,
		cmd = "Roslyn",
		opts = {
			filewatching = "roslyn",
			broad_search = false,
			choose_target = choose_roslyn_target,
			lock_target = false,
		},
		config = function(_, opts)
			require("roslyn").setup(opts)

			vim.lsp.config("roslyn", {
				filetypes = roslyn_filetypes,
				root_dir = roslyn_root_dir,
				settings = {
					roslyn = {
						enable_roslyn_analysers = true,
						enable_import_completion = true,
						organize_imports_on_format = true,
						enable_decompilation_support = true,
					},
					["csharp|background_analysis"] = {
						dotnet_analyzer_diagnostics_scope = "openFiles",
						dotnet_compiler_diagnostics_scope = "openFiles",
					},
					["csharp|completion"] = {
						dotnet_show_completion_items_from_unimported_namespaces = true,
					},
					["csharp|formatting"] = {
						dotnet_organize_imports_on_format = true,
					},
					["csharp|projects"] = {
						dotnet_enable_file_based_programs = true,
					},
					["csharp|symbol_search"] = {
						dotnet_search_reference_assemblies = true,
					},
					["csharp|code_lens"] = {
						dotnet_enable_references_code_lens = false
					},
				}
			})
		end,
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
			vim.api.nvim_create_autocmd("LspAttach", {
				group = vim.api.nvim_create_augroup("moaid_lsp_attach", { clear = true }),
				callback = function(ev)
					local buf = ev.buf
					local client = vim.lsp.get_client_by_id(ev.data.client_id)
					local bopts = function(desc)
						return { buffer = buf, desc = desc, silent = true }
					end

					if client and client.name == "roslyn" then
						vim.b[buf].roslyn_semantic_tokens_provider = client.server_capabilities.semanticTokensProvider
						vim.b[buf].roslyn_semantic_tokens_enabled = client.server_capabilities.semanticTokensProvider ~= nil
						vim.keymap.set('n', '<leader>lT', select_roslyn_target_broad, bopts("Select Roslyn Target"))
						vim.keymap.set('n', '<leader>lR', '<cmd>Roslyn restart<CR>', bopts("Restart Roslyn"))
						vim.keymap.set('n', '<leader>lS', function()
							toggle_roslyn_semantic_tokens(buf, client)
						end, bopts("Toggle Roslyn Semantic Tokens"))
						vim.api.nvim_buf_create_user_command(buf, "RoslynSemanticTokensToggle", function()
							toggle_roslyn_semantic_tokens(buf, client)
						end, { desc = "Toggle Roslyn semantic tokens" })
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
